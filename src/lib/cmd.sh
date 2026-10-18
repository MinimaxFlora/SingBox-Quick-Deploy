# shellcheck shell=bash
# shellcheck disable=SC2154,SC2016
# =============================================================================
#  cmd.sh · 非交互命令与入口分发
# =============================================================================

SBQD_JSON_OUT=${SBQD_JSON_OUT:-0}
SBQD_ASSUME_YES=${SBQD_ASSUME_YES:-0}
SBQD_LANG_FLAG=''

sbqd_usage() {
  cat << 'EOF'
SingBox-Quick-Deploy — sing-box 一键部署 / one-click deployment

用法 / Usage:
  sbqd                          打开管理菜单 (interactive menu)
  sbqd install [--yes]          安装或补全安装
  sbqd status [--json]          运行状态
  sbqd node add --type TYPE [--name N] [--port P] [--domain D] [--upstream ID]
  sbqd node list [--json]
  sbqd node show|delete|enable|disable|rotate|link|qr ID
  sbqd node set-upstream ID UPSTREAM_ID
  sbqd domain add DOMAIN --email EMAIL
  sbqd domain list|renew|delete DOMAIN
  sbqd upstream add --type socks5|shadowsocks --server HOST --port PORT ...
  sbqd upstream list|test|delete ID
  sbqd sub enable [--port P] [--domain D] [--panel URL]
  sbqd sub disable|status|url|rotate|refresh
  sbqd export [DIR]             导出链接/JSON/YAML/QX/二维码
  sbqd backup [FILE] | restore FILE | backups
  sbqd update [kernel|self]
  sbqd doctor                   环境自检
  sbqd uninstall [--purge]
  sbqd version | help

全局选项 / Global flags:
  --lang zh|en   界面语言
  --json         机器可读输出
  --yes          跳过确认
  --verbose      调试日志

节点类型 / Node types:
  vless-reality  VLESS + TCP + Reality + Vision（无需域名）
  hysteria2      Hysteria2（需要域名与证书）
  anytls         AnyTLS（需要域名与证书）
  tuic           TUIC v5（需要域名与证书）
  vmess-ws       VMess + TLS + WebSocket（需要域名与证书）

文档 / Docs: https://github.com/MinimaxFlora/SingBox-Quick-Deploy
EOF
}

sbqd_require_state_cmd() {
  if ! state_exists; then
    sbqd_die "$(sbqd_t '尚未安装，请先运行 sbqd install' 'not installed, run sbqd install first')"
  fi
}

cmd_status() {
  local kernel sub cert enabled
  sbqd_require_state_cmd
  kernel=$(kernel_version 2> /dev/null) || kernel=''
  sub=$(state_value '.settings.subscription.enabled' 'false')
  cert=$(state_cert_days_left)
  enabled=$(jq -r '[.nodes[] | select(.enabled)] | length' "${SBQD_STATE_FILE}")

  if [[ ${SBQD_JSON_OUT} == '1' ]]; then
    jq -n \
      --arg version "${SBQD_VERSION}" \
      --arg kernel "${kernel}" \
      --arg os "${SBQD_OS_PRETTY}" \
      --arg arch "${SBQD_ARCH}" \
      --arg service "$(if service_active; then printf 'running'; else printf 'stopped'; fi)" \
      --argjson nodes "$(state_node_count)" \
      --argjson enabled "${enabled}" \
      --argjson domains "$(state_domain_count)" \
      --argjson upstreams "$(state_upstream_count)" \
      --arg subscription "${sub}" \
      --argjson cert_days "${cert}" \
      --arg ip "$(state_value '.settings.public_ipv4' '')" '{
        version: $version, os: $os, arch: $arch, kernel: $kernel,
        service: $service,
        nodes: {total: $nodes, enabled: $enabled},
        domains: $domains, upstreams: $upstreams,
        subscription: $subscription, cert_days: $cert_days,
        public_ipv4: $ip
      }'
    return 0
  fi

  ui_box_top "$(sbqd_t '运行状态' 'Status')"
  ui_box_line "sing-box  ${kernel:-—}   ·   $(service_status_text)"
  ui_box_line "$(sbqd_t '节点' 'nodes') ${enabled}/$(state_node_count)  ·  $(sbqd_t '域名' 'domains') $(state_domain_count)  ·  $(sbqd_t '上游' 'upstreams') $(state_upstream_count)"
  ui_box_line "$(sbqd_t '订阅' 'subscription') ${sub}  ·  $(sbqd_t '证书' 'cert') $(if ((cert == 9999)); then printf '—'; else printf '%s %s' "${cert}" "$(sbqd_t '天' 'days')"; fi)"
  ui_box_line "$(SBQD_OS_PRETTY) ${SBQD_ARCH}  ·  $(state_value '.settings.public_ipv4' '-')"
  ui_box_bottom

  if [[ $(state_node_count) -gt 0 ]]; then
    printf '\n'
    nodes_list
  fi
}

