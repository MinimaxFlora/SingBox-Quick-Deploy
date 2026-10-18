# shellcheck shell=bash
# shellcheck disable=SC2154
# =============================================================================
#  firewall.sh · 防火墙端口放行
#  自动处理 ufw / firewalld；nftables / iptables 仅提示，避免破坏既有规则
# =============================================================================

firewall_backend() {
  if sbqd_has_cmd ufw && ufw status 2> /dev/null | grep -q '^Status: active'; then
    printf 'ufw'
    return 0
  fi
  if sbqd_has_cmd firewall-cmd && [[ $(firewall-cmd --state 2> /dev/null) == 'running' ]]; then
    printf 'firewalld'
    return 0
  fi
  if sbqd_has_cmd nft && nft list chain inet filter input > /dev/null 2>&1; then
    printf 'nftables'
    return 0
  fi
  if sbqd_has_cmd iptables && iptables -S INPUT > /dev/null 2>&1; then
    printf 'iptables'
    return 0
  fi
  printf 'none'
}

firewall_open_port() {
  local port=$1 proto=${2:-tcp} backend
  backend=$(firewall_backend)
  case ${backend} in
    ufw)
      ufw allow "${port}/${proto}" > /dev/null 2>&1 || true
      ;;
    firewalld)
      firewall-cmd --permanent --add-port="${port}/${proto}" > /dev/null 2>&1 || true
      FIREWALL_CHANGED=1
      ;;
    nftables | iptables)
      return 2
      ;;
    *) return 1 ;;
  esac
  return 0
}

firewall_reload() {
  local backend
  backend=$(firewall_backend)
  case ${backend} in
    firewalld)
      if [[ ${FIREWALL_CHANGED:-0} == '1' ]]; then
        firewall-cmd --reload > /dev/null 2>&1 || true
        FIREWALL_CHANGED=0
      fi
      ;;
    ufw) ufw reload > /dev/null 2>&1 || true ;;
  esac
}

firewall_manual_hint() {
  local port=$1 proto=$2
  sbqd_warn "$(sbqd_t '请手动放行 %s/%s（脚本未修改 nftables/iptables 规则）' \
    'open %s/%s manually (nftables/iptables left untouched)' "${port}" "${proto}")"
}

firewall_sync() {
  state_require
  local backend ports entry port proto
  backend=$(firewall_backend)

  if [[ ${backend} == 'none' ]]; then
    sbqd_debug 'no active firewall detected'
    return 0
  fi

  ports=$(config_ports)
  local -a list=()
  if [[ -n ${ports} ]]; then
    while IFS= read -r entry; do
      if [[ -n ${entry} ]]; then
        list+=("${entry}")
      fi
    done <<< "${ports}"
  fi
  if [[ $(state_domain_count) -gt 0 ]]; then
    list+=('80/tcp')
  fi

  local -A seen=()
  local failed=0
  for entry in "${list[@]}"; do
    port=${entry%%/*}
    proto=${entry##*/}
    if [[ -n ${seen[${entry}]:-} ]]; then
      continue
    fi
    seen[${entry}]=1
    if ! firewall_open_port "${port}" "${proto}"; then
      if (($? == 2)); then
        firewall_manual_hint "${port}" "${proto}"
      fi
      failed=1
    fi
  done
  firewall_reload

  if ((failed == 0)); then
    sbqd_debug "firewall rules synced via ${backend}"
  fi
  return 0
}

firewall_status() {
  local backend
  backend=$(firewall_backend)
  case ${backend} in
    ufw) ufw status numbered 2> /dev/null || true ;;
    firewalld) firewall-cmd --list-all 2> /dev/null || true ;;
    nftables) nft list chain inet filter input 2> /dev/null || true ;;
    iptables) iptables -S INPUT 2> /dev/null || true ;;
    *) printf '%s\n' "$(sbqd_t '未检测到活动防火墙' 'no active firewall detected')" ;;
  esac
}
