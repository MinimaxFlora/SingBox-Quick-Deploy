# shellcheck shell=bash
# shellcheck disable=SC2154,SC2016
# =============================================================================
#  nodes.sh · 节点管理
#  支持：VLESS+Reality+Vision / Hysteria2 / AnyTLS / TUIC v5 / VMess+WS+TLS
#  同类型节点可重复添加，端口随机高端口并自动避让冲突
# =============================================================================

nodes_type_label() {
  case $1 in
    vless-reality) printf 'VLESS Reality Vision' ;;
    hysteria2) printf 'Hysteria2' ;;
    anytls) printf 'AnyTLS' ;;
    tuic) printf 'TUIC v5' ;;
    vmess-ws) printf 'VMess WS TLS' ;;
    *) printf '%s' "$1" ;;
  esac
}

nodes_type_short() {
  case $1 in
    vless-reality) printf 'reality' ;;
    hysteria2) printf 'hy2' ;;
    anytls) printf 'anytls' ;;
    tuic) printf 'tuic' ;;
    vmess-ws) printf 'vmess' ;;
    *) printf '%s' "$1" ;;
  esac
}

nodes_type_needs_domain() {
  case $1 in
    vless-reality) return 1 ;;
    hysteria2 | anytls | tuic | vmess-ws) return 0 ;;
    *) return 1 ;;
  esac
}

nodes_type_transport() {
  case $1 in
    hysteria2 | tuic) printf 'udp' ;;
    *) printf 'tcp' ;;
  esac
}

nodes_port_free() {
  local port=$1 proto=$2 reserved
  if sbqd_port_in_use "${port}" "${proto}"; then
    return 1
  fi
  if [[ -n $(jq -r --argjson p "${port}" '.nodes[] | select(.port == $p) | .id' "${SBQD_STATE_FILE}") ]]; then
    return 1
  fi
  reserved=$(state_value '.settings.subscription.port' '0')
  if [[ ${reserved} =~ ^[0-9]+$ ]] && ((reserved == port)); then
    return 1
  fi
  reserved=$(state_value '.settings.clash_api.port' '0')
  if [[ ${reserved} =~ ^[0-9]+$ ]] && ((reserved == port)); then
    return 1
  fi
  return 0
}

nodes_pick_port() {
  local proto=$1 port i=0
  while ((i < 300)); do
    port=$(sbqd_rand_port)
    if nodes_port_free "${port}" "${proto}"; then
      printf '%s' "${port}"
      return 0
    fi
    i=$((i + 1))
  done
  sbqd_die "$(sbqd_t '无法找到空闲端口，请调整端口范围' 'no free port found, adjust the port range')"
}

nodes_validate_type() {
  case $1 in
    vless-reality | hysteria2 | anytls | tuic | vmess-ws) return 0 ;;
    *) return 1 ;;
  esac
}

nodes_generate_params() {
  local type=$1 extras=${2:-'{}'}
  local uuid password obfs_password ws_path

  case ${type} in
    vless-reality)
      kernel_generate_reality_keypair
      uuid=$(kernel_generate_uuid)
      jq -nc --arg uuid "${uuid}" \
        --arg pk "${SBQD_REALITY_PRIVATE}" --arg pub "${SBQD_REALITY_PUBLIC}" \
        --arg sid "$(kernel_generate_short_id)" \
        --arg hs "${SBQD_NODE_HANDSHAKE:-www.microsoft.com}" \
        --argjson extras "${extras}" '{
          uuid: $uuid,
          private_key: $pk,
          public_key: $pub,
          short_id: $sid,
          flow: "xtls-rprx-vision",
          handshake_server: $hs,
          handshake_port: 443,
          server_name: $hs
        } + $extras'
      ;;
    hysteria2)
      password=$(kernel_generate_password)
      obfs_password=$(kernel_generate_password)
      jq -nc --arg pw "${password}" --arg oob "${obfs_password}" \
        --argjson extras "${extras}" '{
          password: $pw,
          obfs: true,
          obfs_password: $oob
        } + $extras'
      ;;
    anytls)
      password=$(kernel_generate_password)
      jq -nc --arg pw "${password}" --argjson extras "${extras}" \
        '{password: $pw} + $extras'
      ;;
    tuic)
      uuid=$(kernel_generate_uuid)
      password=$(kernel_generate_password)
      jq -nc --arg uuid "${uuid}" --arg pw "${password}" \
        --argjson extras "${extras}" '{
          uuid: $uuid,
          password: $pw,
          congestion_control: "bbr",
          zero_rtt: false
        } + $extras'
      ;;
    vmess-ws)
      uuid=$(kernel_generate_uuid)
      ws_path="/ws-$(sbqd_rand_hex 6)"
      jq -nc --arg uuid "${uuid}" --arg path "${ws_path}" \
        --argjson extras "${extras}" '{
          uuid: $uuid,
          ws_path: $path
        } + $extras'
      ;;
    *)
      return 1
      ;;
  esac
}