cmd_node() {
  local sub=${1:-}
  [[ -n ${sub} ]] || {
    sbqd_err "$(sbqd_t '用法：sbqd node add|list|show|delete|...' 'usage: sbqd node add|list|show|delete|...')"
    return 1
  }
  shift
  case ${sub} in
    add) cmd_node_add "$@" ;;
    list) cmd_node_list "$@" ;;
    show) cmd_node_show "$@" ;;
    delete | del | rm) cmd_node_delete "$@" ;;
    enable | disable | toggle) cmd_node_toggle "${sub}" "$@" ;;
    rotate) cmd_node_rotate "$@" ;;
    link) cmd_node_link "$@" ;;
    qr) cmd_node_qr "$@" ;;
    set-upstream) cmd_node_set_upstream "$@" ;;
    *)
      sbqd_err "$(sbqd_t '未知子命令：%s' 'unknown subcommand: %s' "${sub}")"
      return 1
      ;;
  esac
}

cmd_node_add() {
  local type='' name='' port='' domain='' upstream=0 handshake=''
  while (($#)); do
    case $1 in
      --type)
        type=${2:-}
        shift 2
        ;;
      --name)
        name=${2:-}
        shift 2
        ;;
      --port)
        port=${2:-}
        shift 2
        ;;
      --domain)
        domain=${2:-}
        shift 2
        ;;
      --upstream)
        upstream=${2:-0}
        shift 2
        ;;
      --handshake)
        handshake=${2:-}
        shift 2
        ;;
      *) sbqd_err "$(sbqd_t '未知参数：%s' 'unknown argument: %s' "$1")" && return 1 ;;
    esac
  done
  [[ -n ${type} ]] || {
    sbqd_err "$(sbqd_t '缺少 --type' 'missing --type')"
    return 1
  }
  SBQD_NODE_HANDSHAKE=${handshake:-www.microsoft.com}
  sbqd_require_state_cmd
  nodes_create "${type}" "${name}" "${port}" "${domain}" "${upstream}"
}

cmd_node_list() {
  sbqd_require_state_cmd
  if [[ ${SBQD_JSON_OUT} == '1' ]]; then
    jq -c '.nodes' "${SBQD_STATE_FILE}"
  else
    nodes_list
  fi
}

cmd_node_show() {
  local id=${1:-}
  [[ -n ${id} ]] || {
    sbqd_err "$(sbqd_t '缺少节点 ID' 'missing node ID')"
    return 1
  }
  nodes_require_node "${id}" || return 1
  if [[ ${SBQD_JSON_OUT} == '1' ]]; then
    state_node_json "${id}" | jq .
  else
    nodes_detail "${id}"
    printf '\n'
    nodes_qr "${id}" 2> /dev/null || true
  fi
}

cmd_node_delete() {
  local id=${1:-} yes=0
  shift || true
  while (($#)); do
    case $1 in
      --yes | -y) yes=1 ;;
      *) ;;
    esac
    shift
  done
  [[ -n ${id} ]] || return 1
  nodes_delete "${id}" "${yes}"
}

