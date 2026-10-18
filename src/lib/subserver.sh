# shellcheck shell=bash
# shellcheck disable=SC2154,SC2016
# =============================================================================
#  subserver.sh · 带 Token 的订阅服务
#  交付：静态订阅文件 + UC 分流 + 只读状态面板（Python 标准库）
# =============================================================================

SBQD_SUB_UNIT='sbqd-sub.service'
SBQD_SUB_ENV_FILE="${SBQD_ETC}/sub.env"

subserver_python() {
  if sbqd_has_cmd python3; then
    command -v python3
    return 0
  fi
  sbqd_die "$(sbqd_t '缺少 python3，无法运行订阅服务' 'python3 is required for the subscription server')"
}

subserver_ensure_user() {
  if ! getent group "${SBQD_SUB_USER}" > /dev/null 2>&1; then
    groupadd --system "${SBQD_SUB_USER}" 2> /dev/null ||
      sbqd_die "$(sbqd_t '创建用户组 %s 失败' 'failed to create group %s' "${SBQD_SUB_USER}")"
  fi
  if ! id -u "${SBQD_SUB_USER}" > /dev/null 2>&1; then
    local nologin
    nologin=$(command -v nologin || printf '/usr/sbin/nologin')
    useradd --system --gid "${SBQD_SUB_USER}" --home-dir "${SBQD_ETC}" \
      --no-create-home --shell "${nologin}" "${SBQD_SUB_USER}" 2> /dev/null ||
      sbqd_die "$(sbqd_t '创建用户 %s 失败' 'failed to create user %s' "${SBQD_SUB_USER}")"
  fi
}

subserver_install_python() {
  mkdir -p -- "${SBQD_LIB_DIR}"
  if [[ -n ${SBQD_EMBEDDED_SUBSERVER:-} ]]; then
    printf '%s' "${SBQD_EMBEDDED_SUBSERVER}" | base64 -d > "${SBQD_LIB_DIR}/subserver.py"
  elif [[ -r ${SBQD_ASSETS_DIR:-}/subserver.py ]]; then
    cp -f -- "${SBQD_ASSETS_DIR}/subserver.py" "${SBQD_LIB_DIR}/subserver.py"
  else
    sbqd_die "$(sbqd_t '找不到 subserver.py' 'subserver.py not found')"
  fi
  chmod 644 "${SBQD_LIB_DIR}/subserver.py"
}

subserver_write_env() {
  local port token tls domain panel cert key api_port api_secret
  port=$(state_value '.settings.subscription.port' '0')
  token=$(state_value '.settings.subscription.token' '')
  tls=$(state_value '.settings.subscription.tls' 'false')
  domain=$(state_value '.settings.subscription.domain' '')
  panel=$(state_value '.settings.subscription.panel_url' '')
  api_port=$(state_value '.settings.clash_api.port' '0')
  api_secret=$(state_value '.settings.clash_api.secret' '')

  cert=''
  key=''
  if [[ ${tls} == 'true' ]]; then
    cert="${SBQD_SUB_DIR}/tls/fullchain.pem"
    key="${SBQD_SUB_DIR}/tls/privkey.pem"
  fi

  cat > "${SBQD_SUB_ENV_FILE}" << EOF
SBQD_SUB_ROOT=${SBQD_SUB_DIR}
SBQD_SUB_HOST=0.0.0.0
SBQD_SUB_PORT=${port}
SBQD_SUB_TOKEN=${token}
SBQD_SUB_CERT=${cert}
SBQD_SUB_KEY=${key}
SBQD_CLASH_API=http://127.0.0.1:${api_port}
SBQD_CLASH_SECRET=${api_secret}
SBQD_PANEL_URL=${panel}
SBQD_SUB_LANG=${SBQD_LANG}
EOF
  chmod 600 "${SBQD_SUB_ENV_FILE}"
  if [[ ${tls} == 'true' && -n ${domain} ]]; then
    mkdir -p "${SBQD_SUB_DIR}/tls"
    install -m 640 -o root -g "${SBQD_SUB_USER}" "$(cert_fullchain "${domain}")" "${cert}"
    install -m 640 -o root -g "${SBQD_SUB_USER}" "$(cert_privkey "${domain}")" "${key}"
  fi
}

