# shellcheck shell=bash
# shellcheck disable=SC2154
# =============================================================================
#  menu.sh · 交互式菜单（geto 风格：扁平主菜单 + 装完即出链接）
# =============================================================================

menu_header() {
  local title=$1
  ui_clear
  printf '\n  %s%s%s  %sv%s%s\n' "${SBQD_C_PRIMARY}${SBQD_C_BOLD}" \
    "${SBQD_NAME}" "${SBQD_C_RESET}" "${SBQD_C_DIM}" "${SBQD_VERSION}" "${SBQD_C_RESET}"
  ui_hr
  ui_section "${title}"
}

# geto 风格信息头
sbqd_banner_geto() {
  local kernel service ips nodes=0 enabled=0 domains=0 sub='-'
  ui_clear
  kernel=$(kernel_version 2> /dev/null) || kernel='未安装'

  if state_exists; then
    service=$(service_status_text)
    nodes=$(state_node_count 2> /dev/null || printf '0')
    enabled=$(jq -r '[.nodes[] | select(.enabled)] | length' "${SBQD_STATE_FILE}" 2> /dev/null) || enabled=0
    domains=$(state_domain_count 2> /dev/null || printf '0')
    sub=$(subserver_status_text 2> /dev/null || printf '-')
    ips=$(jq -r '.settings.detected_ips // [] | join("、")' "${SBQD_STATE_FILE}" 2> /dev/null) || ips=''
  else
    service='未安装'
    ips=''
  fi
  if [[ -z ${ips} ]]; then
    if [[ -z ${SBQD_BANNER_IPS:-} ]]; then
      SBQD_BANNER_IPS=$(detect_public_ips_or_v6 | paste -sd '、' - 2> /dev/null) || SBQD_BANNER_IPS=''
    fi
    ips=${SBQD_BANNER_IPS}
  fi

  printf '%s当前检测到信息%s\n' "${SBQD_C_BOLD}" "${SBQD_C_RESET}"
  printf '操作系统：%s\n' "${SBQD_OS_PRETTY:-unknown}"
  printf '服务器IP：%s\n' "${ips:-未检测到}"
  printf '%s--------------------------------------------------%s\n' "${SBQD_C_DIM}" "${SBQD_C_RESET}"
  printf '当前版本：v%s     sing-box：%s（%s）\n' "${SBQD_VERSION}" "${kernel}" "${service}"
  printf '节点：%s/%s    域名：%s    订阅：%s\n' "${enabled}" "${nodes}" "${domains}" "${sub}"
  printf '%s--------------------------------------------------%s\n' "${SBQD_C_DIM}" "${SBQD_C_RESET}"
}