# 非交互创建：type name port domain upstream_id
nodes_create() {
  local type=$1 name=${2:-} port=${3:-} domain=${4:-} upstream_id=${5:-0}
  local proto params id node payload

  if ! nodes_validate_type "${type}"; then
    sbqd_err "$(sbqd_t '不支持的节点类型：%s' 'unsupported node type: %s' "${type}")"
    return 1
  fi

  state_require
  kernel_installed || {
    sbqd_err "$(sbqd_t 'sing-box 尚未安装，请先运行 sbqd install' 'sing-box is not installed, run sbqd install first')"
    return 1
  }

  if nodes_type_needs_domain "${type}"; then
    if [[ -z ${domain} ]]; then
      sbqd_err "$(sbqd_t '%s 需要域名与 TLS 证书，请先添加域名' \
        '%s requires a domain and TLS certificate, add a domain first' "$(nodes_type_label "${type}")")"
      return 1
    fi
    if ! state_domain_exists "${domain}"; then
      sbqd_err "$(sbqd_t '域名未托管：%s' 'domain not managed: %s' "${domain}")"
      return 1
    fi
    if ! cert_files_ok "${domain}"; then
      sbqd_err "$(sbqd_t '域名 %s 的证书文件缺失，请重新签发' \
        'certificate files missing for %s, re-issue it' "${domain}")"
      return 1
    fi
  else
    domain=''
  fi

  if [[ -n ${upstream_id} && ${upstream_id} != '0' ]]; then
    if ! [[ ${upstream_id} =~ ^[0-9]+$ ]] || [[ -z $(state_upstream_json "${upstream_id}") ]]; then
      sbqd_err "$(sbqd_t '上游不存在：%s' 'upstream does not exist: %s' "${upstream_id}")"
      return 1
    fi
  fi

  proto=$(nodes_type_transport "${type}")
  if [[ -z ${port} ]]; then
    port=$(nodes_pick_port "${proto}")
  elif ! sbqd_is_port "${port}"; then
    sbqd_err "$(sbqd_t '端口不合法：%s' 'invalid port: %s' "${port}")"
    return 1
  elif ! nodes_port_free "${port}" "${proto}"; then
    sbqd_err "$(sbqd_t '端口 %s 已被占用' 'port %s is already in use' "${port}")"
    return 1
  fi

  if [[ -z ${name} ]]; then
    name="$(nodes_type_label "${type}")-$(state_node_count | awk '{print $1 + 1}')"
  fi
  name=${name//|/-}

  params=$(nodes_generate_params "${type}") || return 1
  id=$(state_alloc_id next_node_id)

  payload=$(jq -nc \
    --argjson id "${id}" --arg type "${type}" --arg name "${name}" \
    --argjson port "${port}" --arg domain "${domain}" \
    --argjson upstream "${upstream_id}" --argjson params "${params}" \
    --arg at "$(sbqd_iso_now)" '{
      id: $id, type: $type, name: $name, port: $port,
      enabled: true, domain: $domain, upstream_id: $upstream,
      params: $params, created_at: $at
    }')

  cp -f -- "${SBQD_STATE_FILE}" "${SBQD_TMP}/state-before-node.json"
  state_add_node "${payload}"

  if ! config_apply; then
    cp -f -- "${SBQD_TMP}/state-before-node.json" "${SBQD_STATE_FILE}"
    sbqd_err "$(sbqd_t '节点创建失败，状态已回滚' 'node creation failed, state rolled back')"
    return 1
  fi

  sbqd_ok "$(sbqd_t '已添加 %s #%s（端口 %s）' \
    'added %s #%s (port %s)' "$(nodes_type_label "${type}")" "${id}" "${port}")"

  if [[ ${SBQD_JSON_OUT:-0} == 1 ]]; then
    jq -c . <<< "${payload}"
  else
    share_node_uri "$(state_node_json "${id}")"
    printf '\n'
  fi
}

nodes_list_rows() {
  local node id type name port domain upid enabled upstream status
  while IFS= read -r node; do
    id=$(jq -r '.id' <<< "${node}")
    type=$(jq -r '.type' <<< "${node}")
    name=$(jq -r '.name' <<< "${node}")
    port=$(jq -r '.port' <<< "${node}")
    domain=$(jq -r '.domain // "-"' <<< "${node}")
    upid=$(jq -r '.upstream_id // 0' <<< "${node}")
    enabled=$(jq -r '.enabled' <<< "${node}")
    if [[ ${upid} == '0' ]]; then
      upstream='-'
    else
      upstream="#${upid}"
    fi
    if [[ ${enabled} == 'true' ]]; then
      status=$(sbqd_t '启用' 'on')
    else
      status=$(sbqd_t '停用' 'off')
    fi
    printf '%s|%s|%s|%s|%s|%s|%s\n' \
      "${id}" "$(nodes_type_short "${type}")" "${name}" "${port}" \
      "${domain}" "${upstream}" "${status}"
  done < <(jq -c '.nodes[]' "${SBQD_STATE_FILE}")
}

nodes_list() {
  local header rows row
  local -a row_array=()
  if [[ $(state_node_count) == '0' ]]; then
    sbqd_info "$(sbqd_t '还没有节点，先添加一个吧' 'no nodes yet, add one first')"
    return 0
  fi
  header="$(sbqd_t 'ID|类型|名称|端口|域名|上游|状态' 'ID|Type|Name|Port|Domain|Upstream|State')"
  rows=$(nodes_list_rows)
  while IFS= read -r row; do
    [[ -n ${row} ]] || continue
    row_array+=("${row}")
  done <<< "${rows}"
  ui_table "${header}" "${row_array[@]}"
}

nodes_require_node() {
  local id=$1
  if ! [[ ${id} =~ ^[0-9]+$ ]] || ! state_node_exists "${id}"; then
    sbqd_err "$(sbqd_t '节点不存在：%s' 'node does not exist: %s' "${id}")"
    return 1
  fi
}

nodes_detail() {
  local id=$1 node type label domain upstream enabled created uri
  nodes_require_node "${id}" || return 1
  node=$(state_node_json "${id}")
  type=$(jq -r '.type' <<< "${node}")
  label=$(nodes_type_label "${type}")
  domain=$(jq -r '.domain // empty' <<< "${node}")
  enabled=$(jq -r '.enabled' <<< "${node}")
  created=$(jq -r '.created_at // "-"' <<< "${node}")

  ui_box_top "$(sbqd_t '节点详情' 'Node details')"
  ui_box_line "$(sbqd_t '编号' 'ID')        #${id}"
  ui_box_line "$(sbqd_t '类型' 'Type')      ${label}"
  ui_box_line "$(sbqd_t '名称' 'Name')      $(jq -r '.name' <<< "${node}")"
  ui_box_line "$(sbqd_t '端口' 'Port')      $(jq -r '.port' <<< "${node}")/$(nodes_type_transport "${type}")"
  ui_box_line "$(sbqd_t '域名' 'Domain')    ${domain:--}"
  ui_box_line "$(sbqd_t '状态' 'State')     $(if [[ ${enabled} == true ]]; then sbqd_t '启用' 'on'; else sbqd_t '停用' 'off'; fi)"
  ui_box_line "$(sbqd_t '创建时间' 'Created') ${created}"
  ui_box_bottom

  upstream=$(jq -r '.upstream_id // 0' <<< "${node}")
  if [[ ${upstream} != '0' ]]; then
    ui_kv "$(sbqd_t '中转上游' 'Upstream')" "#${upstream} $(state_upstream_field "${upstream}" 'name')"
  fi

  uri=$(share_node_uri "${node}") || return 1
  printf '\n'
  ui_kv "$(sbqd_t '分享链接' 'Share link')" "${uri}" "${SBQD_C_CYAN}"
}

nodes_qr() {
  local id=$1 node
  nodes_require_node "${id}" || return 1
  node=$(state_node_json "${id}")
  share_node_qr "${node}"
}

nodes_toggle() {
  local id=$1
  nodes_require_node "${id}" || return 1
  cp -f -- "${SBQD_STATE_FILE}" "${SBQD_TMP}/state-before-toggle.json"
  state_update '.nodes = [.nodes[] | if .id == $id then .enabled = (.enabled | not) else . end]' \
    --argjson id "${id}"
  if ! config_apply; then
    cp -f -- "${SBQD_TMP}/state-before-toggle.json" "${SBQD_STATE_FILE}"
    return 1
  fi
  if [[ $(state_node_field "${id}" 'enabled') == 'true' ]]; then
    sbqd_ok "$(sbqd_t '节点 #%s 已启用' 'node #%s enabled' "${id}")"
  else
    sbqd_ok "$(sbqd_t '节点 #%s 已停用' 'node #%s disabled' "${id}")"
  fi
}

nodes_delete() {
  local id=$1 assume_yes=${2:-0}
  nodes_require_node "${id}" || return 1

  if [[ ${assume_yes} != '1' ]] &&
    ! sbqd_confirm "$(sbqd_t '确认删除节点 #%s？' 'delete node #%s?' "${id}")" \
      'Delete this node?' 'n'; then
    return 1
  fi

  cp -f -- "${SBQD_STATE_FILE}" "${SBQD_TMP}/state-before-delete.json"
  state_update '.nodes = [.nodes[] | select(.id != $id)]' --argjson id "${id}"
  if ! config_apply; then
    cp -f -- "${SBQD_TMP}/state-before-delete.json" "${SBQD_STATE_FILE}"
    return 1
  fi
  sbqd_ok "$(sbqd_t '节点 #%s 已删除' 'node #%s deleted' "${id}")"
}

nodes_set_upstream() {
  local id=$1 upstream_id=$2
  nodes_require_node "${id}" || return 1
  if [[ ${upstream_id} != '0' ]]; then
    if ! [[ ${upstream_id} =~ ^[0-9]+$ ]] || [[ -z $(state_upstream_json "${upstream_id}") ]]; then
      sbqd_err "$(sbqd_t '上游不存在：%s' 'upstream does not exist: %s' "${upstream_id}")"
      return 1
    fi
  fi
  state_update '.nodes = [.nodes[] | if .id == $id then .upstream_id = $u else . end]' \
    --argjson id "${id}" --argjson u "${upstream_id}"
  config_apply
}

nodes_set_name() {
  local id=$1 name=$2
  nodes_require_node "${id}" || return 1
  [[ -n ${name} ]] || {
    sbqd_err "$(sbqd_t '名称不能为空' 'name cannot be empty')"
    return 1
  }
  state_update '.nodes = [.nodes[] | if .id == $id then .name = $n else . end]' \
    --argjson id "${id}" --arg n "${name}"
  config_apply
}

nodes_rotate() {
  local id=$1 node type params
  nodes_require_node "${id}" || return 1
  node=$(state_node_json "${id}")
  type=$(jq -r '.type' <<< "${node}")
  params=$(nodes_generate_params "${type}") || return 1

  cp -f -- "${SBQD_STATE_FILE}" "${SBQD_TMP}/state-before-rotate.json"
  state_update '.nodes = [.nodes[] | if .id == $id then .params = $p else . end]' \
    --argjson id "${id}" --argjson p "${params}"
  if ! config_apply; then
    cp -f -- "${SBQD_TMP}/state-before-rotate.json" "${SBQD_STATE_FILE}"
    return 1
  fi
  sbqd_ok "$(sbqd_t '节点 #%s 密钥已重置' 'node #%s secrets rotated' "${id}")"
  share_node_uri "$(state_node_json "${id}")"
  printf '\n'
}

# --- 交互式添加 -------------------------------------------------------------
nodes_choose_type() {
  ui_section "$(sbqd_t '选择协议' 'Choose protocol')"
  ui_item 1 'VLESS + TCP + Reality + Vision' 'TCP · 无需域名'
  ui_item 2 'Hysteria2' 'UDP · 需要域名'
  ui_item 3 'AnyTLS' 'TCP · 需要域名'
  ui_item 4 'TUIC v5' 'UDP · 需要域名'
  ui_item 5 'VMess + TLS + WebSocket' 'TCP · 需要域名'
  ui_item 0 "$(sbqd_t '返回' 'Back')" ''
  ui_ask
  case ${REPLY} in
    1) printf 'vless-reality' ;;
    2) printf 'hysteria2' ;;
    3) printf 'anytls' ;;
    4) printf 'tuic' ;;
    5) printf 'vmess-ws' ;;
    *) return 1 ;;
  esac
}

