# shellcheck shell=bash
# shellcheck disable=SC2154,SC2016
# =============================================================================
#  cert.sh · 域名与证书（acme.sh HTTP-01）
#  约束：仅使用 HTTP-01 standalone（需要 80 端口可达），不实现 DNS API
# =============================================================================

cert_dir() {
  printf '%s/%s' "${SINGBOX_CERT_DIR}" "$1"
}

cert_fullchain() {
  printf '%s/fullchain.pem' "$(cert_dir "$1")"
}

cert_privkey() {
  printf '%s/privkey.pem' "$(cert_dir "$1")"
}

cert_files_ok() {
  local domain=$1 fullchain key
  fullchain=$(cert_fullchain "${domain}")
  key=$(cert_privkey "${domain}")
  [[ -s ${fullchain} && -s ${key} ]]
}

# 校验证书与私钥是否匹配
cert_key_matches() {
  local domain=$1 fullchain key a b
  fullchain=$(cert_fullchain "${domain}")
  key=$(cert_privkey "${domain}")
  [[ -r ${fullchain} && -r ${key} ]] || return 1
  a=$(openssl x509 -in "${fullchain}" -noout -pubkey 2> /dev/null | openssl sha256 2> /dev/null) || return 1
  b=$(openssl pkey -in "${key}" -pubout 2> /dev/null | openssl sha256 2> /dev/null) || return 1
  [[ -n ${a} && ${a} == "${b}" ]]
}

cert_expiry_iso() {
  local fullchain=$1 raw
  raw=$(openssl x509 -in "${fullchain}" -noout -enddate 2> /dev/null) || return 1
  raw=${raw#notAfter=}
  date -u -d "${raw}" '+%Y-%m-%dT%H:%M:%SZ' 2> /dev/null
}

cert_days() {
  local domain=$1 iso
  iso=$(cert_expiry_iso "$(cert_fullchain "${domain}")") || {
    printf '0'
    return 0
  }
  sbqd_days_left "${iso}"
}

# 检查 80 端口是否被其他进程占用
cert_check_port80() {
  local listeners
  if ! sbqd_port_in_use 80 tcp; then
    return 0
  fi
  listeners=$(ss -lntp 'sport = :80' 2> /dev/null | tail -n +2) || listeners=''
  sbqd_err "$(sbqd_t '80 端口已被占用，HTTP-01 验证无法进行：' \
    'port 80 is already in use, HTTP-01 cannot proceed:')"
  printf '%s\n' "${listeners}" >&2
  sbqd_err "$(sbqd_t '请停止占用 80 端口的服务后重试' \
    'stop the service on port 80 and try again')"
  return 1
}

cert_dns_hint() {
  local domain=$1 public
  public=$(detect_public_ipv4 2> /dev/null) || public=''
  if [[ -z ${public} ]]; then
    return 0
  fi
  local resolved
  resolved=$(getent ahostsv4 "${domain}" 2> /dev/null | awk '{print $1}' | sort -u | tr '\n' ' ') || resolved=''
  if [[ -z ${resolved} ]]; then
    sbqd_warn "$(sbqd_t '域名 %s 未解析，请先添加 A 记录指向 %s' \
      'domain %s does not resolve, add an A record pointing to %s' "${domain}" "${public}")"
  elif [[ ${resolved} != *"${public}"* ]]; then
    sbqd_warn "$(sbqd_t '域名 %s 解析到 %s，与当前公网 IP %s 不一致' \
      'domain %s resolves to %s, which differs from public IP %s' "${domain}" "${resolved}" "${public}")"
  fi
}

# 申请并安装证书
cert_issue() {
  local domain=$1 email=$2
  local fullchain key dir log_file

  if ! sbqd_is_domain "${domain}"; then
    sbqd_err "$(sbqd_t '域名格式不合法：%s' 'invalid domain: %s' "${domain}")"
    return 1
  fi
  if [[ -z ${email} ]] || ! sbqd_is_email "${email}"; then
    sbqd_err "$(sbqd_t '需要有效的邮箱用于 ACME 注册' 'a valid email is required for ACME')"
    return 1
  fi

  cert_dns_hint "${domain}"
  cert_check_port80 || return 1
  deps_ensure_acme "${email}"

  dir=$(cert_dir "${domain}")
  fullchain=$(cert_fullchain "${domain}")
  key=$(cert_privkey "${domain}")
  mkdir -p -- "${dir}"
  chmod 750 "${SINGBOX_CERT_DIR}" "${dir}" 2> /dev/null || true
  chown "root:${SINGBOX_USER}" "${SINGBOX_CERT_DIR}" "${dir}" 2> /dev/null || true
  chmod 750 "${dir}"

  log_file="${SBQD_TMP}/acme-${domain}.log"

  sbqd_info "$(sbqd_t '向 Let'\''s Encrypt 申请证书：%s' 'requesting certificate from Let'\''s Encrypt: %s' "${domain}")"
  if ! "${ACME_SH}" --issue --standalone -d "${domain}" --httpport 80 \
    --server letsencrypt --keylength ec-256 >> "${log_file}" 2>&1; then
    sbqd_err "$(sbqd_t '证书申请失败，acme.sh 输出：' 'certificate issuance failed, acme.sh output:')"
    tail -n 30 "${log_file}" >&2
    return 1
  fi

  local reloadcmd='true'
  if service_unit_exists; then
    reloadcmd="systemctl reload ${SBQD_SERVICE_NAME}"
  fi

  if ! "${ACME_SH}" --install-cert -d "${domain}" --ecc \
    --key-file "${key}" --fullchain-file "${fullchain}" \
    --reloadcmd "${reloadcmd}" >> "${log_file}" 2>&1; then
    sbqd_err "$(sbqd_t '证书安装失败，acme.sh 输出：' 'certificate install failed, acme.sh output:')"
    tail -n 30 "${log_file}" >&2
    return 1
  fi

  chown root:"${SINGBOX_USER}" "${fullchain}" "${key}" 2> /dev/null || true
  chmod 640 "${fullchain}" "${key}"

  if ! cert_key_matches "${domain}"; then
    sbqd_err "$(sbqd_t '证书与私钥不匹配' 'certificate and private key do not match')"
    return 1
  fi

  cert_record "${domain}" "${email}" "${fullchain}" "${key}"
  cert_refresh_subserver "${domain}"
  sbqd_ok "$(sbqd_t '证书已就绪：%s（剩余 %s 天）' \
    'certificate ready: %s (%s days left)' "${domain}" "$(cert_days "${domain}")")"
  return 0
}

# 证书续期后同步订阅服务的 TLS 副本
cert_refresh_subserver() {
  local domain=$1
  if ! declare -F subserver_write_env > /dev/null 2>&1; then
    return 0
  fi
  if [[ $(state_value '.settings.subscription.enabled' 'false') != 'true' ]]; then
    return 0
  fi
  if [[ $(state_value '.settings.subscription.tls' 'false') != 'true' ]]; then
    return 0
  fi
  if [[ $(state_value '.settings.subscription.domain' '') != "${domain}" ]]; then
    return 0
  fi
  subserver_write_env 2> /dev/null || true
  systemctl restart sbqd-sub 2> /dev/null || true
  return 0
}

cert_record() {
  local domain=$1 email=$2 fullchain=$3 key=$4
  local expires now id

  expires=$(cert_expiry_iso "${fullchain}") || expires=''
  now=$(sbqd_iso_now)

  if state_domain_exists "${domain}"; then
    state_update '.domains = (.domains | map(
      if .domain == $d then
        .email = $mail | .cert_path = $c | .key_path = $k |
        .issued_at = $at | .expires_at = $exp
      else . end))' \
      --arg d "${domain}" --arg mail "${email}" \
      --arg c "${fullchain}" --arg k "${key}" \
      --arg at "${now}" --arg exp "${expires}"
  else
    id=$(state_alloc_id next_domain_id)
    state_update '.domains += [$d]' --argjson d "$(jq -nc \
      --argjson id "${id}" --arg domain "${domain}" --arg mail "${email}" \
      --arg c "${fullchain}" --arg k "${key}" \
      --arg at "${now}" --arg exp "${expires}" '{
        id: $id, domain: $domain, email: $mail,
        cert_path: $c, key_path: $k,
        issued_at: $at, expires_at: $exp, auto_renew: true
      }')"
  fi
}

