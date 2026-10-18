# shellcheck shell=bash
# shellcheck disable=SC2154,SC2016,SC2034
# =============================================================================
#  state.sh · 状态存储层
#  职责：state.json 的初始化、校验、原子更新与领域查询
#  设计：单一 JSON 文件（jq），每次写入原子替换并保留 .prev 快照
# =============================================================================

SBQD_STATE_SCHEMA=1

state_require() {
  if [[ ! -f ${SBQD_STATE_FILE} ]]; then
    sbqd_die "$(sbqd_t '状态文件不存在：%s\n请先运行 sbqd install 完成安装' \
      'state file not found: %s\nrun sbqd install first' "${SBQD_STATE_FILE}")"
  fi
}

state_exists() {
  [[ -f ${SBQD_STATE_FILE} ]]
}

state_init() {
  if [[ -f ${SBQD_STATE_FILE} ]]; then
    return 0
  fi

  mkdir -p -- "${SBQD_ETC}"
  chmod 700 "${SBQD_ETC}"

  local now api_secret sub_token
  now=$(sbqd_iso_now)
  api_secret=$(sbqd_rand_token 18)
  sub_token=$(sbqd_rand_token 24)

  jq -n \
    --arg now "${now}" \
    --arg api_secret "${api_secret}" \
    --arg sub_token "${sub_token}" \
    --argjson pmin "${SBQD_PORT_MIN}" \
    --argjson pmax "${SBQD_PORT_MAX}" \
    '{
      schema: 1,
      created_at: $now,
      updated_at: $now,
      next_node_id: 1,
      next_upstream_id: 1,
      next_domain_id: 1,
      settings: {
        language: "zh",
        port_min: $pmin,
        port_max: $pmax,
        ipv6: true,
        public_ipv4: "",
        public_ipv6: "",
        clash_api: {enabled: true, listen: "127.0.0.1", port: 0, secret: $api_secret},
        subscription: {enabled: false, port: 0, token: $sub_token, tls: false, domain: "", panel_url: ""},
        singbox: {version: "", mirror: ""}
      },
      domains: [],
      upstreams: [],
      nodes: []
    }' | sbqd_atomic_write "${SBQD_STATE_FILE}"

  chmod 600 "${SBQD_STATE_FILE}"
}

state_validate() {
  local ok=0
  jq -e '
    (.schema == 1) and
    (.settings | type == "object") and
    (.nodes | type == "array") and
    (.upstreams | type == "array") and
    (.domains | type == "array") and
    (([.nodes[].port] | length) == ([.nodes[].port] | unique | length)) and
    (([.nodes[].id] | length) == ([.nodes[].id] | unique | length)) and
    (([.nodes[].type] - ["vless-reality", "hysteria2", "anytls", "tuic", "vmess-ws"]) | length == 0)
  ' "${SBQD_STATE_FILE}" > /dev/null 2>&1 || ok=1

  if ((ok)); then
    sbqd_err "$(sbqd_t '状态文件校验失败：%s' 'state validation failed: %s' "${SBQD_STATE_FILE}")"
    return 1
  fi
  return 0
}

state_json() {
  jq -c '.' "${SBQD_STATE_FILE}"
}

# 更新状态：$1 为 jq 过滤器，其余参数原样传给 jq（如 --arg name value）
state_update() {
  local prog=$1
  shift

  state_require
  local out
  if ! out=$(jq "$@" "${prog}" "${SBQD_STATE_FILE}"); then
    sbqd_die "$(sbqd_t '状态更新失败（jq 过滤器执行错误）' 'state update failed (jq filter error)')"
  fi
  if [[ -z ${out} ]]; then
    sbqd_die "$(sbqd_t '状态更新失败（输出为空）' 'state update failed (empty output)')"
  fi

  if [[ -f ${SBQD_STATE_FILE} ]]; then
    cp -f -- "${SBQD_STATE_FILE}" "${SBQD_STATE_FILE}.prev" 2> /dev/null || true
  fi

  printf '%s' "${out}" |
    jq --arg ts "$(sbqd_iso_now)" '.updated_at = $ts' |
    sbqd_atomic_write "${SBQD_STATE_FILE}"
  chmod 600 "${SBQD_STATE_FILE}"
}

# 读取标量值（空值返回默认值）
state_value() {
  local filter=$1 default=${2:-} value
  state_require
  value=$(jq -r "${filter} // empty" "${SBQD_STATE_FILE}" 2> /dev/null) || value=''
  if [[ -z ${value} ]]; then
    printf '%s' "${default}"
  else
    printf '%s' "${value}"
  fi
}

