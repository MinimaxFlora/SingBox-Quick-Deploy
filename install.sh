#!/usr/bin/env bash
# =============================================================================
#  install.sh · 一键安装引导
#  用法：curl -fsSL https://raw.githubusercontent.com/MinimaxFlora/SingBox-Quick-Deploy/main/install.sh | bash
# =============================================================================
set -Eeuo pipefail

REPO='MinimaxFlora/SingBox-Quick-Deploy'
PREFIX=${PREFIX:-/usr/local/bin}
TARGET="${PREFIX}/sbqd"
SBQD_ARGS=()

die() {
  printf '\033[31m[FAIL]\033[0m %s\n' "$*" >&2
  exit 1
}

info() {
  printf '\033[36m[INFO]\033[0m %s\n' "$*"
}

while (($#)); do
  case $1 in
    --version)
      printf '%s\n' "${2:-latest}"
      exit 0
      ;;
    --prefix)
      PREFIX=${2:-/usr/local/bin}
      TARGET="${PREFIX}/sbqd"
      shift 2
      ;;
    --uninstall)
      if [[ -x ${TARGET} ]]; then
        exec "${TARGET}" uninstall "${@:2}"
      fi
      die 'sbqd is not installed'
      ;;
    *)
      SBQD_ARGS+=("$1")
      shift
      ;;
  esac
done

((EUID == 0)) || die '请使用 root 运行 / please run as root'

mkdir -p -- "${PREFIX}"

script_dir=''
if [[ -n ${BASH_SOURCE[0]:-} && ${BASH_SOURCE[0]} != /dev/fd/* ]]; then
  if script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2> /dev/null && pwd); then
    :
  else
    script_dir=''
  fi
fi

cleanup_paths=()
cleanup() {
  local path
  if ((${#cleanup_paths[@]})); then
    for path in "${cleanup_paths[@]}"; do
      if [[ -e ${path} ]]; then
        rm -rf -- "${path}"
      fi
    done
  fi
}
trap cleanup EXIT

tmp=''
if [[ -n ${script_dir} && -f ${script_dir}/src/main.sh ]]; then
  info '检测到源码目录，本地构建单文件版本 / building locally'
  bash "${script_dir}/build/build.sh" > /dev/null || die '构建失败 / build failed'
  tmp="${script_dir}/dist/sbqd.sh"
else
  tmp=$(mktemp /tmp/sbqd.XXXXXX)
  cleanup_paths+=("${tmp}")
  url="https://github.com/${REPO}/releases/latest/download/sbqd.sh"
  info '下载最新版本 / downloading latest release'
  if ! curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 -o "${tmp}" "${url}"; then
    info 'GitHub 直连失败，尝试镜像 / retrying with mirror'
    if ! curl -fL --retry 3 --connect-timeout 10 -o "${tmp}" "https://ghproxy.net/${url}"; then
      info '回退到源码构建 / falling back to source build'
      src_tgz=$(mktemp /tmp/sbqd-src.XXXXXX.tgz)
      src_dir=$(mktemp -d /tmp/sbqd-src.XXXXXX)
      cleanup_paths+=("${src_tgz}" "${src_dir}")
      src_url="https://github.com/${REPO}/archive/refs/heads/main.tar.gz"
      if ! curl -fL --retry 3 --connect-timeout 15 -o "${src_tgz}" "${src_url}"; then
        curl -fL --retry 3 --connect-timeout 15 -o "${src_tgz}" "https://ghproxy.net/${src_url}" ||
          die '下载失败，请检查网络或手动安装 / download failed'
      fi
      tar -xzf "${src_tgz}" -C "${src_dir}" || die '解压源码失败 / failed to extract source'
      repo_root=$(find "${src_dir}" -maxdepth 1 -type d -name '*SingBox-Quick-Deploy*' | head -n 1)
      [[ -n ${repo_root} ]] || die '源码目录结构异常 / unexpected source layout'
      bash "${repo_root}/build/build.sh" > /dev/null || die '构建失败 / build failed'
      tmp="${repo_root}/dist/sbqd.sh"
    fi
  fi
fi

bash -n "${tmp}" || die '脚本语法校验失败 / syntax check failed'
info '安装到 / installing to '"${TARGET}"
install -m 755 "${tmp}" "${TARGET}"

if ((${#SBQD_ARGS[@]})); then
  exec "${TARGET}" install "${SBQD_ARGS[@]}"
fi
exec "${TARGET}" install
