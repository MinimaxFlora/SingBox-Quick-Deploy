# shellcheck shell=bash
# shellcheck disable=SC2154
# =============================================================================
#  menu.sh · 交互式 TUI
# =============================================================================

menu_header() {
  local title=$1
  ui_clear
  printf '\n  %s%s%s  %sv%s%s\n' "${SBQD_C_PRIMARY}${SBQD_C_BOLD}" \
    "${SBQD_NAME}" "${SBQD_C_RESET}" "${SBQD_C_DIM}" "${SBQD_VERSION}" "${SBQD_C_RESET}"
  ui_hr
  ui_section "${title}"
}

sbqd_dashboard() {
  local kernel service nodes enabled domains sub cert ip desc
  kernel=$(kernel_version 2> /dev/null) || kernel='-'
  service=$(service_status_text)
  nodes=$(state_node_count)
  enabled=$(jq -r '[.nodes[] | select(.enabled)] | length' "${SBQD_STATE_FILE}" 2> /dev/null) || enabled=0
  domains=$(state_domain_count)
  sub=$(subserver_status_text)
  cert=$(state_cert_days_left)
  ip=$(state_value '.settings.public_ipv4' '')
  desc="$(sbqd_t '系统' 'OS') ${SBQD_OS_PRETTY} · ${SBQD_ARCH}"

  ui_box_top ''
  ui_box_line "sing-box ${kernel}  ·  ${service}  ·  $(sbqd_t '节点' 'nodes') ${enabled}/${nodes}" "${SBQD_C_WHITE}"
  ui_box_line "$(sbqd_t '域名' 'domains') ${domains}  ·  $(sbqd_t '证书' 'cert') $(if ((cert == 9999)); then printf '—'; else printf '%s %s' "${cert}" "$(sbqd_t '天' 'days')"; fi)  ·  $(sbqd_t '订阅' 'subscription') ${sub}"
  ui_box_line "${desc}  ·  ${ip:-$(sbqd_t '地址未设置' 'no address')}"
  ui_box_bottom
}

menu_prompt_id() {
  local zh=$1 en=$2 id
  sbqd_prompt "${zh}" "${en}" ''
  id=${REPLY}
  if [[ -z ${id} ]]; then
    return 1
  fi
  printf '%s' "${id}"
}

# --- 节点 -------------------------------------------------------------------
sbqd_menu_nodes() {
  local choice id
  while :; do
    menu_header "$(sbqd_t '节点管理' 'Node management')"
    nodes_list
    ui_item 1 "$(sbqd_t '添加节点' 'Add node')" 'Reality / HY2 / AnyTLS / TUIC / VMess'
    ui_item 2 "$(sbqd_t '节点详情' 'Node details')" "$(sbqd_t '含分享链接' 'with share link')"
    ui_item 3 "$(sbqd_t '删除节点' 'Delete node')" ''
    ui_item 4 "$(sbqd_t '启用 / 停用' 'Enable / disable')" ''
    ui_item 5 "$(sbqd_t '重置密钥' 'Rotate secrets')" ''
    ui_item 6 "$(sbqd_t '设置中转' 'Set upstream relay')" ''
    ui_item 7 "$(sbqd_t '二维码' 'QR code')" ''
    ui_item 0 "$(sbqd_t '返回' 'Back')" ''
    ui_ask
    choice=${REPLY}
    case ${choice} in
      1)
        nodes_add_interactive || true
        ui_pause
        ;;
      2)
        if id=$(menu_prompt_id '节点 ID' 'Node ID'); then
          nodes_detail "${id}" || true
          ui_pause
        fi
        ;;
      3)
        if id=$(menu_prompt_id '节点 ID' 'Node ID'); then
          nodes_delete "${id}" || true
          ui_pause
        fi
        ;;
      4)
        if id=$(menu_prompt_id '节点 ID' 'Node ID'); then
          nodes_toggle "${id}" || true
          ui_pause
        fi
        ;;
      5)
        if id=$(menu_prompt_id '节点 ID' 'Node ID'); then
          nodes_rotate "${id}" || true
          ui_pause
        fi
        ;;
      6)
        if id=$(menu_prompt_id '节点 ID' 'Node ID'); then
          relay_assign_interactive "${id}" || true
          ui_pause
        fi
        ;;
      7)
        if id=$(menu_prompt_id '节点 ID' 'Node ID'); then
          nodes_qr "${id}" || true
          ui_pause
        fi
        ;;
      0) return 0 ;;
      *) ;;
    esac
  done
}