subserver_write_unit() {
  local py
  py=$(subserver_python)
  subserver_ensure_user

  cat > "${SBQD_TMP}/sbqd-sub.service" << EOF
# Managed by SingBox-Quick-Deploy — do not edit manually.
[Unit]
Description=SBQD subscription server
Documentation=${SBQD_HOME_URL}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SBQD_SUB_USER}
Group=${SBQD_SUB_USER}
EnvironmentFile=${SBQD_SUB_ENV_FILE}
ExecStart=${py} ${SBQD_LIB_DIR}/subserver.py
Restart=always
RestartSec=3s
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadOnlyPaths=${SBQD_SUB_DIR}

[Install]
WantedBy=multi-user.target
EOF
  install -m 644 "${SBQD_TMP}/sbqd-sub.service" "/etc/systemd/system/${SBQD_SUB_UNIT}"
  systemctl daemon-reload || sbqd_die "$(sbqd_t 'daemon-reload 失败' 'daemon-reload failed')"
}

subserver_active() {
  systemctl is-active --quiet sbqd-sub 2> /dev/null
}

subserver_wait_port() {
  local port=$1 i=0
  while ((i < 20)); do
    if sbqd_port_in_use "${port}" tcp; then
      return 0
    fi
    i=$((i + 1))
    sleep 0.2
  done
  return 1
}

subserver_enable() {
  local port=$1 domain=${2:-} panel=${3:-} tls='false' cert key

  if [[ -z ${port} ]]; then
    port=$(sbqd_rand_port)
  fi
  if ! sbqd_is_port "${port}"; then
    sbqd_err "$(sbqd_t '端口不合法：%s' 'invalid port: %s' "${port}")"
    return 1
  fi
  # 重新配置端口时先停掉旧实例，避免端口占用误判
  if systemctl is-active --quiet sbqd-sub 2> /dev/null; then
    systemctl stop sbqd-sub 2> /dev/null || true
  fi
  if sbqd_port_in_use "${port}" tcp; then
    sbqd_err "$(sbqd_t '端口 %s 已被占用' 'port %s is already in use' "${port}")"
    return 1
  fi

  if [[ -n ${domain} ]]; then
    if ! state_domain_exists "${domain}" || ! cert_files_ok "${domain}"; then
      sbqd_err "$(sbqd_t '域名 %s 的证书不可用，订阅将使用 HTTP' \
        'certificate for %s unavailable, subscription will use HTTP' "${domain}")"
      domain=''
    else
      tls='true'
    fi
  fi

  subserver_ensure_user
  subserver_install_python
  share_publish || true

  state_update '
    .settings.subscription.enabled = true |
    .settings.subscription.port = $port |
    .settings.subscription.tls = ($tls == "true") |
    .settings.subscription.domain = $domain |
    .settings.subscription.panel_url = $panel' \
    --argjson port "${port}" --arg tls "${tls}" \
    --arg domain "${domain}" --arg panel "${panel}"

  subserver_write_env
  subserver_write_unit

  if ! systemctl enable --now sbqd-sub > /dev/null 2>&1; then
    sbqd_err "$(sbqd_t '订阅服务启动失败' 'failed to start subscription server')"
    systemctl status sbqd-sub --no-pager -l 2>&1 | head -n 20 >&2 || true
    state_update '.settings.subscription.enabled = false'
    return 1
  fi
  if ! subserver_wait_port "${port}"; then
    sbqd_err "$(sbqd_t '订阅服务未在预期端口监听' 'subscription server is not listening')"
    state_update '.settings.subscription.enabled = false'
    return 1
  fi

  sbqd_ok "$(sbqd_t '订阅服务已开启' 'subscription server enabled')"
  subserver_print_url
}

subserver_disable() {
  systemctl disable --now sbqd-sub > /dev/null 2>&1 || true
  state_update '.settings.subscription.enabled = false'
  sbqd_ok "$(sbqd_t '订阅服务已关闭' 'subscription server disabled')"
}

subserver_restart() {
  if [[ $(state_value '.settings.subscription.enabled' 'false') != 'true' ]]; then
    return 0
  fi
  subserver_write_env
  systemctl restart sbqd-sub 2> /dev/null || return 1
  local port
  port=$(state_value '.settings.subscription.port' '0')
  subserver_wait_port "${port}"
}

