# shellcheck shell=bash
# shellcheck disable=SC2154,SC2016
# =============================================================================
#  relay.sh · 出站链式中转（SOCKS5 / Shadowsocks）
#  模型：节点 inbound → route 规则 → 上游 outbound → 目标
# =============================================================================

RELAY_SS_METHODS='aes-128-gcm aes-256-gcm chacha20-ietf-poly1305 2022-blake3-aes-128-gcm 2022-blake3-aes-256-gcm 2022-blake3-chacha20-poly1305'

relay_validate_method() {
  local method=$1 m
  for m in ${RELAY_SS_METHODS}; do
    if [[ ${m} == "${method}" ]]; then
      return 0
    fi
  done
  return 1
}

relay_create() {
  local type=$1 name=${2:-} server=${3:-} port=${4:-} username=${5:-} password=${6:-} method=${7:-}

  case ${type} in
    socks5 | shadowsocks) ;;
    *)
      sbqd_err "$(sbqd_t '不支持的中转类型：%s（仅 socks5 / shadowsocks）' \
        'unsupported upstream type: %s (socks5 / shadowsocks only)' "${type}")"
      return 1
      ;;
  esac

  if [[ -z ${server} ]]; then
    sbqd_err "$(sbqd_t '上游地址不能为空' 'upstream server cannot be empty')"
    return 1
  fi
  if ! sbqd_is_port "${port}"; then
    sbqd_err "$(sbqd_t '上游端口不合法：%s' 'invalid upstream port: %s' "${port}")"
    return 1
  fi
  if [[ -z ${name} ]]; then
    name="${type}-${server}"
  fi

  if [[ ${type} == 'shadowsocks' ]]; then
    if [[ -z ${method} ]] || ! relay_validate_method "${method}"; then
      sbqd_err "$(sbqd_t 'Shadowsocks 加密方式不合法：%s' 'invalid Shadowsocks method: %s' "${method:-empty}")"
      sbqd_err "$(sbqd_t '可选：%s' 'available: %s' "${RELAY_SS_METHODS}")"
      return 1
    fi
    if [[ -z ${password} ]]; then
      sbqd_err "$(sbqd_t 'Shadowsocks 密码不能为空' 'Shadowsocks password cannot be empty')"
      return 1
    fi
  fi

  local id payload
  id=$(state_alloc_id next_upstream_id)
  payload=$(jq -nc \
    --argjson id "${id}" --arg type "${type}" --arg name "${name}" \
    --arg server "${server}" --argjson port "${port}" \
    --arg username "${username}" --arg password "${password}" \
    --arg method "${method}" --arg at "$(sbqd_iso_now)" '{
      id: $id, type: $type, name: $name, server: $server, port: $port,
      username: $username, password: $password, method: $method,
      created_at: $at
    }')

  state_add_upstream "${payload}"
  sbqd_ok "$(sbqd_t '已添加上游 #%s：%s' 'upstream #%s added: %s' "${id}" "${name}")"
  if [[ ${SBQD_JSON_OUT:-0} == 1 ]]; then
    jq -c . <<< "${payload}"
  fi
}

relay_list() {
  local upstream id type name server port used
  local -a rows=()
  if [[ $(state_upstream_count) == '0' ]]; then
    sbqd_info "$(sbqd_t '还没有中转上游' 'no upstream relay yet')"
    return 0
  fi

  while IFS= read -r upstream; do
    id=$(jq -r '.id' <<< "${upstream}")
    type=$(jq -r '.type' <<< "${upstream}")
    name=$(jq -r '.name' <<< "${upstream}")
    server=$(jq -r '.server' <<< "${upstream}")
    port=$(jq -r '.port' <<< "${upstream}")
    used=$(jq -r --argjson id "${id}" '[.nodes[] | select(.upstream_id == $id)] | length' "${SBQD_STATE_FILE}")
    rows+=("${id}|${type}|${name}|${server}:${port}|${used}")
  done < <(jq -c '.upstreams[]' "${SBQD_STATE_FILE}")

  ui_table "$(sbqd_t 'ID|类型|名称|地址|使用节点' 'ID|Type|Name|Address|Nodes')" "${rows[@]}"
}

relay_delete() {
  local id=$1 assume_yes=${2:-0}
  if ! [[ ${id} =~ ^[0-9]+$ ]] || [[ -z $(state_upstream_json "${id}") ]]; then
    sbqd_err "$(sbqd_t '上游不存在：%s' 'upstream does not exist: %s' "${id}")"
    return 1
  fi

  local used
  used=$(jq -r --argjson id "${id}" '[.nodes[] | select(.upstream_id == $id)] | length' "${SBQD_STATE_FILE}")
  if ((used > 0)); then
    sbqd_warn "$(sbqd_t '有 %s 个节点正在使用该上游，删除后将改为直连' \
      '%s nodes use this upstream and will fall back to direct' "${used}")"
  fi

  if [[ ${assume_yes} != '1' ]] &&
    ! sbqd_confirm "$(sbqd_t '确认删除上游 #%s？' 'delete upstream #%s?' "${id}")" \
      'Delete this upstream?' 'n'; then
    return 1
  fi

  cp -f -- "${SBQD_STATE_FILE}" "${SBQD_TMP}/state-before-upstream-delete.json"
  state_update '.upstreams = [.upstreams[] | select(.id != $id)] |
    .nodes = [.nodes[] | if .upstream_id == $id then .upstream_id = 0 else . end]' \
    --argjson id "${id}"
  if ! config_apply; then
    cp -f -- "${SBQD_TMP}/state-before-upstream-delete.json" "${SBQD_STATE_FILE}"
    return 1
  fi
  sbqd_ok "$(sbqd_t '已删除上游 #%s' 'upstream #%s deleted' "${id}")"
}