# --- 订阅与导出 -------------------------------------------------------------
sbqd_menu_subscription() {
  local choice dir id
  while :; do
    menu_header "$(sbqd_t '订阅与导出' 'Subscription & export')"
    if [[ $(state_value '.settings.subscription.enabled' 'false') == 'true' ]]; then
      subserver_print_url 2> /dev/null || true
    fi
    ui_item 1 "$(sbqd_t '订阅服务设置' 'Subscription server')" "$(subserver_status_text)"
    ui_item 2 "$(sbqd_t '导出配置包' 'Export bundle')" 'Base64 / JSON / YAML / QX / QR'
    ui_item 3 "$(sbqd_t '查看全部链接' 'Show all links')" ''
    ui_item 4 "$(sbqd_t '节点二维码' 'Node QR code')" ''
    ui_item 5 "$(sbqd_t '刷新订阅文件' 'Refresh subscription files')" ''
    ui_item 0 "$(sbqd_t '返回' 'Back')" ''
    ui_ask
    choice=${REPLY}
    case ${choice} in
      1)
        subserver_setup_interactive
        ui_pause
        ;;
      2)
        dir="/root/sbqd-export-$(date '+%Y%m%d-%H%M%S')"
        sbqd_prompt "$(sbqd_t '导出目录' 'Export directory')" 'Export directory' "${dir}"
        share_export_dir "${REPLY}" || true
        ui_pause
        ;;
      3)
        share_links || true
        ui_pause
        ;;
      4)
        if id=$(menu_prompt_id '节点 ID' 'Node ID'); then
          nodes_qr "${id}" || true
          ui_pause
        fi
        ;;
      5)
        share_publish && sbqd_ok "$(sbqd_t '订阅文件已刷新' 'subscription files refreshed')"
        ui_pause
        ;;
      0) return 0 ;;
      *) ;;
    esac
  done
}

# --- 域名与证书 -------------------------------------------------------------
sbqd_menu_domain_add() {
  local domain email
  sbqd_prompt "$(sbqd_t '域名（如 node.example.com）' 'Domain (e.g. node.example.com)')" \
    'Domain (e.g. node.example.com)' ''
  domain=${REPLY}
  if [[ -z ${domain} ]]; then
    return 1
  fi
  if state_domain_exists "${domain}" && ! sbqd_confirm \
    "$(sbqd_t '域名已存在，重新签发证书？' 'domain exists, re-issue certificate?')" \
    'Re-issue certificate?' 'n'; then
    return 0
  fi

  sbqd_prompt "$(sbqd_t 'ACME 邮箱' 'ACME email')" 'ACME email' "$(state_domain_field "${domain}" 'email' 2> /dev/null || true)"
  email=${REPLY}
  if [[ -z ${email} ]]; then
    sbqd_err "$(sbqd_t '邮箱不能为空' 'email cannot be empty')"
    return 1
  fi

  cert_issue "${domain}" "${email}" || return 1
  firewall_sync || true
  share_publish || true
}