cert_renew() {
  local domain=$1
  if ! state_domain_exists "${domain}"; then
    sbqd_err "$(sbqd_t '域名未托管：%s' 'domain not managed: %s' "${domain}")"
    return 1
  fi
  if [[ ! -x ${ACME_SH} ]]; then
    sbqd_die "$(sbqd_t 'acme.sh 未安装' 'acme.sh is not installed')"
  fi

  sbqd_info "$(sbqd_t '续期证书：%s' 'renewing certificate: %s' "${domain}")"
  local log_file="${SBQD_TMP}/acme-renew-${domain}.log"
  if ! "${ACME_SH}" --renew -d "${domain}" --ecc --force --server letsencrypt >> "${log_file}" 2>&1; then
    sbqd_err "$(sbqd_t '续期失败：' 'renewal failed:')"
    tail -n 30 "${log_file}" >&2
    return 1
  fi
  "${ACME_SH}" --install-cert -d "${domain}" --ecc \
    --key-file "$(cert_privkey "${domain}")" \
    --fullchain-file "$(cert_fullchain "${domain}")" \
    --reloadcmd "systemctl reload ${SBQD_SERVICE_NAME}" >> "${log_file}" 2>&1 || true
  chmod 640 "$(cert_fullchain "${domain}")" "$(cert_privkey "${domain}")" 2> /dev/null || true
  cert_record "${domain}" "$(state_domain_field "${domain}" 'email')" \
    "$(cert_fullchain "${domain}")" "$(cert_privkey "${domain}")"
  cert_refresh_subserver "${domain}"
  sbqd_ok "$(sbqd_t '已续期：%s' 'renewed: %s' "${domain}")"
}

cert_delete() {
  local domain=$1 keep_files=${2:-false}
  if ! state_domain_exists "${domain}"; then
    sbqd_err "$(sbqd_t '域名未托管：%s' 'domain not managed: %s' "${domain}")"
    return 1
  fi
  local used
  used=$(jq -r --arg d "${domain}" '[.nodes[] | select(.domain == $d)] | length' "${SBQD_STATE_FILE}")
  if ((used > 0)); then
    sbqd_err "$(sbqd_t '仍有 %s 个节点使用域名 %s，请先删除或改绑节点' \
      '%s nodes still use domain %s, remove or rebind them first' "${used}" "${domain}")"
    return 1
  fi
  state_update '.domains = [.domains[] | select(.domain != $d)]' --arg d "${domain}"
  if [[ ${keep_files} != 'true' ]]; then
    rm -rf -- "$(cert_dir "${domain}")"
  fi
  sbqd_ok "$(sbqd_t '已移除域名：%s' 'domain removed: %s' "${domain}")"
}

cert_list_lines() {
  local domain expires days
  while IFS= read -r domain; do
    [[ -n ${domain} ]] || continue
    expires=$(state_domain_field "${domain}" 'expires_at')
    days=$(sbqd_days_left "${expires}")
    printf '%s|%s|%s\n' "${domain}" "${expires}" "${days}"
  done < <(state_domain_names)
}