state_bool() {
  local filter=$1
  local value
  value=$(state_value "${filter}" 'false')
  [[ ${value} == 'true' ]]
}

# 分配自增 ID：node / upstream / domain
state_alloc_id() {
  local field=$1 current
  current=$(state_value ".${field}" '1')
  [[ ${current} =~ ^[0-9]+$ ]] || current=1
  state_update ".[\$f] = (\$cur + 1)" --arg f "${field}" --argjson cur "${current}"
  printf '%s' "${current}"
}

# --- 节点 -------------------------------------------------------------------
state_add_node() {
  local node=$1
  state_update '.nodes += [$n]' --argjson n "${node}"
}

state_node_exists() {
  local id=$1
  [[ ${id} =~ ^[0-9]+$ ]] || return 1
  jq -e --argjson id "${id}" 'any(.nodes[]; .id == $id)' "${SBQD_STATE_FILE}" > /dev/null 2>&1
}

state_node_json() {
  local id=$1
  jq -c --argjson id "${id}" '.nodes[] | select(.id == $id)' "${SBQD_STATE_FILE}"
}

state_node_field() {
  local id=$1 field=$2
  jq -r --argjson id "${id}" --arg f "${field}" \
    '.nodes[] | select(.id == $id) | .[$f] // empty' "${SBQD_STATE_FILE}"
}

state_node_count() {
  jq -r '.nodes | length' "${SBQD_STATE_FILE}"
}

state_node_ids() {
  jq -r '.nodes[].id' "${SBQD_STATE_FILE}"
}

state_node_ports() {
  jq -r '.nodes[].port' "${SBQD_STATE_FILE}"
}

state_node_tag() {
  local id=$1 type
  type=$(state_node_field "${id}" 'type')
  printf '%s-%s' "${type}" "${id}"
}

# 节点是否有可用的域名与证书
state_node_domain() {
  local id=$1
  state_node_field "${id}" 'domain'
}

# --- 上游中转 ---------------------------------------------------------------
state_add_upstream() {
  local upstream=$1
  state_update '.upstreams += [$u]' --argjson u "${upstream}"
}

state_upstream_json() {
  local id=$1
  jq -c --argjson id "${id}" '.upstreams[] | select(.id == $id)' "${SBQD_STATE_FILE}"
}

state_upstream_field() {
  local id=$1 field=$2
  jq -r --argjson id "${id}" --arg f "${field}" \
    '.upstreams[] | select(.id == $id) | .[$f] // empty' "${SBQD_STATE_FILE}"
}

state_upstream_count() {
  jq -r '.upstreams | length' "${SBQD_STATE_FILE}"
}

state_upstream_ids() {
  jq -r '.upstreams[].id' "${SBQD_STATE_FILE}"
}

# --- 域名与证书 -------------------------------------------------------------
state_add_domain() {
  local domain=$1
  state_update '.domains += [$d]' --argjson d "${domain}"
}

state_domain_json() {
  local domain=$1
  jq -c --arg d "${domain}" '.domains[] | select(.domain == $d)' "${SBQD_STATE_FILE}"
}

state_domain_exists() {
  local domain=$1
  jq -e --arg d "${domain}" 'any(.domains[]; .domain == $d)' "${SBQD_STATE_FILE}" > /dev/null 2>&1
}

state_domain_field() {
  local domain=$1 field=$2
  jq -r --arg d "${domain}" --arg f "${field}" \
    '.domains[] | select(.domain == $d) | .[$f] // empty' "${SBQD_STATE_FILE}"
}

state_domain_count() {
  jq -r '.domains | length' "${SBQD_STATE_FILE}"
}

state_domain_names() {
  jq -r '.domains[].domain' "${SBQD_STATE_FILE}"
}

# 返回最早到期证书的剩余天数（无证书时输出 9999）
state_cert_days_left() {
  local min=9999 days issued
  while IFS= read -r issued; do
    [[ -n ${issued} ]] || continue
    days=$(sbqd_days_left "${issued}")
    if ((days < min)); then
      min=${days}
    fi
  done < <(jq -r '.domains[].expires_at // empty' "${SBQD_STATE_FILE}" 2> /dev/null)
  printf '%s' "${min}"
}

# --- 语言 -------------------------------------------------------------------
state_language() {
  state_value '.settings.language' 'zh'
}

state_set_language() {
  local lang=$1
  [[ ${lang} == 'en' || ${lang} == 'zh' ]] || return 1
  state_update '.settings.language = $l' --arg l "${lang}"
}
