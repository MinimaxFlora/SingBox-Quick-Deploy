# shellcheck shell=bash
# shellcheck disable=SC2154,SC2016
# =============================================================================
#  config.sh · sing-box 配置生成与应用
#  目标版本：sing-box >= 1.12（当前发布线 1.14.x）
#  说明：所有字段使用 1.12+ 新语法，绝不输出 1.11 已废弃字段
# =============================================================================

config_listen() {
  if state_bool '.settings.ipv6'; then
    printf '::'
  else
    printf '0.0.0.0'
  fi
}

config_cert_file() {
  local domain=$1 name=$2
  printf '%s/%s/%s' "${SINGBOX_CERT_DIR}" "${domain}" "${name}"
}

# 单个节点的 inbound JSON
config_node_inbound() {
  local node=$1
  local type id tag domain listen cert key

  type=$(jq -r '.type' <<< "${node}")
  id=$(jq -r '.id' <<< "${node}")
  tag="${type}-${id}"
  domain=$(jq -r '.domain // empty' <<< "${node}")
  listen=$(config_listen)

  case ${type} in
    vless-reality)
      jq -nc --argjson n "${node}" --arg tag "${tag}" --arg listen "${listen}" '
        {
          type: "vless",
          tag: $tag,
          listen: $listen,
          listen_port: ($n.port | tonumber),
          users: [{
            name: "user",
            uuid: $n.params.uuid,
            flow: ($n.params.flow // "xtls-rprx-vision")
          }],
          tls: {
            enabled: true,
            server_name: $n.params.server_name,
            reality: {
              enabled: true,
              handshake: {
                server: $n.params.handshake_server,
                server_port: ($n.params.handshake_port // 443)
              },
              private_key: $n.params.private_key,
              short_id: [$n.params.short_id],
              max_time_difference: "1m"
            }
          }
        }'
      ;;
    hysteria2 | anytls | tuic | vmess-ws)
      if [[ -z ${domain} ]]; then
        sbqd_err "$(sbqd_t '节点 %s 缺少域名，无法生成 TLS 配置' \
          'node %s has no domain, cannot build TLS config' "${tag}")"
        return 1
      fi
      cert=$(config_cert_file "${domain}" 'fullchain.pem')
      key=$(config_cert_file "${domain}" 'privkey.pem')

      case ${type} in
        hysteria2)
          jq -nc --argjson n "${node}" --arg tag "${tag}" --arg listen "${listen}" \
            --arg domain "${domain}" --arg cert "${cert}" --arg key "${key}" '
            {
              type: "hysteria2",
              tag: $tag,
              listen: $listen,
              listen_port: ($n.port | tonumber),
              users: [{name: "user", password: $n.params.password}],
              masquerade: ("https://" + $domain + "/"),
              tls: {
                enabled: true,
                server_name: $domain,
                alpn: ["h3"],
                certificate_path: $cert,
                key_path: $key
              }
            }
            + (if ($n.params.obfs // false) then
                 {obfs: {type: "salamander", password: ($n.params.obfs_password // "")}}
               else {} end)'
          ;;
        anytls)
          jq -nc --argjson n "${node}" --arg tag "${tag}" --arg listen "${listen}" \
            --arg domain "${domain}" --arg cert "${cert}" --arg key "${key}" '
            {
              type: "anytls",
              tag: $tag,
              listen: $listen,
              listen_port: ($n.port | tonumber),
              users: [{name: "user", password: $n.params.password}],
              tls: {
                enabled: true,
                server_name: $domain,
                certificate_path: $cert,
                key_path: $key
              }
            }'
          ;;
        tuic)
          jq -nc --argjson n "${node}" --arg tag "${tag}" --arg listen "${listen}" \
            --arg domain "${domain}" --arg cert "${cert}" --arg key "${key}" '
            {
              type: "tuic",
              tag: $tag,
              listen: $listen,
              listen_port: ($n.port | tonumber),
              users: [{
                name: "user",
                uuid: $n.params.uuid,
                password: $n.params.password
              }],
              congestion_control: ($n.params.congestion_control // "bbr"),
              auth_timeout: "3s",
              zero_rtt_handshake: ($n.params.zero_rtt // false),
              tls: {
                enabled: true,
                server_name: $domain,
                alpn: ["h3"],
                certificate_path: $cert,
                key_path: $key
              }
            }'
          ;;
        vmess-ws)
          jq -nc --argjson n "${node}" --arg tag "${tag}" --arg listen "${listen}" \
            --arg domain "${domain}" --arg cert "${cert}" --arg key "${key}" '
            {
              type: "vmess",
              tag: $tag,
              listen: $listen,
              listen_port: ($n.port | tonumber),
              users: [{name: "user", uuid: $n.params.uuid, alterId: 0}],
              transport: {
                type: "ws",
                path: $n.params.ws_path,
                headers: {Host: $domain},
                max_early_data: 2048,
                early_data_header_name: "Sec-WebSocket-Protocol"
              },
              tls: {
                enabled: true,
                server_name: $domain,
                alpn: ["http/1.1"],
                certificate_path: $cert,
                key_path: $key
              }
            }'
          ;;
      esac
      ;;
    *)
      sbqd_err "$(sbqd_t '未知节点类型：%s' 'unknown node type: %s' "${type}")"
      return 1
      ;;
  esac
}

# 上游中转的 outbound JSON
config_upstream_outbound() {
  local upstream=$1
  local type
  type=$(jq -r '.type' <<< "${upstream}")

  case ${type} in
    socks5)
      jq -nc --argjson u "${upstream}" '
        {
          type: "socks",
          tag: ("upstream-" + ($u.id | tostring)),
          server: $u.server,
          server_port: ($u.port | tonumber),
          version: "5"
        }
        + (if (($u.username // "") != "") then
             {username: $u.username, password: ($u.password // "")}
           else {} end)'
      ;;
    shadowsocks)
      jq -nc --argjson u "${upstream}" '
        {
          type: "shadowsocks",
          tag: ("upstream-" + ($u.id | tostring)),
          server: $u.server,
          server_port: ($u.port | tonumber),
          method: $u.method,
          password: $u.password
        }'
      ;;
    *)
      sbqd_err "$(sbqd_t '未知中转类型：%s' 'unknown upstream type: %s' "${type}")"
      return 1
      ;;
  esac
}

# 生成完整服务端配置到 stdout
config_generate() {
  state_require

  local inbounds='[]' outbounds='[{"type":"direct","tag":"direct"}]' rules='[]'
  local node frag tag upid upstream ufrag
  local api_enabled api_port api_secret api_json experimental

  while IFS= read -r node; do
    if [[ $(jq -r '.enabled' <<< "${node}") != 'true' ]]; then
      continue
    fi
    if ! frag=$(config_node_inbound "${node}"); then
      return 1
    fi
    inbounds=$(jq -c --argjson f "${frag}" '. + [$f]' <<< "${inbounds}")

    upid=$(jq -r '.upstream_id // 0' <<< "${node}")
    if [[ ${upid} =~ ^[0-9]+$ ]] && ((upid > 0)); then
      if [[ -n $(state_upstream_json "${upid}") ]]; then
        tag=$(jq -r '.type + "-" + (.id | tostring)' <<< "${node}")
        rules=$(jq -c --arg t "${tag}" --arg o "upstream-${upid}" \
          '. + [{inbound: [$t], action: "route", outbound: $o}]' <<< "${rules}")
      else
        sbqd_warn "$(sbqd_t '节点 %s 引用了不存在的上游 %s，已忽略' \
          'node %s references missing upstream %s, ignored' "${tag:-?}" "${upid}")"
      fi
    fi
  done < <(jq -c '.nodes[]' "${SBQD_STATE_FILE}")

  while IFS= read -r upstream; do
    if ! ufrag=$(config_upstream_outbound "${upstream}"); then
      return 1
    fi
    outbounds=$(jq -c --argjson f "${ufrag}" '. + [$f]' <<< "${outbounds}")
  done < <(jq -c '.upstreams[]' "${SBQD_STATE_FILE}")

  api_enabled=$(state_value '.settings.clash_api.enabled' 'false')
  api_port=$(state_value '.settings.clash_api.port' '0')
  api_secret=$(state_value '.settings.clash_api.secret' '')
  api_json='{}'
  if [[ ${api_enabled} == 'true' && ${api_port} =~ ^[0-9]+$ ]] && ((api_port > 0)); then
    api_json=$(jq -nc --arg ctl "127.0.0.1:${api_port}" --arg secret "${api_secret}" \
      '{clash_api: {external_controller: $ctl, secret: $secret, default_mode: "rule"}}')
  fi
  experimental=$(jq -nc --argjson api "${api_json}" '{cache_file: {enabled: true}} + $api')

  jq -n \
    --argjson inbounds "${inbounds}" \
    --argjson outbounds "${outbounds}" \
    --argjson rules "${rules}" \
    --argjson experimental "${experimental}" \
    '{
      log: {level: "info", timestamp: true},
      inbounds: $inbounds,
      outbounds: $outbounds,
      route: {rules: $rules, final: "direct"},
      experimental: $experimental
    }'
}

# 校验配置；失败时把 sing-box 的错误输出到 stderr
config_check() {
  local file=$1 out
  if [[ ! -x ${SINGBOX_BIN} ]]; then
    sbqd_err "$(sbqd_t 'sing-box 未安装' 'sing-box is not installed')"
    return 1
  fi
  if ! out=$("${SINGBOX_BIN}" check -c "${file}" 2>&1); then
    sbqd_err "$(sbqd_t '配置校验失败：' 'config validation failed:')"
    printf '%s\n' "${out}" | head -n 25 >&2
    return 1
  fi
  return 0
}

# 检查所有启用节点的域名/证书是否就绪
config_check_domains() {
  local node type tag domain fullchain key missing=0
  while IFS= read -r node; do
    [[ $(jq -r '.enabled' <<< "${node}") == 'true' ]] || continue
    type=$(jq -r '.type' <<< "${node}")
    if [[ ${type} == 'vless-reality' ]]; then
      continue
    fi
    tag="${type}-$(jq -r '.id' <<< "${node}")"
    domain=$(jq -r '.domain // empty' <<< "${node}")
    if [[ -z ${domain} ]]; then
      sbqd_err "$(sbqd_t '节点 %s 没有绑定域名' 'node %s has no domain' "${tag}")"
      missing=1
      continue
    fi
    fullchain=$(config_cert_file "${domain}" 'fullchain.pem')
    key=$(config_cert_file "${domain}" 'privkey.pem')
    if [[ ! -r ${fullchain} || ! -r ${key} ]]; then
      sbqd_err "$(sbqd_t '节点 %s 的证书文件缺失：%s' \
        'certificate files missing for node %s: %s' "${tag}" "${domain}")"
      missing=1
    fi
  done < <(jq -c '.nodes[]' "${SBQD_STATE_FILE}")
  return "${missing}"
}

config_rollback() {
  local backup=$1
  if [[ -f ${backup} ]]; then
    install -m 640 -o root -g "${SINGBOX_USER}" "${backup}" "${SINGBOX_CONFIG_FILE}"
    sbqd_warn "$(sbqd_t '已恢复上一份可用配置' 'restored the previous working config')"
    service_restart || true
  fi
}

# 生成 → 校验 → 原子替换 → 热重载；失败自动回滚
config_apply() {
  local generated="${SBQD_TMP}/config.json" backup="${SINGBOX_CONFIG_FILE}.bak"

  state_require
  config_check_domains || return 1
  config_generate > "${generated}" || return 1
  if ! config_check "${generated}"; then
    return 1
  fi

  if [[ -f ${SINGBOX_CONFIG_FILE} ]] && cmp -s "${generated}" "${SINGBOX_CONFIG_FILE}"; then
    if ! service_active; then
      service_enable_start || {
        sbqd_err "$(sbqd_t '配置未变化，但服务启动失败' 'config unchanged, but service failed to start')"
        return 1
      }
    fi
    # 配置未变时仍需刷新订阅（例如只改了节点名称）
    if declare -F share_publish > /dev/null 2>&1; then
      share_publish || sbqd_warn "$(sbqd_t '订阅文件刷新失败' 'failed to refresh subscription files')"
    fi
    sbqd_debug 'config unchanged'
    return 0
  fi

  mkdir -p -- "${SINGBOX_CONFIG_DIR}"
  if [[ -f ${SINGBOX_CONFIG_FILE} ]]; then
    cp -f -- "${SINGBOX_CONFIG_FILE}" "${backup}"
    chmod 600 "${backup}"
  fi

  install -m 640 -o root -g "${SINGBOX_USER}" "${generated}" "${SINGBOX_CONFIG_FILE}"

  if ! service_reload; then
    sbqd_err "$(sbqd_t '服务重载失败' 'service reload failed')"
    config_rollback "${backup}"
    return 1
  fi
  if ! service_wait_active; then
    sbqd_err "$(sbqd_t '服务未能保持运行，正在回滚' 'service did not stay up, rolling back')"
    config_rollback "${backup}"
    return 1
  fi

  sbqd_ok "$(sbqd_t '配置已应用，sing-box 运行中' 'config applied, sing-box is running')"

  if declare -F share_publish > /dev/null 2>&1; then
    share_publish || sbqd_warn "$(sbqd_t '订阅文件刷新失败' 'failed to refresh subscription files')"
  fi
  if declare -F firewall_sync > /dev/null 2>&1; then
    firewall_sync || sbqd_warn "$(sbqd_t '防火墙规则同步失败' 'failed to sync firewall rules')"
  fi
  return 0
}

config_show() {
  if [[ -r ${SINGBOX_CONFIG_FILE} ]]; then
    jq . "${SINGBOX_CONFIG_FILE}"
  else
    sbqd_err "$(sbqd_t '配置文件不存在' 'config file does not exist')"
    return 1
  fi
}

# 需要放行的端口列表，格式 "port/proto"
config_ports() {
  local node type port
  while IFS= read -r node; do
    [[ $(jq -r '.enabled' <<< "${node}") == 'true' ]] || continue
    type=$(jq -r '.type' <<< "${node}")
    port=$(jq -r '.port' <<< "${node}")
    case ${type} in
      hysteria2 | tuic) printf '%s/udp\n' "${port}" ;;
      *) printf '%s/tcp\n' "${port}" ;;
    esac
  done < <(jq -c '.nodes[]' "${SBQD_STATE_FILE}")

  local sub_enabled sub_port
  sub_enabled=$(state_value '.settings.subscription.enabled' 'false')
  sub_port=$(state_value '.settings.subscription.port' '0')
  if [[ ${sub_enabled} == 'true' && ${sub_port} =~ ^[0-9]+$ ]] && ((sub_port > 0)); then
    printf '%s/tcp\n' "${sub_port}"
  fi
}