sbqd_menu_domain() {
  local choice domain
  local -a table=()
  while :; do
    menu_header "$(sbqd_t '域名与证书' 'Domains & certificates')"
    if [[ $(state_domain_count) == '0' ]]; then
      sbqd_info "$(sbqd_t '还没有托管域名' 'no managed domain yet')"
    else
      table=()
      while IFS= read -r domain; do
        [[ -n ${domain} ]] || continue
        table+=("${domain}|$(state_domain_field "${domain}" 'expires_at')|$(cert_days "${domain}") $(sbqd_t '天' 'days')")
      done < <(state_domain_names)
      ui_table "$(sbqd_t '域名|到期时间|剩余' 'Domain|Expires|Left')" "${table[@]}"
    fi

    ui_item 1 "$(sbqd_t '添加域名（HTTP-01）' 'Add domain (HTTP-01)')" ''
    ui_item 2 "$(sbqd_t '续期证书' 'Renew certificate')" ''
    ui_item 3 "$(sbqd_t '删除域名' 'Delete domain')" ''
    ui_item 0 "$(sbqd_t '返回' 'Back')" ''
    ui_ask
    choice=${REPLY}
    case ${choice} in
      1)
        sbqd_menu_domain_add || true
        ui_pause
        ;;
      2)
        sbqd_prompt "$(sbqd_t '域名' 'Domain')" 'Domain' ''
        if [[ -n ${REPLY} ]]; then
          cert_renew "${REPLY}" || true
          ui_pause
        fi
        ;;
      3)
        sbqd_prompt "$(sbqd_t '域名' 'Domain')" 'Domain' ''
        if [[ -n ${REPLY} ]]; then
          cert_delete "${REPLY}" || true
          ui_pause
        fi
        ;;
      0) return 0 ;;
      *) ;;
    esac
  done
}

# --- 中转 -------------------------------------------------------------------
sbqd_menu_relay() {
  local choice id
  while :; do
    menu_header "$(sbqd_t '中转上游' 'Upstream relay')"
    relay_list
    ui_item 1 "$(sbqd_t '添加上游' 'Add upstream')" 'SOCKS5 / Shadowsocks'
    ui_item 2 "$(sbqd_t '测试连通性' 'Test connectivity')" ''
    ui_item 3 "$(sbqd_t '删除上游' 'Delete upstream')" ''
    ui_item 0 "$(sbqd_t '返回' 'Back')" ''
    ui_ask
    choice=${REPLY}
    case ${choice} in
      1)
        relay_add_interactive || true
        ui_pause
        ;;
      2)
        if id=$(menu_prompt_id '上游 ID' 'Upstream ID'); then
          relay_test "${id}" || true
          ui_pause
        fi
        ;;
      3)
        if id=$(menu_prompt_id '上游 ID' 'Upstream ID'); then
          relay_delete "${id}" || true
          ui_pause
        fi
        ;;
      0) return 0 ;;
      *) ;;
    esac
  done
}

# --- 系统 -------------------------------------------------------------------
sbqd_menu_system() {
  local choice
  while :; do
    menu_header "$(sbqd_t '系统与服务' 'System & service')"
    ui_kv "$(sbqd_t '服务' 'service')" "$(service_status_text)  (pid $(service_pid))"
    ui_kv "$(sbqd_t '内核' 'kernel')" "sing-box $(kernel_version 2> /dev/null || printf '-')"
    ui_item 1 "$(sbqd_t '运行状态' 'Status')" ''
    ui_item 2 "$(sbqd_t '服务日志' 'Service logs')" ''
    ui_item 3 "$(sbqd_t '重启服务' 'Restart service')" ''
    ui_item 4 "$(sbqd_t '更新内核' 'Update kernel')" ''
    ui_item 5 "$(sbqd_t '更新脚本' 'Update script')" ''
    ui_item 6 "$(sbqd_t '防火墙状态' 'Firewall status')" ''
    ui_item 7 "$(sbqd_t '备份' 'Backup')" ''
    ui_item 8 "$(sbqd_t '恢复' 'Restore')" ''
    ui_item 9 "$(sbqd_t '卸载' 'Uninstall')" ''
    ui_item 0 "$(sbqd_t '返回' 'Back')" ''
    ui_ask
    choice=${REPLY}
    case ${choice} in
      1)
        sbqd_show_status
        ui_pause
        ;;
      2)
        service_logs 50
        ui_pause
        ;;
      3)
        if service_restart; then
          sbqd_ok "$(sbqd_t '服务已重启' 'service restarted')"
        else
          sbqd_err "$(sbqd_t '重启失败' 'restart failed')"
        fi
        ui_pause
        ;;
      4)
        kernel_upgrade || true
        ui_pause
        ;;
      5)
        sbqd_update_self || true
        ui_pause
        ;;
      6)
        firewall_status
        ui_pause
        ;;
      7)
        backup_create || true
        ui_pause
        ;;
      8)
        sbqd_prompt "$(sbqd_t '备份文件路径' 'Backup file path')" 'Backup file path' ''
        if [[ -n ${REPLY} ]]; then
          backup_restore "${REPLY}" || true
          ui_pause
        fi
        ;;
      9)
        sbqd_uninstall 0 || true
        exit 0
        ;;
      0) return 0 ;;
      *) ;;
    esac
  done
}