nodes_choose_domain() {
  local domains count i=1 domain days
  domains=$(state_domain_names)
  if [[ -z ${domains} ]]; then
    sbqd_err "$(sbqd_t '还没有可用域名，请先到「域名与证书」添加' \
      'no domain available, add one in Domain & Certificate first')"
    return 1
  fi
  ui_section "$(sbqd_t '选择域名' 'Choose domain')"
  while IFS= read -r domain; do
    [[ -n ${domain} ]] || continue
    days=$(cert_days "${domain}")
    ui_item "${i}" "${domain}" "$(sbqd_t '剩余' 'expires in') ${days} $(sbqd_t '天' 'days')"
    i=$((i + 1))
  done <<< "${domains}"
  ui_ask
  if ! [[ ${REPLY} =~ ^[0-9]+$ ]]; then
    return 1
  fi
  count=$((i - 1))
  if ((REPLY < 1 || REPLY > count)); then
    return 1
  fi
  sed -n "${REPLY}p" <<< "${domains}"
}

nodes_choose_upstream() {
  local upstreams count i=1 id name type
  upstreams=$(jq -r '.upstreams[] | "\(.id)|\(.name)|\(.type)"' "${SBQD_STATE_FILE}")
  ui_section "$(sbqd_t '中转上游' 'Upstream relay')"
  ui_item 0 "$(sbqd_t '不使用中转（直连）' 'No relay (direct)')" ''
  if [[ -n ${upstreams} ]]; then
    while IFS='|' read -r id name type; do
      ui_item "${i}" "#${id} ${name}" "${type}"
      i=$((i + 1))
    done <<< "${upstreams}"
  fi
  ui_ask
  if [[ ${REPLY} == '0' ]]; then
    printf '0'
    return 0
  fi
  if ! [[ ${REPLY} =~ ^[0-9]+$ ]]; then
    return 1
  fi
  count=$((i - 1))
  if ((REPLY < 1 || REPLY > count)); then
    return 1
  fi
  sed -n "${REPLY}p" <<< "${upstreams}" | cut -d'|' -f1
}