# 多 IP 选择（geto 风格：0 或回车=全部，支持 1,3 与 1-2）
menu_choose_ips() {
  local -a all=()
  local -a tokens=()
  local i c token a b j nips
  local -A seen=()

  mapfile -t all < <(detect_public_ips_or_v6)
  nips=${#all[@]}
  SBQD_SELECTED_IPS=()

  if ((nips == 0)); then
    sbqd_err "$(sbqd_t '没有检测到公网 IP，请检查网络或在设置中手动填写' \
      'no public IP detected, check the network or set it in Settings')"
    return 1
  fi
  if ((nips == 1)); then
    SBQD_SELECTED_IPS=("${all[0]}")
    return 0
  fi

  printf '\n%s检测到多个公网 IP%s\n' "${SBQD_C_BOLD}" "${SBQD_C_RESET}"
  printf '请选择要安装的 IP（每个 IP 独立端口、独立密钥）\n'
  printf '  0) 全部 IP\n'
  i=1
  for c in "${all[@]}"; do
    printf '  %s) %s\n' "${i}" "${c}"
    i=$((i + 1))
  done
  printf '支持：0 / 1 / 1-2 / 1,3（回车=全部）\n'

  while :; do
    printf '请输入数字 [0]: '
    if ! IFS= read -r c; then
      c=0
    fi
    c=${c//[[:space:]]/}
    if [[ -z ${c} || ${c} == '0' ]]; then
      SBQD_SELECTED_IPS=("${all[@]}")
      return 0
    fi

    SBQD_SELECTED_IPS=()
    seen=()
    local ok=1
    IFS=',' read -ra tokens <<< "${c}"
    for token in "${tokens[@]}"; do
      if [[ ${token} =~ ^([1-9][0-9]*)-([1-9][0-9]*)$ ]]; then
        a=${BASH_REMATCH[1]}
        b=${BASH_REMATCH[2]}
        if ((a > b || b > nips)); then
          sbqd_warn "无效区间：${token}"
          ok=0
          break
        fi
        for ((j = a; j <= b; j++)); do
          if [[ -n ${seen[${j}]:-} ]]; then
            continue
          fi
          seen[${j}]=1
          SBQD_SELECTED_IPS+=("${all[j - 1]}")
        done
      elif [[ ${token} =~ ^[1-9][0-9]*$ ]]; then
        if ((token > nips)); then
          sbqd_warn "没有第 ${token} 个 IP"
          ok=0
          break
        fi
        if [[ -n ${seen[${token}]:-} ]]; then
          continue
        fi
        seen[${token}]=1
        SBQD_SELECTED_IPS+=("${all[token - 1]}")
      else
        sbqd_warn "请输入 0、序号或区间，例如 1-2 或 1,3"
        ok=0
        break
      fi
    done
    if ((ok)) && ((${#SBQD_SELECTED_IPS[@]} > 0)); then
      printf '已选择：%s\n' "${SBQD_SELECTED_IPS[*]}"
      return 0
    fi
  done
}

menu_choose_mode() {
  printf '\n安装模式\n'
  printf '  1) 快速（推荐，全自动：随机端口 + 自签证书）\n'
  printf '  2) 自定义（端口 / 域名 / 伪装目标）\n'
  printf '请选择 [1]: '
  local c
  if ! IFS= read -r c; then
    c=1
  fi
  if [[ ${c} == '2' ]]; then
    printf 'custom'
  else
    printf 'quick'
  fi
}

# 安装后逐个输出链接 / 二维码
menu_print_nodes() {
  local id
  for id in "$@"; do
    nodes_print_share "${id}" || true
    printf '\n'
  done
}

# --- 安装流程 ---------------------------------------------------------------
menu_install_type() {
  local type=$1
  local ip port name domain tls_mode mode handshake
  local -a ids=()

  if ! sbqd_ensure_base; then
    return 1
  fi
  if ! menu_choose_ips; then
    return 1
  fi
  mode=$(menu_choose_mode)

  for ip in "${SBQD_SELECTED_IPS[@]}"; do
    port=''
    name=''
    domain=''
    tls_mode=''

    if [[ ${type} == 'vless-reality' ]]; then
      handshake=''
      if [[ ${mode} == 'custom' ]]; then
        sbqd_prompt "$(sbqd_t 'Reality 伪装域名' 'Reality handshake domain')" \
          'Reality handshake domain' "$(nodes_random_handshake)"
        handshake=${REPLY}
      else
        handshake=$(nodes_random_handshake)
      fi
      SBQD_NODE_HANDSHAKE=${handshake}
      tls_mode='reality'
    else
      if [[ ${mode} == 'custom' ]]; then
        if [[ $(state_domain_count) -gt 0 ]]; then
          printf '\n已托管域名：%s\n' "$(state_domain_names | paste -sd ', ' -)"
        fi
        sbqd_prompt "$(sbqd_t 'TLS 域名（留空 = 自签证书）' 'TLS domain (empty = self-signed)')" \
          'TLS domain (empty = self-signed)' ''
        domain=${REPLY}
        if [[ -n ${domain} ]]; then
          if ! state_domain_exists "${domain}" || ! cert_files_ok "${domain}"; then
            sbqd_err "$(sbqd_t '域名 %s 尚未签发证书，请先到「域名与证书」添加' \
              'domain %s has no certificate, add it in Domains first' "${domain}")"
            return 1
          fi
          tls_mode='domain'
        fi
      fi
    fi

    if [[ ${mode} == 'custom' ]]; then
      sbqd_prompt "$(sbqd_t '端口（留空随机）' 'Port (empty = random)')" 'Port (empty = random)' ''
      port=${REPLY}
      sbqd_prompt "$(sbqd_t '节点名称（留空自动）' 'Node name (empty = auto)')" 'Node name (empty = auto)' ''
      name=${REPLY}
    fi

    if ! nodes_create "${type}" "${name}" "${port}" "${domain}" 0 "${ip}" "${tls_mode}" > /dev/null; then
      continue
    fi
    ids+=("${SBQD_LAST_NODE_ID}")
  done

  if ((${#ids[@]} == 0)); then
    return 1
  fi
  menu_print_nodes "${ids[@]}"

  if [[ $(state_value '.settings.subscription.enabled' 'false') != 'true' ]] &&
    sbqd_confirm '是否开启订阅服务？客户端可一键导入全部节点' 'enable subscription server?' 'y'; then
    local sport
    sport=$(sbqd_rand_port)
    subserver_enable "${sport}" '' '' || true
  fi
}

# --- 节点管理 ---------------------------------------------------------------
sbqd_menu_nodes() {
  local choice id
  while :; do
    menu_header "$(sbqd_t '查看 / 管理节点' 'View / manage nodes')"
    nodes_list
    ui_item 1 "$(sbqd_t '查看全部链接 / 二维码' 'Show all links / QR')" ''
    ui_item 2 "$(sbqd_t '按 ID 查看' 'Show by ID')" ''
    ui_item 3 "$(sbqd_t '删除节点' 'Delete node')" ''
    ui_item 4 "$(sbqd_t '启用 / 停用' 'Enable / disable')" ''
    ui_item 5 "$(sbqd_t '重置密钥' 'Rotate secrets')" ''
    ui_item 6 "$(sbqd_t '设置中转' 'Set upstream')" ''
    ui_item 0 "$(sbqd_t '返回' 'Back')" ''
    ui_ask
    choice=${REPLY}
    case ${choice} in
      1)
        if [[ $(state_node_count) -gt 0 ]]; then
          # shellcheck disable=SC2046
          menu_print_nodes $(state_node_ids)
        fi
        ui_pause
        ;;
      2)
        if id=$(menu_prompt_id '节点 ID' 'Node ID'); then
          nodes_print_share "${id}" || true
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
      sbqd_info "$(sbqd_t '还没有托管域名（TLS 节点可直接用自签证书）' \
        'no managed domain yet (TLS nodes can use self-signed certificates)')"
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
  local choice min max
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
  Quantumult X                                     QX conf（仅 VMess）

  自签证书节点：客户端需要允许不安全连接（insecure / skip-cert-verify）
  域名节点：acme.sh 自动签发，客户端无需跳过校验

  文档 / Docs
  https://github.com/MinimaxFlora/SingBox-Quick-Deploy
EOF
  ui_pause
}

# --- 主菜单（geto 风格） ----------------------------------------------------
menu_require_state() {
  if state_exists; then
    return 0
  fi
  sbqd_warn "$(sbqd_t '请先安装一个节点，再使用该功能' 'install a node first')"
  sleep 1
  return 1
}

sbqd_menu_main() {
  local choice
  while :; do
    sbqd_banner_geto
    printf '\n%s安装（可共存，一次装一种）%s\n' "${SBQD_C_BOLD}" "${SBQD_C_RESET}"
    printf '  1) VLESS + TCP + Reality + Vision      直连（最推荐）\n'
    printf '  2) Hysteria2                           UDP 加速\n'
    printf '  3) AnyTLS                              TCP 伪装\n'
    printf '  4) TUIC v5                             UDP 低延迟\n'
    printf '  5) VMess + TLS + WebSocket             兼容性最好\n'
    printf '\n%s中转%s\n' "${SBQD_C_BOLD}" "${SBQD_C_RESET}"
    printf '  6) 添加中转（SOCKS5 / Shadowsocks）\n'
    printf '\n%s管理%s\n' "${SBQD_C_BOLD}" "${SBQD_C_RESET}"
    printf '  7) 查看节点 / 链接 / 二维码\n'
    printf '  8) 域名与证书（acme.sh）\n'
    printf '  9) 订阅与导出\n'
    printf ' 10) 设置\n'
    printf ' 11) 系统状态 / 日志 / 备份\n'
    printf ' 12) 卸载\n'
    printf '  0) 退出\n'
    printf '  关闭 SSH 后，输入 sbqd 可重新打开菜单\n'
    printf '\n请输入选项: '

    if ! IFS= read -r choice; then
      exit 0
    fi
    case ${choice} in
      1) menu_install_type 'vless-reality' ;;
      2) menu_install_type 'hysteria2' ;;
      3) menu_install_type 'anytls' ;;
      4) menu_install_type 'tuic' ;;
      5) menu_install_type 'vmess-ws' ;;
      6) if menu_require_state; then sbqd_menu_relay; fi ;;
      7) if menu_require_state; then sbqd_menu_nodes; fi ;;
      8) if menu_require_state; then sbqd_menu_domain; fi ;;
      9) if menu_require_state; then sbqd_menu_subscription; fi ;;
      10) if menu_require_state; then sbqd_menu_settings; fi ;;
      11) if menu_require_state; then sbqd_menu_system; fi ;;
      12)
        if sbqd_uninstall; then
          exit 0
        fi
        ;;
      0 | q | Q) exit 0 ;;
      *)
        sbqd_warn '无效选项'
        sleep 1
        ;;
    esac

    if [[ ${choice} =~ ^[1-5]$ ]]; then
      ui_pause
    fi
  done
}
