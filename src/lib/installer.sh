# shellcheck shell=bash
# shellcheck disable=SC2154
# =============================================================================
#  installer.sh · 安装、首次配置与自更新
# =============================================================================

sbqd_language_choose() {
  ui_section "$(sbqd_t '界面语言 / Language' '界面语言 / Language')"
  ui_item 1 '中文' ''
  ui_item 2 'English' ''
  ui_ask
  case ${REPLY} in
    2)
      SBQD_LANG='en'
      state_set_language 'en'
      ;;
    *)
      SBQD_LANG='zh'
      state_set_language 'zh'
      ;;
  esac
}

sbqd_install_base() {
  local ip4 ip6 api_port

  sbqd_require_root
  detect_all

  if [[ ${SBQD_INIT} != 'systemd' ]]; then
    sbqd_die "$(sbqd_t '当前环境没有运行 systemd，无法安装服务' \
      'systemd is not running, cannot install the service')"
  fi
  if [[ -z ${SBQD_ARCH} ]]; then
    sbqd_die "$(sbqd_t '无法识别 CPU 架构' 'cannot detect CPU architecture')"
  fi

  deps_install_base
  deps_ensure_qrencode || true

  state_init

  ip4=$(detect_public_ipv4 2> /dev/null) || ip4=$(detect_local_ipv4 2> /dev/null) || ip4=''
  ip6=$(detect_public_ipv6 2> /dev/null) || ip6=''
  if [[ -n ${ip4} && -z $(state_value '.settings.public_ipv4') ]]; then
    state_update '.settings.public_ipv4 = $ip' --arg ip "${ip4}"
  fi
  if [[ -n ${ip6} && -z $(state_value '.settings.public_ipv6') ]]; then
    state_update '.settings.public_ipv6 = $ip' --arg ip "${ip6}"
  fi

  api_port=$(state_value '.settings.clash_api.port' '0')
  if [[ ! ${api_port} =~ ^[0-9]+$ ]] || ((api_port == 0)); then
    api_port=$(sbqd_rand_port)
    state_update '.settings.clash_api.port = $p' --argjson p "${api_port}"
  fi

  kernel_ensure
  service_write_unit
  config_apply
  service_enable_start || sbqd_die "$(sbqd_t 'sing-box 服务启动失败' 'failed to start sing-box service')"
  firewall_sync || true
}

sbqd_install_summary() {
  local kernel nodes domains sub cert
  kernel=$(kernel_version 2> /dev/null) || kernel='-'
  nodes=$(state_node_count)
  domains=$(state_domain_count)
  sub=$(subserver_status_text)
  cert=$(state_cert_days_left)

  printf '\n'
  ui_box_top "$(sbqd_t '安装完成' 'Installation complete')"
  ui_box_line "$(sbqd_t '内核' 'Kernel')       sing-box ${kernel}"
  ui_box_line "$(sbqd_t '服务' 'Service')      $(service_status_text)"
  ui_box_line "$(sbqd_t '节点' 'Nodes')        ${nodes}"
  ui_box_line "$(sbqd_t '域名' 'Domains')      ${domains}"
  ui_box_line "$(sbqd_t '证书' 'Certificate')  $(if ((cert == 9999)); then sbqd_t '暂无' 'none'; else printf '%s %s' "${cert}" "$(sbqd_t '天' 'days')"; fi)"
  ui_box_line "$(sbqd_t '订阅' 'Subscription') ${sub}"
  ui_box_bottom
  printf '\n   %s\n\n' "$(sbqd_t '运行 sbqd 打开管理菜单' 'run sbqd to open the management menu')"
}

# 首次交互配置
sbqd_first_run() {
  sbqd_language_choose

  if sbqd_confirm '现在配置域名与证书？（需要 80 端口与正确解析）' \
    'configure a domain and certificate now? (needs port 80 and DNS)' 'n'; then
    sbqd_menu_domain_add || true
  fi

  if sbqd_confirm '现在添加第一个节点？' 'add the first node now?' 'y'; then
    nodes_add_interactive || true
  fi

  if sbqd_confirm '开启订阅服务？' 'enable the subscription server?' 'y'; then
    local port
    port=$(sbqd_rand_port)
    subserver_enable "${port}" '' '' || true
  fi
}

sbqd_install() {
  if ((SBQD_TTY)); then
    ui_banner
  fi
  sbqd_install_base
  if [[ ${SBQD_ASSUME_YES:-0} != '1' && -t 0 ]] && [[ $(state_node_count) == '0' ]]; then
    sbqd_first_run
  fi
  sbqd_install_summary
}

# 自更新：从 GitHub Release 下载最新单文件
sbqd_update_self() {
  local latest url tmp current new_version
  sbqd_require_root

  current=${SBQD_VERSION}
  latest=$(curl -fsSL --max-time 15 --connect-timeout 8 \
    "https://api.github.com/repos/${SBQD_REPO}/releases/latest" 2> /dev/null |
    jq -r '.tag_name // empty' 2> /dev/null) || latest=''
  latest=${latest#v}

  if [[ -z ${latest} ]]; then
    sbqd_err "$(sbqd_t '无法获取最新版本信息（GitHub API 不可达）' \
      'cannot query the latest release (GitHub API unreachable)')"
    return 1
  fi
  if [[ ${latest} == "${current}" ]]; then
    sbqd_ok "$(sbqd_t '已是最新版本：%s' 'already up to date: %s' "${current}")"
    return 0
  fi

  url="https://github.com/${SBQD_REPO}/releases/download/v${latest}/sbqd.sh"
  tmp="${SBQD_TMP}/sbqd.sh"
  if ! curl -fL --retry 3 --connect-timeout 10 -o "${tmp}" "${url}"; then
    sbqd_err "$(sbqd_t '下载新版本失败' 'failed to download the new version')"
    return 1
  fi
  if ! bash -n "${tmp}"; then
    sbqd_err "$(sbqd_t '新版本脚本语法校验失败，已放弃更新' 'new script failed syntax check, update aborted')"
    return 1
  fi

  new_version=$(bash "${tmp}" --version 2> /dev/null | awk '{print $2}') || new_version=''
  if [[ -z ${new_version} ]]; then
    sbqd_warn "$(sbqd_t '无法读取新版本号，继续更新' 'cannot read new version, continuing')"
  fi

  local target=${SBQD_SELF:-${SBQD_BIN_DIR}/sbqd}
  install -m 755 "${tmp}" "${target}"
  sbqd_ok "$(sbqd_t '脚本已更新：%s → %s' 'script updated: %s → %s' "${current}" "${latest}")"
  if service_unit_exists; then
    systemctl daemon-reload 2> /dev/null || true
  fi
}