nodes_add_interactive() {
  local type name port domain upstream_id default_name

  type=$(nodes_choose_type) || return 0

  domain=''
  if nodes_type_needs_domain "${type}"; then
    domain=$(nodes_choose_domain) || return 0
  fi

  default_name="$(nodes_type_label "${type}")-$(state_node_count | awk '{print $1 + 1}')"
  sbqd_prompt "$(sbqd_t '节点名称' 'Node name')" 'Node name' "${default_name}"
  name=${REPLY}

  local default_port
  default_port=$(nodes_pick_port "$(nodes_type_transport "${type}")")
  while :; do
    sbqd_prompt "$(sbqd_t '端口' 'Port')" 'Port' "${default_port}"
    port=${REPLY}
    if ! sbqd_is_port "${port}"; then
      sbqd_err "$(sbqd_t '端口必须在 1-65535 之间' 'port must be between 1 and 65535')"
      continue
    fi
    if ! nodes_port_free "${port}" "$(nodes_type_transport "${type}")"; then
      sbqd_err "$(sbqd_t '端口 %s 已被占用，请换一个' 'port %s is taken, choose another' "${port}")"
      continue
    fi
    break
  done

  upstream_id=$(nodes_choose_upstream) || return 0

  SBQD_NODE_HANDSHAKE='www.microsoft.com'
  if [[ ${type} == 'vless-reality' ]]; then
    ui_section "$(sbqd_t 'Reality 伪装目标' 'Reality handshake target')"
    ui_item 1 'www.microsoft.com' ''
    ui_item 2 'www.apple.com' ''
    ui_item 3 'www.cloudflare.com' ''
    ui_item 4 'dl.google.com' ''
    ui_item 5 'www.amazon.com' ''
    ui_item 6 "$(sbqd_t '自定义' 'Custom')" ''
    ui_ask
    case ${REPLY} in
      1) SBQD_NODE_HANDSHAKE='www.microsoft.com' ;;
      2) SBQD_NODE_HANDSHAKE='www.apple.com' ;;
      3) SBQD_NODE_HANDSHAKE='www.cloudflare.com' ;;
      4) SBQD_NODE_HANDSHAKE='dl.google.com' ;;
      5) SBQD_NODE_HANDSHAKE='www.amazon.com' ;;
      6)
        sbqd_prompt "$(sbqd_t '输入伪装域名' 'Handshake domain')" 'Handshake domain' 'www.microsoft.com'
        SBQD_NODE_HANDSHAKE=${REPLY}
        ;;
      *) return 0 ;;
    esac
  fi

  nodes_create "${type}" "${name}" "${port}" "${domain}" "${upstream_id}"
}