sbqd_show_status() {
  local kernel sub cert
  kernel=$(kernel_version 2> /dev/null) || kernel='-'
  sub=$(subserver_status_text)
  cert=$(state_cert_days_left)

  ui_table "$(sbqd_t '项目|值' 'Item|Value')" \
    "$(sbqd_t 'sing-box|' 'sing-box|')${kernel}" \
    "$(sbqd_t '服务状态|' 'service|')$(service_status_text)" \
    "$(sbqd_t '监听 PID|' 'pid|')$(service_pid)" \
    "$(sbqd_t '配置文件|' 'config|')${SINGBOX_CONFIG_FILE}" \
    "$(sbqd_t '证书剩余|' 'cert days|')$(if ((cert == 9999)); then printf '—'; else printf '%s' "${cert}"; fi)" \
    "$(sbqd_t '订阅服务|' 'subscription|')${sub}"

  printf '\n'
  printf '  %s\n' "$(sbqd_t '端口：' 'ports:')"
  config_ports | while IFS= read -r line; do
    printf '    %s\n' "${line}"
  done

  printf '\n'
  if [[ -f ${SINGBOX_CONFIG_FILE} ]] && kernel_installed; then
    if config_check "${SINGBOX_CONFIG_FILE}"; then
      sbqd_ok "$(sbqd_t '当前配置校验通过' 'current config is valid')"
    fi
  fi
}

# --- 设置 -------------------------------------------------------------------
sbqd_menu_settings() {
  local choice value min max
  while :; do
    menu_header "$(sbqd_t '设置' 'Settings')"
    ui_kv "$(sbqd_t '语言' 'language')" "${SBQD_LANG}"
    ui_kv "$(sbqd_t '公网地址' 'address')" "$(state_value '.settings.public_ipv4' '-') / $(state_value '.settings.public_ipv6' '-')"
    ui_kv "$(sbqd_t '端口范围' 'port range')" "$(state_value '.settings.port_min')-$(state_value '.settings.port_max')"
    ui_kv 'Clash API' "$(state_value '.settings.clash_api.listen' '127.0.0.1'):$(state_value '.settings.clash_api.port' '0')"
    ui_item 1 "$(sbqd_t '切换语言' 'Switch language')" ''
    ui_item 2 "$(sbqd_t '设置公网地址' 'Set public address')" ''
    ui_item 3 "$(sbqd_t '设置端口范围' 'Set port range')" ''
    ui_item 4 "$(sbqd_t '重置 Clash API 密钥' 'Rotate Clash API secret')" ''
    ui_item 5 "$(sbqd_t '设置面板地址' 'Set panel URL')" ''
    ui_item 0 "$(sbqd_t '返回' 'Back')" ''
    ui_ask
    choice=${REPLY}
    case ${choice} in
      1)
        sbqd_language_choose
        ui_pause
        ;;
      2)
        sbqd_prompt '公网 IPv4' 'Public IPv4' "$(state_value '.settings.public_ipv4' '')"
        if [[ -n ${REPLY} ]]; then
          state_update '.settings.public_ipv4 = $v' --arg v "${REPLY}"
        fi
        sbqd_prompt '公网 IPv6' 'Public IPv6' "$(state_value '.settings.public_ipv6' '')"
        if [[ -n ${REPLY} ]]; then
          state_update '.settings.public_ipv6 = $v' --arg v "${REPLY}"
        fi
        if share_publish; then
          subserver_restart || true
        fi
        ui_pause
        ;;
      3)
        sbqd_prompt '最小端口' 'Min port' "$(state_value '.settings.port_min' '20000')"
        min=${REPLY}
        sbqd_prompt '最大端口' 'Max port' "$(state_value '.settings.port_max' '60000')"
        max=${REPLY}
        if sbqd_is_port "${min}" && sbqd_is_port "${max}" && ((min < max)); then
          state_update '.settings.port_min = $a | .settings.port_max = $b' \
            --argjson a "${min}" --argjson b "${max}"
          sbqd_ok "$(sbqd_t '端口范围已更新' 'port range updated')"
        else
          sbqd_err "$(sbqd_t '端口范围不合法' 'invalid port range')"
        fi
        ui_pause
        ;;
      4)
        state_update '.settings.clash_api.secret = $s' --arg s "$(sbqd_rand_token 18)"
        config_apply || true
        subserver_restart || true
        sbqd_ok "$(sbqd_t 'Clash API 密钥已重置' 'Clash API secret rotated')"
        ui_pause
        ;;
      5)
        sbqd_prompt '外部面板 URL' 'External panel URL' "$(state_value '.settings.subscription.panel_url' '')"
        state_update '.settings.subscription.panel_url = $v' --arg v "${REPLY}"
        subserver_restart || true
        ui_pause
        ;;
      0) return 0 ;;
      *) ;;
    esac
  done
}