cmd_node_toggle() {
  local action=$1 id=${2:-}
  [[ -n ${id} ]] || return 1
  case ${action} in
    enable) state_update '.nodes = [.nodes[] | if .id == $id then .enabled = true else . end]' --argjson id "${id}" && config_apply ;;
    disable) state_update '.nodes = [.nodes[] | if .id == $id then .enabled = false else . end]' --argjson id "${id}" && config_apply ;;
    toggle) nodes_toggle "${id}" ;;
  esac
}

cmd_node_rotate() {
  local id=${1:-}
  [[ -n ${id} ]] || return 1
  nodes_rotate "${id}"
}

cmd_node_link() {
  local id=${1:-} node
  [[ -n ${id} ]] || return 1
  nodes_require_node "${id}" || return 1
  node=$(state_node_json "${id}")
  share_node_uri "${node}"
  printf '\n'
}

cmd_node_qr() {
  local id=${1:-}
  [[ -n ${id} ]] || return 1
  nodes_qr "${id}"
}

cmd_node_set_upstream() {
  local id=${1:-} upstream=${2:-0}
  [[ -n ${id} ]] || return 1
  nodes_set_upstream "${id}" "${upstream}"
}

cmd_domain() {
  local sub=${1:-}
  [[ -n ${sub} ]] || return 1
  shift
  case ${sub} in
    add) cmd_domain_add "$@" ;;
    list) cmd_domain_list "$@" ;;
    renew) cert_renew "${1:-}" ;;
    delete | del | rm) cert_delete "${1:-}" ;;
    *) sbqd_err "$(sbqd_t '未知子命令：%s' 'unknown subcommand: %s' "${sub}")" && return 1 ;;
  esac
}

cmd_domain_add() {
  local domain=${1:-} email=''
  shift || true
  while (($#)); do
    case $1 in
      --email)
        email=${2:-}
        shift 2
        ;;
      *) shift ;;
    esac
  done
  [[ -n ${domain} ]] || {
    sbqd_err "$(sbqd_t '用法：sbqd domain add DOMAIN --email EMAIL' 'usage: sbqd domain add DOMAIN --email EMAIL')"
    return 1
  }
  sbqd_require_state_cmd
  cert_issue "${domain}" "${email}" || return 1
  firewall_sync || true
  share_publish || true
}

cmd_domain_list() {
  local domain days
  sbqd_require_state_cmd
  if [[ ${SBQD_JSON_OUT} == '1' ]]; then
    jq -c '.domains' "${SBQD_STATE_FILE}"
    return 0
  fi
  if [[ $(state_domain_count) == '0' ]]; then
    sbqd_info "$(sbqd_t '还没有托管域名' 'no managed domain yet')"
    return 0
  fi
  while IFS= read -r domain; do
    [[ -n ${domain} ]] || continue
    days=$(cert_days "${domain}")
    printf '%s  %s  %s %s\n' "${domain}" \
      "$(state_domain_field "${domain}" 'expires_at')" "${days}" "$(sbqd_t '天' 'days')"
  done < <(state_domain_names)
}

cmd_upstream() {
  local sub=${1:-}
  [[ -n ${sub} ]] || return 1
  shift
  case ${sub} in
    add) cmd_upstream_add "$@" ;;
    list) sbqd_require_state_cmd && relay_list ;;
    test) relay_test "${1:-}" ;;
    delete | del | rm) relay_delete "${1:-}" 1 ;;
    assign) nodes_set_upstream "${1:-}" "${2:-0}" ;;
    *) sbqd_err "$(sbqd_t '未知子命令：%s' 'unknown subcommand: %s' "${sub}")" && return 1 ;;
  esac
}

cmd_upstream_add() {
  local type='' name='' server='' port='' username='' password='' method=''
  while (($#)); do
    case $1 in
      --type)
        type=${2:-}
        shift 2
        ;;
      --name)
        name=${2:-}
        shift 2
        ;;
      --server)
        server=${2:-}
        shift 2
        ;;
      --port)
        port=${2:-}
        shift 2
        ;;
      --user | --username)
        username=${2:-}
        shift 2
        ;;
      --pass | --password)
        password=${2:-}
        shift 2
        ;;
      --method)
        method=${2:-}
        shift 2
        ;;
      *) shift ;;
    esac
  done
  sbqd_require_state_cmd
  relay_create "${type}" "${name}" "${server}" "${port}" "${username}" "${password}" "${method}"
}

