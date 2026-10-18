# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034
# =============================================================================
#  detect.sh · 环境探测层
#  职责：发行版、架构、包管理器、init、容器、公网/内网地址
# =============================================================================

detect_os() {
  if [[ ! -r /etc/os-release ]]; then
    sbqd_die "$(sbqd_t '无法读取 /etc/os-release，不支持的系统' 'cannot read /etc/os-release, unsupported system')"
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  SBQD_OS_ID=${ID:-unknown}
  SBQD_OS_VERSION=${VERSION_ID:-}
  SBQD_OS_PRETTY=${PRETTY_NAME:-${NAME:-${SBQD_OS_ID}}}
  SBQD_OS_FAMILY='unknown'

  case " ${ID:-} ${ID_LIKE:-} " in
    *debian* | *ubuntu*) SBQD_OS_FAMILY='debian' ;;
    *rhel* | *fedora* | *centos* | *rocky* | *almalinux* | *ol*) SBQD_OS_FAMILY='rhel' ;;
    *alpine*) SBQD_OS_FAMILY='alpine' ;;
  esac

  if sbqd_has_cmd apt-get; then
    SBQD_PKG_MGR='apt'
  elif sbqd_has_cmd dnf; then
    SBQD_PKG_MGR='dnf'
  elif sbqd_has_cmd yum; then
    SBQD_PKG_MGR='yum'
  elif sbqd_has_cmd apk; then
    SBQD_PKG_MGR='apk'
  else
    SBQD_PKG_MGR=''
  fi

  if [[ ${SBQD_OS_FAMILY} == 'unknown' ]]; then
    sbqd_warn "$(sbqd_t '未识别的发行版 %s，将尝试通用流程' \
      'unrecognized distribution %s, trying the generic path' "${SBQD_OS_PRETTY}")"
  fi
}

detect_arch() {
  local machine
  machine=$(uname -m)
  case ${machine} in
    x86_64 | amd64) SBQD_ARCH='amd64' ;;
    aarch64 | arm64) SBQD_ARCH='arm64' ;;
    armv7l | armv7) SBQD_ARCH='armv7' ;;
    armv6l) SBQD_ARCH='armv6' ;;
    i386 | i686) SBQD_ARCH='386' ;;
    *)
      SBQD_ARCH=''
      sbqd_die "$(sbqd_t '不支持的 CPU 架构：%s' 'unsupported CPU architecture: %s' "${machine}")"
      ;;
  esac
}

detect_init() {
  if [[ -d /run/systemd/system ]] && sbqd_has_cmd systemctl; then
    SBQD_INIT='systemd'
  else
    SBQD_INIT='other'
  fi
}

detect_container() {
  if [[ -f /.dockerenv ]]; then
    SBQD_CONTAINER='docker'
  elif [[ -f /run/.containerenv ]]; then
    SBQD_CONTAINER='podman'
  elif grep -qaE '(docker|lxc|kubepods)' /proc/1/cgroup 2> /dev/null; then
    SBQD_CONTAINER='container'
  else
    SBQD_CONTAINER=''
  fi
}

detect_all() {
  detect_os
  detect_arch
  detect_init
  detect_container
}

# --- 地址探测 ---------------------------------------------------------------
detect_public_ipv4() {
  local url ip
  for url in 'https://api.ipify.org' 'https://ifconfig.me/ip' 'https://ip.sb'; do
    ip=$(curl -4 -fsS --max-time 6 "${url}" 2> /dev/null) || continue
    sbqd_trim "${ip}"
    ip=${REPLY}
    if sbqd_is_ipv4 "${ip}"; then
      printf '%s' "${ip}"
      return 0
    fi
  done
  return 1
}

detect_public_ipv6() {
  local url ip
  for url in 'https://api6.ipify.org' 'https://ifconfig.co/ip' 'https://ip.sb'; do
    ip=$(curl -6 -fsS --max-time 6 "${url}" 2> /dev/null) || continue
    sbqd_trim "${ip}"
    ip=${REPLY}
    if sbqd_is_ipv6 "${ip}"; then
      printf '%s' "${ip}"
      return 0
    fi
  done
  return 1
}

detect_local_ipv4() {
  local ip
  ip=$(ip -4 route get 1.1.1.1 2> /dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')
  if sbqd_is_ipv4 "${ip}"; then
    printf '%s' "${ip}"
    return 0
  fi
  return 1
}

# 对外通告地址：优先公网 IPv4，其次本地 IPv4
detect_primary_ipv4() {
  local ip
  ip=$(detect_public_ipv4) || ip=$(detect_local_ipv4) || ip=''
  printf '%s' "${ip}"
}

detect_hostname() {
  hostname -f 2> /dev/null || hostname 2> /dev/null || printf 'localhost'
}

detect_summary() {
  printf '%s | %s | %s | %s' \
    "${SBQD_OS_PRETTY}" "${SBQD_ARCH}" "${SBQD_PKG_MGR:-none}" "${SBQD_INIT}"
}
