# shellcheck shell=bash
# shellcheck disable=SC2154
# =============================================================================
#  service.sh · systemd 服务管理
#  职责：运行用户、unit 文件、启停/重载、状态与日志
# =============================================================================

SBQD_SERVICE_NAME='sing-box'

service_unit_exists() {
  systemctl cat "${SBQD_SERVICE_NAME}" > /dev/null 2>&1
}

service_active() {
  systemctl is-active --quiet "${SBQD_SERVICE_NAME}" 2> /dev/null
}

service_enabled() {
  systemctl is-enabled --quiet "${SBQD_SERVICE_NAME}" 2> /dev/null
}

service_user_ensure() {
  if ! getent group "${SINGBOX_USER}" > /dev/null 2>&1; then
    groupadd --system "${SINGBOX_USER}" 2> /dev/null ||
      sbqd_die "$(sbqd_t '创建用户组 %s 失败' 'failed to create group %s' "${SINGBOX_USER}")"
  fi
  if ! id -u "${SINGBOX_USER}" > /dev/null 2>&1; then
    local nologin
    nologin=$(command -v nologin || printf '/usr/sbin/nologin')
    useradd --system --gid "${SINGBOX_USER}" --home-dir "${SINGBOX_STATE_DIR}" \
      --no-create-home --shell "${nologin}" "${SINGBOX_USER}" 2> /dev/null ||
      sbqd_die "$(sbqd_t '创建用户 %s 失败' 'failed to create user %s' "${SINGBOX_USER}")"
  fi
}

service_write_unit() {
  service_user_ensure
  mkdir -p -- "${SINGBOX_CONFIG_DIR}" "${SINGBOX_STATE_DIR}"
  chmod 750 "${SINGBOX_CONFIG_DIR}"

  if [[ -f ${SINGBOX_UNIT_FILE} ]] && ! grep -q 'SingBox-Quick-Deploy' "${SINGBOX_UNIT_FILE}" 2> /dev/null; then
    local backup
    backup="${SINGBOX_UNIT_FILE}.sbqd.bak"
    if [[ ! -f ${backup} ]]; then
      cp -f -- "${SINGBOX_UNIT_FILE}" "${backup}"
      sbqd_warn "$(sbqd_t '已备份原有 unit 到 %s' 'backed up existing unit to %s' "${backup}")"
    fi
  fi

  cat > "${SBQD_TMP}/sing-box.service" << EOF
# Managed by SingBox-Quick-Deploy — do not edit manually.
# 由 SingBox-Quick-Deploy 管理，请勿手工修改。
[Unit]
Description=sing-box service (SingBox-Quick-Deploy)
Documentation=${SBQD_HOME_URL}
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=${SINGBOX_USER}
Group=${SINGBOX_USER}
StateDirectory=sing-box
WorkingDirectory=${SINGBOX_STATE_DIR}
ExecStart=${SINGBOX_BIN} -D ${SINGBOX_STATE_DIR} -c ${SINGBOX_CONFIG_FILE} run
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=false
ReadWritePaths=${SINGBOX_STATE_DIR}

[Install]
WantedBy=multi-user.target
EOF

  install -m 644 "${SBQD_TMP}/sing-box.service" "${SINGBOX_UNIT_FILE}"
  systemctl daemon-reload || sbqd_die "$(sbqd_t 'systemctl daemon-reload 失败' 'systemctl daemon-reload failed')"
}

service_start() {
  systemctl start "${SBQD_SERVICE_NAME}" 2> /dev/null || return 1
}

service_enable_start() {
  systemctl enable "${SBQD_SERVICE_NAME}" > /dev/null 2>&1 || true
  if ! service_active; then
    systemctl start "${SBQD_SERVICE_NAME}" || return 1
  fi
  return 0
}

service_reload() {
  if ! service_active; then
    systemctl start "${SBQD_SERVICE_NAME}" || return 1
    return 0
  fi
  # SIGHUP 会先 check 再完整重建实例；失败时保留旧实例
  systemctl reload "${SBQD_SERVICE_NAME}" 2> /dev/null || systemctl restart "${SBQD_SERVICE_NAME}" || return 1
  return 0
}

service_restart() {
  systemctl restart "${SBQD_SERVICE_NAME}" 2> /dev/null || return 1
}

service_stop() {
  systemctl stop "${SBQD_SERVICE_NAME}" 2> /dev/null || true
}

service_wait_active() {
  local i=0
  while ((i < 15)); do
    if service_active; then
      return 0
    fi
    i=$((i + 1))
    sleep 0.3
  done
  return 1
}

service_status_text() {
  if ! service_unit_exists; then
    sbqd_t '未安装' 'not installed'
    return 0
  fi
  if service_active; then
    sbqd_t '运行中' 'running'
  else
    sbqd_t '已停止' 'stopped'
  fi
}

service_status_color() {
  if service_active; then
    printf '%s' "${SBQD_C_GREEN}"
  else
    printf '%s' "${SBQD_C_RED}"
  fi
}

service_logs() {
  local lines=${1:-50}
  journalctl -u "${SBQD_SERVICE_NAME}" -n "${lines}" --no-pager 2> /dev/null ||
    sbqd_warn "$(sbqd_t '无法读取 journal 日志' 'cannot read journal logs')"
}

service_pid() {
  systemctl show -p MainPID --value "${SBQD_SERVICE_NAME}" 2> /dev/null || printf '0'
}

service_uninstall() {
  systemctl stop "${SBQD_SERVICE_NAME}" 2> /dev/null || true
  systemctl disable "${SBQD_SERVICE_NAME}" 2> /dev/null || true
  rm -f -- "${SINGBOX_UNIT_FILE}"
  if [[ -f ${SINGBOX_UNIT_FILE}.sbqd.bak ]]; then
    mv -f -- "${SINGBOX_UNIT_FILE}.sbqd.bak" "${SINGBOX_UNIT_FILE}"
  fi
  systemctl daemon-reload 2> /dev/null || true
}