cmd_sub() {
  local sub=${1:-}
  [[ -n ${sub} ]] || return 1
  shift
  case ${sub} in
    enable) cmd_sub_enable "$@" ;;
    disable) subserver_disable ;;
    status)
      if [[ ${SBQD_JSON_OUT} == '1' ]]; then
        jq -c '.settings.subscription' "${SBQD_STATE_FILE}"
      else
        subserver_status_text
        printf '\n'
      fi
      ;;
    url) share_sub_url && printf '\n' ;;
    rotate) subserver_rotate_token ;;
    refresh) share_publish && sbqd_ok "$(sbqd_t '已刷新' 'refreshed')" ;;
    *) sbqd_err "$(sbqd_t '未知子命令：%s' 'unknown subcommand: %s' "${sub}")" && return 1 ;;
  esac
}

cmd_sub_enable() {
  local port='' domain='' panel=''
  while (($#)); do
    case $1 in
      --port)
        port=${2:-}
        shift 2
        ;;
      --domain)
        domain=${2:-}
        shift 2
        ;;
      --panel)
        panel=${2:-}
        shift 2
        ;;
      *) shift ;;
    esac
  done
  sbqd_require_state_cmd
  subserver_enable "${port}" "${domain}" "${panel}"
}

cmd_export() {
  local dir=${1:-}
  sbqd_require_state_cmd
  if [[ -z ${dir} ]]; then
    dir="/root/sbqd-export-$(date '+%Y%m%d-%H%M%S')"
  fi
  share_export_dir "${dir}"
}

cmd_backup() {
  local file=${1:-}
  backup_create "${file}"
}

cmd_restore() {
  local file=${1:-}
  [[ -n ${file} ]] || {
    sbqd_err "$(sbqd_t '用法：sbqd restore FILE' 'usage: sbqd restore FILE')"
    return 1
  }
  backup_restore "${file}" "${SBQD_ASSUME_YES}"
}

cmd_doctor() {
  local failures=0 cert
  sbqd_info "$(sbqd_t '环境自检' 'Environment check')"
  printf '\n'
  detect_all
  printf '  os      %s\n' "${SBQD_OS_PRETTY}"
  printf '  arch    %s\n' "${SBQD_ARCH}"
  printf '  pkg     %s\n' "${SBQD_PKG_MGR:-unknown}"
  printf '  init    %s\n' "${SBQD_INIT}"
  printf '  kernel  sing-box %s (%s)\n' "$(kernel_version 2> /dev/null || printf 'not installed')" "${SINGBOX_BIN}"
  printf '\n'

  deps_check || failures=1

  printf '\n'
  if state_exists; then
    if state_validate; then
      sbqd_ok "$(sbqd_t '状态文件有效' 'state file is valid')"
    else
      failures=1
    fi
    if [[ -f ${SINGBOX_CONFIG_FILE} ]] && kernel_installed; then
      if config_check "${SINGBOX_CONFIG_FILE}"; then
        sbqd_ok "$(sbqd_t '运行配置有效' 'runtime config is valid')"
      else
        failures=1
      fi
    fi
    cert=$(state_cert_days_left)
    if ((cert != 9999 && cert < 14)); then
      sbqd_warn "$(sbqd_t '证书将在 %s 天后过期' 'certificate expires in %s days' "${cert}")"
    fi
  else
    sbqd_warn "$(sbqd_t '尚未安装（无状态文件）' 'not installed (no state file)')"
  fi

  printf '\n'
  if systemctl is-active --quiet sing-box 2> /dev/null; then
    sbqd_ok "$(sbqd_t 'sing-box 服务运行中' 'sing-box service is running')"
  else
    sbqd_warn "$(sbqd_t 'sing-box 服务未运行' 'sing-box service is not running')"
  fi

  printf '\n'
  if ((failures)); then
    sbqd_err "$(sbqd_t '自检发现问题，请查看上面的输出' 'issues found, see output above')"
    return 1
  fi
  sbqd_ok "$(sbqd_t '自检通过' 'all checks passed')"
}

