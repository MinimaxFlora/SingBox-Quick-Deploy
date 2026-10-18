# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034,SC2016
# =============================================================================
#  kernel.sh · sing-box 内核管理
#  职责：版本探测、下载安装（含镜像回退与校验）、密钥生成
# =============================================================================

SBQD_SINGBOX_MIN='1.12.0'
SBQD_REALITY_PRIVATE=''
SBQD_REALITY_PUBLIC=''

kernel_version() {
  if [[ ! -x ${SINGBOX_BIN} ]]; then
    return 1
  fi
  local first
  first=$("${SINGBOX_BIN}" version 2> /dev/null | head -n 1) || return 1
  printf '%s' "${first##* }"
}

kernel_installed() {
  [[ -x ${SINGBOX_BIN} ]]
}

kernel_latest_version() {
  local tag
  tag=$(curl -fsSL --max-time 15 --connect-timeout 8 \
    'https://api.github.com/repos/SagerNet/sing-box/releases/latest' 2> /dev/null |
    jq -r '.tag_name // empty' 2> /dev/null) || tag=''
  tag=${tag#v}
  printf '%s' "${tag}"
}

kernel_version_ge() {
  local have=$1 want=$2
  if [[ ${have} == "${want}" ]]; then
    return 0
  fi
  [[ $(printf '%s\n%s\n' "${want}" "${have}" | sort -V | tail -n 1) == "${have}" ]]
}

kernel_asset_digest() {
  local version=$1 asset=$2 digest
  digest=$(curl -fsSL --max-time 15 \
    "https://api.github.com/repos/SagerNet/sing-box/releases/tags/v${version}" 2> /dev/null |
    jq -r --arg n "${asset}" '.assets[] | select(.name == $n) | .digest // empty' 2> /dev/null) || digest=''
  digest=${digest#sha256:}
  printf '%s' "${digest}"
}

# 安装指定版本（默认最新），会覆盖现有二进制
kernel_install() {
  local version=${1:-}
  local fallback='1.14.3'
  if [[ -z ${version} ]]; then
    version=$(kernel_latest_version)
    if [[ -z ${version} ]]; then
      sbqd_warn "$(sbqd_t '无法查询最新版本，回退到 %s' \
        'cannot query the latest version, falling back to %s' "${fallback}")"
      version=${fallback}
    fi
  fi

  local asset url archive extract sha found
  asset="sing-box-${version}-linux-${SBQD_ARCH}.tar.gz"
  url="https://github.com/SagerNet/sing-box/releases/download/v${version}/${asset}"
  archive="${SBQD_TMP}/${asset}"
  extract="${SBQD_TMP}/sing-box-${version}"

  sbqd_info "$(sbqd_t '下载 sing-box %s（%s）…' 'downloading sing-box %s (%s)…' "${version}" "${SBQD_ARCH}")"
  sha=$(kernel_asset_digest "${version}" "${asset}")
  if [[ -n ${sha} ]]; then
    sbqd_debug "sha256=${sha}"
  else
    sbqd_warn "$(sbqd_t '未取得官方校验值，仅依赖 HTTPS 传输安全' \
      'official checksum unavailable, relying on HTTPS only')"
  fi

  if ! deps_download "${url}" "${archive}" "${sha}"; then
    sbqd_die "$(sbqd_t '下载 sing-box 失败：%s' 'failed to download sing-box: %s' "${url}")"
  fi

  mkdir -p "${extract}"
  tar -xzf "${archive}" -C "${extract}" || sbqd_die "$(sbqd_t '解压失败' 'failed to extract archive')"

  found=$(find "${extract}" -type f -name 'sing-box' -perm -u+x | head -n 1)
  if [[ -z ${found} ]]; then
    sbqd_die "$(sbqd_t '安装包中未找到 sing-box 二进制' 'sing-box binary not found in archive')"
  fi

  install -m 755 "${found}" "${SINGBOX_BIN}"

  local installed
  installed=$(kernel_version) || installed=''
  if [[ -z ${installed} ]]; then
    sbqd_die "$(sbqd_t '安装后无法执行 sing-box' 'installed sing-box is not executable')"
  fi
  if ! kernel_version_ge "${installed}" "${SBQD_SINGBOX_MIN}"; then
    sbqd_die "$(sbqd_t 'sing-box 版本过低（%s），最低要求 %s' \
      'sing-box version too old (%s), minimum is %s' "${installed}" "${SBQD_SINGBOX_MIN}")"
  fi

  state_update '.settings.singbox.version = $v' --arg v "${installed}"
  sbqd_ok "$(sbqd_t 'sing-box %s 安装完成' 'sing-box %s installed' "${installed}")"
  printf '%s' "${installed}"
}

# 确保内核可用且版本满足要求
kernel_ensure() {
  local current
  if kernel_installed; then
    current=$(kernel_version) || current=''
    if [[ -n ${current} ]] && kernel_version_ge "${current}" "${SBQD_SINGBOX_MIN}"; then
      return 0
    fi
    sbqd_warn "$(sbqd_t '已安装的 sing-box 版本为 %s，需要升级' \
      'installed sing-box %s needs an upgrade' "${current:-unknown}")"
  fi
  kernel_install "${1:-}" > /dev/null
}

kernel_upgrade() {
  local before after
  before=$(kernel_version 2> /dev/null) || before=''
  after=$(kernel_install '')
  sbqd_ok "$(sbqd_t '已从 %s 升级到 %s' 'upgraded from %s to %s' "${before:-none}" "${after}")"
  if kernel_installed; then
    config_apply
  fi
}

# --- 密钥生成 ---------------------------------------------------------------
kernel_generate_uuid() {
  local uuid
  if kernel_installed; then
    uuid=$("${SINGBOX_BIN}" generate uuid 2> /dev/null) || uuid=''
  else
    uuid=$(cat /proc/sys/kernel/random/uuid 2> /dev/null) || uuid=''
  fi
  if ! sbqd_is_uuid "${uuid}"; then
    sbqd_die "$(sbqd_t '生成 UUID 失败' 'failed to generate UUID')"
  fi
  printf '%s' "${uuid}"
}

kernel_generate_reality_keypair() {
  local out
  if ! kernel_installed; then
    sbqd_die "$(sbqd_t '需要先安装 sing-box 才能生成 Reality 密钥' \
      'sing-box must be installed to generate Reality keys')"
  fi
  out=$("${SINGBOX_BIN}" generate reality-keypair 2> /dev/null) || out=''
  SBQD_REALITY_PRIVATE=$(sed -n 's/^PrivateKey: //p' <<< "${out}")
  SBQD_REALITY_PUBLIC=$(sed -n 's/^PublicKey: //p' <<< "${out}")
  if [[ -z ${SBQD_REALITY_PRIVATE} || -z ${SBQD_REALITY_PUBLIC} ]]; then
    sbqd_die "$(sbqd_t '生成 Reality 密钥对失败' 'failed to generate Reality keypair')"
  fi
}

kernel_generate_short_id() {
  local sid
  if kernel_installed; then
    sid=$("${SINGBOX_BIN}" generate rand --hex 8 2> /dev/null) || sid=''
  fi
  if [[ -z ${sid} ]]; then
    sid=$(sbqd_rand_hex 8)
  fi
  printf '%s' "${sid}"
}

kernel_generate_password() {
  local pass
  if kernel_installed; then
    pass=$("${SINGBOX_BIN}" generate rand --base64 16 2> /dev/null) || pass=''
  fi
  if [[ -z ${pass} ]]; then
    pass=$(sbqd_rand_token 18)
  fi
  printf '%s' "${pass}"
}

kernel_uninstall() {
  if [[ -x ${SINGBOX_BIN} ]]; then
    rm -f -- "${SINGBOX_BIN}"
  fi
}