# 连通性测试：TCP 可达性 + SOCKS5 代理请求
relay_test() {
  local id=$1 upstream type server port username password
  if ! [[ ${id} =~ ^[0-9]+$ ]] || [[ -z $(state_upstream_json "${id}") ]]; then
    sbqd_err "$(sbqd_t '上游不存在：%s' 'upstream does not exist: %s' "${id}")"
    return 1
  fi
  upstream=$(state_upstream_json "${id}")
  type=$(jq -r '.type' <<< "${upstream}")
  server=$(jq -r '.server' <<< "${upstream}")
  port=$(jq -r '.port' <<< "${upstream}")
  username=$(jq -r '.username // empty' <<< "${upstream}")
  password=$(jq -r '.password // empty' <<< "${upstream}")

  printf '  %s TCP %s:%s ... ' "$(sbqd_t '连接' 'connect')" "${server}" "${port}"
  if timeout 6 bash -c "exec 3<>/dev/tcp/${server}/${port}" 2> /dev/null; then
    printf '%s\n' "$(ui_badge "$(sbqd_t '可达' 'reachable')" "${SBQD_C_GREEN}")"
  else
    printf '%s\n' "$(ui_badge "$(sbqd_t '不可达' 'unreachable')" "${SBQD_C_RED}")"
    return 1
  fi

  if [[ ${type} == 'socks5' ]] && sbqd_has_cmd curl; then
    local proxy code
    if [[ -n ${username} ]]; then
      proxy="socks5h://${username}:${password}@${server}:${port}"
    else
      proxy="socks5h://${server}:${port}"
    fi
    printf '  %s SOCKS5 %s ... ' "$(sbqd_t '验证' 'verify')" "$(sbqd_t '代理' 'proxy')"
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 --proxy "${proxy}" \
      'https://www.gstatic.com/generate_204' 2> /dev/null) || code='000'
    if [[ ${code} == '204' || ${code} == '200' ]]; then
      printf '%s\n' "$(ui_badge 'OK' "${SBQD_C_GREEN}")"
    else
      printf '%s\n' "$(ui_badge "$(sbqd_t '失败（%s）' 'failed (%s)' "${code}")" "${SBQD_C_YELLOW}")"
    fi
  elif [[ ${type} == 'shadowsocks' ]]; then
    sbqd_info "$(sbqd_t 'Shadowsocks 连通性将在节点流量中验证' \
      'Shadowsocks connectivity will be verified through node traffic')"
  fi
  return 0
}

relay_add_interactive() {
  local type name server port username password method

  ui_section "$(sbqd_t '选择中转类型' 'Choose relay type')"
  ui_item 1 'SOCKS5' ''
  ui_item 2 'Shadowsocks' ''
  ui_item 0 "$(sbqd_t '返回' 'Back')" ''
  ui_ask
  case ${REPLY} in
    1) type='socks5' ;;
    2) type='shadowsocks' ;;
    *) return 0 ;;
  esac

  sbqd_prompt "$(sbqd_t '名称' 'Name')" 'Name' "${type}-relay"
  name=${REPLY}
  sbqd_prompt "$(sbqd_t '服务器地址' 'Server address')" 'Server address' ''
  server=${REPLY}
  sbqd_prompt "$(sbqd_t '端口' 'Port')" 'Port' '1080'
  port=${REPLY}

  if [[ ${type} == 'socks5' ]]; then
    sbqd_prompt "$(sbqd_t '用户名（可留空）' 'Username (optional)')" 'Username (optional)' ''
    username=${REPLY}
    if [[ -n ${username} ]]; then
      sbqd_prompt_secret "$(sbqd_t '密码' 'Password')" 'Password'
      password=${REPLY}
    else
      password=''
    fi
    method=''
  else
    sbqd_prompt "$(sbqd_t '加密方式' 'Method')" 'Method' 'aes-128-gcm'
    method=${REPLY}
    sbqd_prompt_secret "$(sbqd_t '密码' 'Password')" 'Password'
    password=${REPLY}
    username=''
  fi

  relay_create "${type}" "${name}" "${server}" "${port}" "${username}" "${password}" "${method}"
}

relay_assign_interactive() {
  local node_id=$1 id name i=1
  if [[ -z $(jq -r '.upstreams[]' "${SBQD_STATE_FILE}") ]]; then
    sbqd_err "$(sbqd_t '还没有中转上游' 'no upstream relay yet')"
    return 1
  fi

  ui_section "$(sbqd_t '选择上游' 'Choose upstream')"
  ui_item 0 "$(sbqd_t '直连（取消中转）' 'Direct (no relay)')" ''
  while IFS='|' read -r id name; do
    ui_item "${i}" "#${id} ${name}" ''
    i=$((i + 1))
  done < <(jq -r '.upstreams[] | "\(.id)|\(.name)"' "${SBQD_STATE_FILE}")

  ui_ask
  if [[ ${REPLY} == '0' ]]; then
    nodes_set_upstream "${node_id}" 0
    return
  fi
  if ! [[ ${REPLY} =~ ^[0-9]+$ ]]; then
    return 1
  fi
  local chosen
  chosen=$(jq -r --argjson n "${REPLY}" '.upstreams[$n - 1].id' "${SBQD_STATE_FILE}")
  if [[ -z ${chosen} || ${chosen} == 'null' ]]; then
    return 1
  fi
  nodes_set_upstream "${node_id}" "${chosen}"
}