sbqd_main() {
  local cmd=''
  local -a rest=()

  while (($#)); do
    case $1 in
      --lang)
        SBQD_LANG_FLAG=${2:-zh}
        shift 2
        ;;
      --json)
        SBQD_JSON_OUT=1
        shift
        ;;
      --yes | -y)
        SBQD_ASSUME_YES=1
        shift
        ;;
      --verbose | -v)
        SBQD_LOG_LEVEL='debug'
        shift
        ;;
      --version | -V)
        printf 'sbqd %s\n' "${SBQD_VERSION}"
        return 0
        ;;
      --help | -h)
        sbqd_usage
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        sbqd_err "$(sbqd_t '未知选项：%s' 'unknown option: %s' "$1")"
        sbqd_usage
        return 1
        ;;
      *)
        cmd=$1
        shift
        rest=("$@")
        break
        ;;
    esac
  done

  sbqd_init
  ui_init

  if [[ -n ${SBQD_LANG_FLAG} ]]; then
    if [[ ${SBQD_LANG_FLAG} == 'en' || ${SBQD_LANG_FLAG} == 'zh' ]]; then
      SBQD_LANG=${SBQD_LANG_FLAG}
    fi
  elif state_exists; then
    SBQD_LANG=$(state_language 2> /dev/null || printf 'zh')
  fi

  if [[ -z ${cmd} ]]; then
    if [[ -t 0 && -t 1 ]]; then
      sbqd_require_root
      detect_all
      if ! state_exists; then
        if sbqd_confirm '尚未安装，现在安装？' 'not installed yet, install now?' 'y'; then
          sbqd_lock
          sbqd_install
        else
          return 1
        fi
      fi
      sbqd_lock
      sbqd_menu_main
      return 0
    fi
    sbqd_usage
    return 1
  fi

  case ${cmd} in
    version)
      printf 'sbqd %s\n' "${SBQD_VERSION}"
      return 0
      ;;
    help | --help)
      sbqd_usage
      return 0
      ;;
  esac

  sbqd_require_root
  detect_all
  sbqd_lock

  case ${cmd} in
    install)
      local arg
      for arg in "${rest[@]}"; do
        if [[ ${arg} == '--yes' || ${arg} == '-y' ]]; then
          SBQD_ASSUME_YES=1
        fi
      done
      sbqd_install
      ;;
    menu)
      if ! state_exists; then
        sbqd_install
      fi
      sbqd_menu_main
      ;;
    status) cmd_status ;;
    node) cmd_node "${rest[@]}" ;;
    domain) cmd_domain "${rest[@]}" ;;
    upstream) cmd_upstream "${rest[@]}" ;;
    sub) cmd_sub "${rest[@]}" ;;
    export) cmd_export "${rest[@]}" ;;
    backup) cmd_backup "${rest[@]}" ;;
    restore) cmd_restore "${rest[@]}" ;;
    backups) backup_list ;;
    update)
      case ${rest[0]:-all} in
        kernel) kernel_upgrade ;;
        self) sbqd_update_self ;;
        all)
          kernel_upgrade
          sbqd_update_self || true
          ;;
        *) sbqd_err "$(sbqd_t '用法：sbqd update kernel|self' 'usage: sbqd update kernel|self')" && return 1 ;;
      esac
      ;;
    doctor) cmd_doctor ;;
    uninstall)
      local purge=0
      if [[ ${rest[0]:-} == '--purge' ]]; then
        purge=1
      fi
      sbqd_uninstall "${purge}"
      ;;
    *) sbqd_err "$(sbqd_t '未知命令：%s' 'unknown command: %s' "${cmd}")" && sbqd_usage && return 1 ;;
  esac
}