subserver_print_url() {
  local url
  if ! url=$(share_sub_url); then
    sbqd_warn "$(sbqd_t '订阅地址不可用（未开启或缺少公网地址）' \
      'subscription URL unavailable (disabled or no public address)')"
    return 1
  fi

  ui_kv "$(sbqd_t '订阅地址' 'Subscription URL')" "${url}" "${SBQD_C_CYAN}"

  local domain port
  domain=$(state_value '.settings.subscription.domain' '')
  port=$(state_value '.settings.subscription.port' '0')
  if [[ -n ${domain} ]]; then
    ui_kv "$(sbqd_t '面板' 'Dashboard')" "https://${domain}:${port}/sub/$(state_value '.settings.subscription.token')/dashboard" "${SBQD_C_DIM}"
  fi
  return 0
}

subserver_status_text() {
  local enabled
  enabled=$(state_value '.settings.subscription.enabled' 'false')
  if [[ ${enabled} != 'true' ]]; then
    sbqd_t '未开启' 'disabled'
    return 0
  fi
  if subserver_active; then
    sbqd_t '运行中' 'running'
  else
    sbqd_t '异常' 'failed'
  fi
}

subserver_rotate_token() {
  local token
  token=$(sbqd_rand_token 24)
  state_update '.settings.subscription.token = $t' --arg t "${token}"
  if [[ $(state_value '.settings.subscription.enabled' 'false') == 'true' ]]; then
    subserver_restart || sbqd_warn "$(sbqd_t '重启订阅服务失败' 'failed to restart subscription server')"
  fi
  sbqd_ok "$(sbqd_t '订阅 Token 已重置，旧地址立即失效' 'subscription token rotated, old URLs are invalid')"
  subserver_print_url
}

subserver_setup_interactive() {
  local state port domain panel domains

  state=$(state_value '.settings.subscription.enabled' 'false')
  ui_section "$(sbqd_t '订阅服务' 'Subscription server')"
  if [[ ${state} == 'true' ]]; then
    printf '   %s\n' "$(subserver_status_text)"
    subserver_print_url || true
  fi

  ui_item 1 "$(sbqd_t '开启 / 修改端口' 'Enable / change port')" ''
  ui_item 2 "$(sbqd_t '关闭订阅服务' 'Disable')" ''
  ui_item 3 "$(sbqd_t '重置 Token' 'Rotate token')" ''
  ui_item 4 "$(sbqd_t '查看二维码' 'Show QR code')" ''
  ui_item 0 "$(sbqd_t '返回' 'Back')" ''
  ui_ask

  case ${REPLY} in
    1)
      port=$(state_value '.settings.subscription.port' '')
      if [[ -z ${port} || ${port} == '0' ]]; then
        port=$(sbqd_rand_port)
      fi
      sbqd_prompt "$(sbqd_t '监听端口' 'Listen port')" 'Listen port' "${port}"
      port=${REPLY}

      domain=''
      domains=$(state_domain_names)
      if [[ -n ${domains} ]]; then
        sbqd_prompt "$(sbqd_t '启用 HTTPS 的域名（留空则用 HTTP）' 'Domain for HTTPS (empty = HTTP)')" \
          'Domain for HTTPS (empty = HTTP)' ''
        domain=${REPLY}
        if [[ -n ${domain} ]] && ! state_domain_exists "${domain}"; then
          sbqd_err "$(sbqd_t '域名未托管：%s' 'domain not managed: %s' "${domain}")"
          return 1
        fi
      fi

      sbqd_prompt "$(sbqd_t '外部面板地址（可留空）' 'External panel URL (optional)')" \
        'External panel URL (optional)' "$(state_value '.settings.subscription.panel_url' '')"
      panel=${REPLY}

      subserver_enable "${port}" "${domain}" "${panel}"
      ;;
    2) subserver_disable ;;
    3) subserver_rotate_token ;;
    4)
      local url
      if url=$(share_sub_url); then
        if sbqd_has_cmd qrencode && [[ -t 1 ]]; then
          qrencode -t ANSIUTF8 -m 2 "${url}"
        else
          printf '%s\n' "${url}"
        fi
      else
        sbqd_err "$(sbqd_t '订阅服务未开启' 'subscription server is not enabled')"
      fi
      ;;
    *) return 0 ;;
  esac
}
