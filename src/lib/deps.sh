# shellcheck shell=bash
# shellcheck disable=SC2154
# =============================================================================
#  deps.sh · 依赖与外部组件
#  职责：系统依赖安装、acme.sh 安装、运行期依赖检查
# =============================================================================

# 运行时必需（订阅服务需要 python3，二维码需要 qrencode 但可降级）
DEPS_APT='curl wget tar unzip jq openssl socat cron qrencode python3 iproute2 ca-certificates'
DEPS_DNF='curl wget tar unzip jq openssl socat cronie python3 iproute ca-certificates'

deps_pkg_install() {
  local pkgs=$1
  case ${SBQD_PKG_MGR} in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq || sbqd_warn "$(sbqd_t 'apt-get update 失败，继续尝试安装' 'apt-get update failed, trying install anyway')"
      # shellcheck disable=SC2086
      apt-get install -y -qq --no-install-recommends ${pkgs}
      ;;
    dnf | yum)
      # shellcheck disable=SC2086
      ${SBQD_PKG_MGR} install -y -q ${pkgs}
      ;;
    apk)
      # shellcheck disable=SC2086
      apk add --no-cache ${pkgs}
      ;;
    *)
      sbqd_die "$(sbqd_t '没有可用的包管理器，请手动安装：%s' \
        'no package manager available, install manually: %s' "${pkgs}")"
      ;;
  esac
}

deps_install_base() {
  local missing=() cmd
  for cmd in curl jq openssl tar unzip socat crontab; do
    if ! sbqd_has_cmd "${cmd}"; then
      missing+=("${cmd}")
    fi
  done

  if ! sbqd_has_cmd python3; then
    missing+=('python3')
  fi
  if ! sbqd_has_cmd ss; then
    missing+=('ss')
  fi

  if ((${#missing[@]} == 0)); then
    sbqd_debug 'base dependencies already satisfied'
    return 0
  fi

  sbqd_info "$(sbqd_t '安装基础依赖：%s' 'installing base dependencies: %s' "${missing[*]}")"
  case ${SBQD_PKG_MGR} in
    apt) deps_pkg_install "${DEPS_APT}" ;;
    dnf | yum) deps_pkg_install "${DEPS_DNF}" ;;
    apk) deps_pkg_install 'curl jq openssl tar unzip python3 iproute2 socat qrencode' ;;
    *) sbqd_die "$(sbqd_t '无法自动安装依赖，请手动安装：%s' \
      'cannot install dependencies automatically, install manually: %s' "${missing[*]}")" ;;
  esac
}

# qrencode 为可选依赖；RHEL 系需要 EPEL
deps_ensure_qrencode() {
  if sbqd_has_cmd qrencode; then
    return 0
  fi
  sbqd_info "$(sbqd_t '尝试安装 qrencode（用于二维码）' 'trying to install qrencode (QR codes)')"
  if [[ ${SBQD_PKG_MGR} == 'apt' ]]; then
    deps_pkg_install 'qrencode' > /dev/null 2>&1 || true
  elif [[ ${SBQD_PKG_MGR} == 'dnf' || ${SBQD_PKG_MGR} == 'yum' ]]; then
    if ! deps_pkg_install 'qrencode' > /dev/null 2>&1; then
      sbqd_warn "$(sbqd_t 'qrencode 需要 EPEL 源，尝试启用' 'qrencode needs EPEL, trying to enable it')"
      ${SBQD_PKG_MGR} install -y -q epel-release > /dev/null 2>&1 || true
      deps_pkg_install 'qrencode' > /dev/null 2>&1 || true
    fi
  fi
  if ! sbqd_has_cmd qrencode; then
    sbqd_warn "$(sbqd_t 'qrencode 不可用，二维码功能将降级为链接文本' \
      'qrencode unavailable, QR codes will fall back to plain links')"
    return 1
  fi
  return 0
}

# 安装 acme.sh（幂等）
deps_ensure_acme() {
  local email=$1
  if [[ -x ${ACME_SH} ]]; then
    return 0
  fi

  sbqd_info "$(sbqd_t '安装 acme.sh…' 'installing acme.sh…')"

  local tmp
  tmp=$(mktemp "${SBQD_TMP}/acme-install.XXXXXX.sh")
  if ! curl -fsSL --retry 3 --connect-timeout 10 \
    'https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh' \
    -o "${tmp}" 2> /dev/null; then
    sbqd_warn "$(sbqd_t '从 GitHub 下载 acme.sh 失败，尝试镜像' 'download failed, trying mirror')"
    curl -fsSL --retry 3 --connect-timeout 10 \
      'https://ghproxy.net/https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh' \
      -o "${tmp}" || sbqd_die "$(sbqd_t '无法下载 acme.sh' 'cannot download acme.sh')"
  fi

  mkdir -p /root/.acme.sh
  install -m 755 "${tmp}" "${ACME_SH}"

  if [[ -n ${email} ]]; then
    "${ACME_SH}" --register-account -m "${email}" --server letsencrypt > /dev/null 2>&1 || true
  fi
  if ! crontab -l 2> /dev/null | grep -q 'acme.sh --cron'; then
    (
      crontab -l 2> /dev/null || true
      printf '0 3 * * * "%s" --cron --home "/root/.acme.sh" >/dev/null 2>&1\n' "${ACME_SH}"
    ) | crontab - 2> /dev/null || sbqd_warn "$(sbqd_t '写入 acme.sh 续期 cron 失败' 'failed to install acme.sh renewal cron')"
  fi
  return 0
}

# 运行期依赖检查（不安装，仅报告）
deps_check() {
  local ok=0 cmd
  for cmd in curl jq openssl tar python3; do
    if sbqd_has_cmd "${cmd}"; then
      sbqd_ok "$(printf '%-12s %s' "${cmd}" "$(command -v "${cmd}")")"
    else
      sbqd_err "$(printf '%-12s %s' "${cmd}" "$(sbqd_t '缺失' 'missing')")"
      ok=1
    fi
  done
  for cmd in qrencode socat flock ss; do
    if sbqd_has_cmd "${cmd}"; then
      sbqd_ok "$(printf '%-12s %s' "${cmd}" "$(command -v "${cmd}")")"
    else
      sbqd_warn "$(printf '%-12s %s' "${cmd}" "$(sbqd_t '缺失（可选）' 'missing (optional)')")"
    fi
  done
  return "${ok}"
}

# 下载文件，带镜像回退
# 用法：deps_download <url> <output> [sha256]
deps_download() {
  local url=$1 output=$2 sha=${3:-} mirror
  local -a candidates=("${url}")
  case ${url} in
    https://github.com/*)
      candidates+=(
        "https://ghproxy.net/${url}"
        "https://gh-proxy.com/${url}"
        "https://ghfast.top/${url}"
      )
      ;;
  esac

  for mirror in "${candidates[@]}"; do
    if curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 600 \
      -o "${output}" "${mirror}" 2> /dev/null; then
      if [[ -n ${sha} ]]; then
        if printf '%s  %s\n' "${sha}" "${output}" | sha256sum -c - > /dev/null 2>&1; then
          return 0
        fi
        sbqd_warn "$(sbqd_t '校验失败，尝试下一个下载源' 'checksum mismatch, trying next mirror')"
        continue
      fi
      return 0
    fi
  done
  return 1
}
