# shellcheck shell=bash
# shellcheck disable=SC2154
# =============================================================================
#  backup.sh · 备份、恢复与卸载
#  备份内容：state.json、订阅文件、sing-box 配置、证书、unit 文件
# =============================================================================

SBQD_BACKUP_DIR=${SBQD_BACKUP_DIR:-/root/sbqd-backups}

backup_create() {
  local output=${1:-} stamp
  sbqd_require_root
  stamp=$(date '+%Y%m%d-%H%M%S')
  if [[ -z ${output} ]]; then
    mkdir -p -- "${SBQD_BACKUP_DIR}"
    chmod 700 "${SBQD_BACKUP_DIR}"
    output="${SBQD_BACKUP_DIR}/sbqd-${stamp}.tar.gz"
  fi

  local -a paths=()
  if [[ -d ${SBQD_ETC} ]]; then paths+=('etc/sbqd'); fi
  if [[ -d ${SINGBOX_CONFIG_DIR} ]]; then paths+=('etc/sing-box'); fi
  if [[ -f /etc/systemd/system/sbqd-sub.service ]]; then paths+=('etc/systemd/system/sbqd-sub.service'); fi
  if [[ -f ${SINGBOX_UNIT_FILE} ]]; then paths+=('etc/systemd/system/sing-box.service'); fi

  if ((${#paths[@]} == 0)); then
    sbqd_err "$(sbqd_t '没有可备份的内容，请先完成安装' 'nothing to back up, install first')"
    return 1
  fi

  tar -czf "${output}" -C / "${paths[@]}" 2> /dev/null ||
    sbqd_die "$(sbqd_t '打包备份失败' 'failed to create backup archive')"
  chmod 600 "${output}"
  sbqd_ok "$(sbqd_t '备份完成：%s' 'backup created: %s' "${output}")"
  printf '%s\n' "${output}"
}

backup_list() {
  if [[ ! -d ${SBQD_BACKUP_DIR} ]]; then
    sbqd_info "$(sbqd_t '还没有备份' 'no backups yet')"
    return 0
  fi
  find "${SBQD_BACKUP_DIR}" -maxdepth 1 -type f -name '*.tar.gz' -printf '%TY-%Tm-%Td %TH:%TM  %10s  %p\n' 2> /dev/null |
    sort -r || true
}

backup_verify() {
  local file=$1
  [[ -r ${file} ]] || {
    sbqd_err "$(sbqd_t '备份文件不存在：%s' 'backup file not found: %s' "${file}")"
    return 1
  }
  tar -tzf "${file}" 2> /dev/null | grep -qx 'etc/sbqd/state.json' ||
    {
      sbqd_err "$(sbqd_t '备份中缺少 state.json' 'state.json missing from backup')"
      return 1
    }
}

backup_restore() {
  local file=$1 assume_yes=${2:-0} workdir

  backup_verify "${file}" || return 1
  if [[ ${assume_yes} != '1' ]] &&
    ! sbqd_confirm "$(sbqd_t '恢复会覆盖当前配置与证书，继续？' \
      'restore will overwrite current config and certificates, continue?')" \
      'Restore backup?' 'n'; then
    return 1
  fi

  workdir=$(mktemp -d "${SBQD_TMP}/restore.XXXXXX")
  tar -xzf "${file}" -C "${workdir}" || {
    sbqd_err "$(sbqd_t '解压备份失败' 'failed to extract backup')"
    return 1
  }

  if ! jq -e '.schema == 1' "${workdir}/etc/sbqd/state.json" > /dev/null 2>&1; then
    sbqd_err "$(sbqd_t '备份中的状态文件无效' 'invalid state file in backup')"
    return 1
  fi

  service_stop
  systemctl stop sbqd-sub 2> /dev/null || true

  mkdir -p -- "${SBQD_ETC}" "${SINGBOX_CONFIG_DIR}"
  cp -a -- "${workdir}/etc/sbqd/." "${SBQD_ETC}/"
  if [[ -d ${workdir}/etc/sing-box ]]; then
    cp -a -- "${workdir}/etc/sing-box/." "${SINGBOX_CONFIG_DIR}/"
  fi
  if [[ -f ${workdir}/etc/systemd/system/sing-box.service ]]; then
    install -m 644 "${workdir}/etc/systemd/system/sing-box.service" "${SINGBOX_UNIT_FILE}"
  fi
  if [[ -f ${workdir}/etc/systemd/system/sbqd-sub.service ]]; then
    install -m 644 "${workdir}/etc/systemd/system/sbqd-sub.service" "/etc/systemd/system/sbqd-sub.service"
  fi
  systemctl daemon-reload 2> /dev/null || true

  chmod 600 "${SBQD_STATE_FILE}"
  if [[ -d ${SINGBOX_CERT_DIR} ]]; then
    chown -R root:"${SINGBOX_USER}" "${SINGBOX_CERT_DIR}" 2> /dev/null || true
    find "${SINGBOX_CERT_DIR}" -type f -exec chmod 640 {} + 2> /dev/null || true
  fi

  state_validate || {
    sbqd_err "$(sbqd_t '恢复后的状态校验失败' 'restored state validation failed')"
    return 1
  }

  config_apply || {
    sbqd_err "$(sbqd_t '恢复后应用配置失败，请检查日志' 'failed to apply restored config, check logs')"
    return 1
  }
  if [[ $(state_value '.settings.subscription.enabled' 'false') == 'true' ]]; then
    subserver_write_env 2> /dev/null || true
    systemctl start sbqd-sub 2> /dev/null || true
  fi

  rm -rf -- "${workdir}"
  sbqd_ok "$(sbqd_t '恢复完成' 'restore completed')"
}

# 卸载：默认保留配置与证书，--purge 时彻底删除
sbqd_uninstall() {
  local purge=${1:-0}
  sbqd_require_root

  if ! sbqd_confirm "$(sbqd_t '确认卸载 SingBox-Quick-Deploy？' \
    'uninstall SingBox-Quick-Deploy?')" 'Uninstall?' 'n'; then
    return 1
  fi

  systemctl stop sbqd-sub 2> /dev/null || true
  systemctl disable sbqd-sub 2> /dev/null || true
  rm -f /etc/systemd/system/sbqd-sub.service
  service_uninstall

  if ((purge)); then
    sbqd_warn "$(sbqd_t '将删除配置、证书与状态文件' 'config, certificates and state will be deleted')"
    rm -rf -- "${SBQD_ETC}" "${SINGBOX_CONFIG_DIR}"
    rm -f -- "${SINGBOX_BIN}"
    rm -rf -- "${SBQD_LIB_DIR}"
    userdel "${SBQD_SUB_USER}" 2> /dev/null || true
  else
    sbqd_info "$(sbqd_t '已保留 %s 与 %s' 'kept %s and %s' "${SBQD_ETC}" "${SINGBOX_CONFIG_DIR}")"
  fi

  if [[ -f ${SBQD_SELF:-} ]]; then
    rm -f -- "${SBQD_SELF}"
  fi
  systemctl daemon-reload 2> /dev/null || true
  sbqd_ok "$(sbqd_t '卸载完成' 'uninstall completed')"
}