sbqd_menu_help() {
  menu_header "$(sbqd_t '帮助' 'Help')"
  cat << 'EOF'
  客户端导入 / Client import
  ------------------------------------------------------------------
  Shadowrocket / v2rayNG / Passwall / Homeproxy    Base64 链接列表
  Stash / OpenClash / Nikki / FlClash / CMFA       Mihomo YAML
  sing-box (SFI / SFA)                             sing-box JSON
  Quantumult X                                     QX conf（仅 VMess，实验性）

  单节点导入：节点详情 → 分享链接 / 二维码
  订阅导入：订阅地址（按 UA 自动返回对应格式）

  文档 / Docs
  https://github.com/MinimaxFlora/SingBox-Quick-Deploy
EOF
  ui_pause
}

# --- 主菜单 -----------------------------------------------------------------
sbqd_menu_main() {
  local choice
  while :; do
    ui_clear
    ui_banner
    sbqd_dashboard
    ui_section "$(sbqd_t '管理' 'Manage')"
    ui_item 1 "$(sbqd_t '节点管理' 'Nodes')" "$(state_node_count) $(sbqd_t '个节点' 'nodes')"
    ui_item 2 "$(sbqd_t '订阅与导出' 'Subscription & export')" ''
    ui_item 3 "$(sbqd_t '域名与证书' 'Domains & certificates')" "$(state_domain_count)"
    ui_item 4 "$(sbqd_t '中转上游' 'Upstream relay')" "$(state_upstream_count)"
    ui_item 5 "$(sbqd_t '系统与服务' 'System & service')" ''
    ui_item 6 "$(sbqd_t '设置' 'Settings')" ''
    ui_item 7 "$(sbqd_t '帮助' 'Help')" ''
    ui_item 0 "$(sbqd_t '退出' 'Exit')" ''
    ui_ask
    choice=${REPLY}
    case ${choice} in
      1) sbqd_menu_nodes ;;
      2) sbqd_menu_subscription ;;
      3) sbqd_menu_domain ;;
      4) sbqd_menu_relay ;;
      5) sbqd_menu_system ;;
      6) sbqd_menu_settings ;;
      7) sbqd_menu_help ;;
      0 | q | Q) exit 0 ;;
      *) ;;
    esac
  done
}
