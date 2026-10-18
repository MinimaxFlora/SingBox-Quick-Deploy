# shellcheck shell=bash
# shellcheck disable=SC2034
# =============================================================================
#  core.sh · 基础层
#  职责：常量、路径、日志、错误处理、交互输入、通用校验与工具函数
#  约定：全局变量以 SBQD_ 开头；函数以 sbqd_ 开头；所有日志写 stderr
# =============================================================================

# --- 版本与项目信息 ----------------------------------------------------------
SBQD_VERSION=${SBQD_VERSION:-0.1.0}
SBQD_NAME='SingBox-Quick-Deploy'
SBQD_REPO='MinimaxFlora/SingBox-Quick-Deploy'
SBQD_HOME_URL="https://github.com/${SBQD_REPO}"

# --- 路径（均可通过环境变量覆盖，便于测试） ---------------------------------
SBQD_ETC=${SBQD_ETC:-/etc/sbqd}
SBQD_STATE_FILE=${SBQD_STATE_FILE:-${SBQD_ETC}/state.json}
SBQD_SUB_DIR=${SBQD_SUB_DIR:-${SBQD_ETC}/sub}
SBQD_LOG_FILE=${SBQD_LOG_FILE:-/var/log/sbqd/sbqd.log}
SBQD_LIB_DIR=${SBQD_LIB_DIR:-/usr/local/lib/sbqd}
SBQD_BIN_DIR=${SBQD_BIN_DIR:-/usr/local/bin}
SBQD_RUN_DIR=${SBQD_RUN_DIR:-/run/sbqd}

SINGBOX_CONFIG_DIR=${SINGBOX_CONFIG_DIR:-/etc/sing-box}
SINGBOX_CONFIG_FILE=${SINGBOX_CONFIG_FILE:-${SINGBOX_CONFIG_DIR}/config.json}
SINGBOX_CERT_DIR=${SINGBOX_CERT_DIR:-${SINGBOX_CONFIG_DIR}/cert}
SINGBOX_BIN=${SINGBOX_BIN:-/usr/local/bin/sing-box}
SINGBOX_STATE_DIR=${SINGBOX_STATE_DIR:-/var/lib/sing-box}
SINGBOX_UNIT_FILE=${SINGBOX_UNIT_FILE:-/etc/systemd/system/sing-box.service}
SINGBOX_USER=${SINGBOX_USER:-sing-box}
SBQD_SUB_USER=${SBQD_SUB_USER:-sbqd-sub}

ACME_SH=${ACME_SH:-/root/.acme.sh/acme.sh}

# 默认随机高端口区间（用户选择：全部随机高端口）
SBQD_PORT_MIN=${SBQD_PORT_MIN:-20000}
SBQD_PORT_MAX=${SBQD_PORT_MAX:-60000}

# 订阅服务、Clash API 固定回环
SBQD_API_LISTEN=${SBQD_API_LISTEN:-127.0.0.1}

# --- 运行期状态 -------------------------------------------------------------
SBQD_LANG=${SBQD_LANG:-zh}
SBQD_LOG_LEVEL=${SBQD_LOG_LEVEL:-info}
SBQD_LOG_LEVEL_NUM=1
SBQD_TMP=''
SBQD_LOCKED=0
SBQD_TTY=0
SBQD_UTF8=0
SBQD_OS_ID=''
SBQD_OS_PRETTY=''
SBQD_OS_FAMILY=''
SBQD_ARCH=''
SBQD_PKG_MGR=''
SBQD_INIT=''

# --- 颜色（仅终端启用；NO_COLOR 遵循 no-color.org 约定） --------------------
SBQD_C_RESET=''
SBQD_C_BOLD=''
SBQD_C_DIM=''
SBQD_C_RED=''
SBQD_C_GREEN=''
SBQD_C_YELLOW=''
SBQD_C_BLUE=''
SBQD_C_MAGENTA=''
SBQD_C_CYAN=''
SBQD_C_PRIMARY=''
SBQD_C_ACCENT=''
SBQD_C_WHITE=''

sbqd_colors_init() {
  if [[ -n ${NO_COLOR:-} || ${TERM:-dumb} == dumb ]]; then
    return 0
  fi
  if [[ ! -t 1 && ! -t 2 ]]; then
    return 0
  fi
  SBQD_C_RESET=$'\033[0m'
  SBQD_C_BOLD=$'\033[1m'
  SBQD_C_DIM=$'\033[38;5;244m'
  SBQD_C_RED=$'\033[38;5;203m'
  SBQD_C_GREEN=$'\033[38;5;114m'
  SBQD_C_YELLOW=$'\033[38;5;221m'
  SBQD_C_BLUE=$'\033[38;5;75m'
  SBQD_C_MAGENTA=$'\033[38;5;177m'
  SBQD_C_CYAN=$'\033[38;5;80m'
  SBQD_C_PRIMARY=$'\033[38;5;45m'
  SBQD_C_ACCENT=$'\033[38;5;215m'
  SBQD_C_WHITE=$'\033[38;5;255m'
}

# --- 双语字符串 -------------------------------------------------------------
# 用法：sbqd_t '中文 %s' 'English %s' "$arg"（% 占位符按 printf 规则）
sbqd_t() {
  local zh=$1 en=$2
  shift 2
  if [[ ${SBQD_LANG} == en ]]; then
    # shellcheck disable=SC2059
    printf -- "$en" "$@"
  else
    # shellcheck disable=SC2059
    printf -- "$zh" "$@"
  fi
}

# --- 日志 -------------------------------------------------------------------
sbqd_log_file() {
  local level=$1 msg=$2 dir
  [[ -n ${SBQD_LOG_FILE} ]] || return 0
  dir=${SBQD_LOG_FILE%/*}
  [[ -d ${dir} && -w ${dir} ]] || return 0
  printf '%s [%s] %s\n' "$(date '+%F %T')" "${level}" "${msg}" \
    >> "${SBQD_LOG_FILE}" 2> /dev/null || true
}

sbqd_log() {
  local level=$1 msg=$2 color label
  case ${level} in
    debug)
      if ((SBQD_LOG_LEVEL_NUM > 0)); then
        return 0
      fi
      label='DBG '
      color=${SBQD_C_DIM}
      ;;
    info)
      label='INFO'
      color=${SBQD_C_CYAN}
      ;;
    ok)
      label=' OK '
      color=${SBQD_C_GREEN}
      ;;
    warn)
      label='WARN'
      color=${SBQD_C_YELLOW}
      ;;
    error)
      label='FAIL'
      color=${SBQD_C_RED}
      ;;
    *)
      label=${level}
      color=''
      ;;
  esac
  printf '%s[%s]%s %s\n' "${color}" "${label}" "${SBQD_C_RESET}" "${msg}" >&2
  sbqd_log_file "${level}" "${msg}"
}

sbqd_debug() { sbqd_log debug "$*"; }
sbqd_info() { sbqd_log info "$*"; }
sbqd_ok() { sbqd_log ok "$*"; }
sbqd_warn() { sbqd_log warn "$*"; }
sbqd_err() { sbqd_log error "$*"; }

sbqd_die() {
  sbqd_log error "$*"
  exit 1
}

# --- 错误与退出处理 ---------------------------------------------------------
sbqd_on_err() {
  local rc=$1 line=$2 cmd=$3
  if ((rc != 0)); then
    printf '%s[FAIL]%s %s (line %s): %s\n' \
      "${SBQD_C_RED}" "${SBQD_C_RESET}" \
      "$(sbqd_t '命令执行失败' 'command failed')" "${line}" "${cmd}" >&2
  fi
  exit "${rc}"
}

sbqd_cleanup() {
  if [[ -n ${SBQD_SPIN_PID:-} ]]; then
    kill "${SBQD_SPIN_PID}" 2> /dev/null || true
  fi
  if [[ -n ${SBQD_TMP} && -d ${SBQD_TMP} ]]; then
    rm -rf -- "${SBQD_TMP}"
  fi
}

sbqd_init() {
  umask 077

  case ${SBQD_LOG_LEVEL} in
    debug) SBQD_LOG_LEVEL_NUM=0 ;;
    info | warn | error) SBQD_LOG_LEVEL_NUM=1 ;;
    *) SBQD_LOG_LEVEL_NUM=1 ;;
  esac

  SBQD_TTY=0
  if [[ -t 1 ]]; then
    SBQD_TTY=1
  fi

  SBQD_UTF8=0
  if [[ ${SBQD_ASCII:-0} != 1 ]] && command -v locale > /dev/null 2>&1 &&
    [[ "$(locale charmap 2> /dev/null)" == 'UTF-8' ]]; then
    SBQD_UTF8=1
  fi

  sbqd_colors_init

  SBQD_TMP=$(mktemp -d "${TMPDIR:-/tmp}/sbqd.XXXXXX")
  trap 'sbqd_cleanup' EXIT
  trap 'sbqd_on_err $? $LINENO "$BASH_COMMAND"' ERR
  trap 'printf "\n" >&2; exit 130' INT
}

# --- 基础工具 ---------------------------------------------------------------
sbqd_has_cmd() { command -v "$1" > /dev/null 2>&1; }

sbqd_require_cmd() {
  local cmd=$1 hint=${2:-}
  sbqd_has_cmd "${cmd}" && return 0
  if [[ -n ${hint} ]]; then
    sbqd_die "$(sbqd_t '缺少命令 %s，请先安装：%s' 'missing command %s, install it first: %s' "${cmd}" "${hint}")"
  fi
  sbqd_die "$(sbqd_t '缺少命令 %s' 'missing command %s' "${cmd}")"
}

sbqd_require_root() {
  if ((EUID == 0)); then
    return 0
  fi
  sbqd_die "$(sbqd_t '需要 root 权限，请使用 sudo 运行' 'root privileges required, run with sudo')"
}

sbqd_trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  REPLY=${s}
}

sbqd_lower() {
  local s=$1
  REPLY=${s,,}
}

sbqd_is_tty() { [[ -t 1 ]]; }

# --- 交互输入 ---------------------------------------------------------------
sbqd_confirm() {
  local zh=$1 en=$2 def=${3:-n} hint ans
  if [[ ${def} == y ]]; then
    hint='[Y/n]'
  else
    hint='[y/N]'
  fi
  printf '  %s %s: ' "$(sbqd_t "${zh}" "${en}")" "${hint}" >&2
  if ! IFS= read -r ans; then
    ans=${def}
  fi
  if [[ -z ${ans} ]]; then
    ans=${def}
  fi
  [[ ${ans} =~ ^[Yy] ]]
}

# 读取一行输入，结果存入 REPLY；EOF 时使用默认值
sbqd_prompt() {
  local zh=$1 en=$2 def=${3:-} prompt ans
  prompt=$(sbqd_t "${zh}" "${en}")
  if [[ -n ${def} ]]; then
    printf '  %s [%s]: ' "${prompt}" "${def}" >&2
  else
    printf '  %s: ' "${prompt}" >&2
  fi
  if ! IFS= read -r ans; then
    ans=${def}
  fi
  if [[ -z ${ans} ]]; then
    ans=${def}
  fi
  REPLY=${ans}
}

# 读取敏感输入（不回显），结果存入 REPLY
sbqd_prompt_secret() {
  local zh=$1 en=$2 prompt ans
  prompt=$(sbqd_t "${zh}" "${en}")
  printf '  %s: ' "${prompt}" >&2
  if ! IFS= read -r -s ans; then
    ans=''
  fi
  printf '\n' >&2
  REPLY=${ans}
}

# --- 随机与校验 -------------------------------------------------------------
sbqd_rand_hex() {
  local n=${1:-16}
  if sbqd_has_cmd openssl; then
    openssl rand -hex "${n}"
    return 0
  fi
  od -An -N "${n}" -tx1 /dev/urandom | tr -d ' \n'
}

sbqd_rand_token() {
  local n=${1:-24}
  if sbqd_has_cmd openssl; then
    openssl rand -base64 "${n}" | tr -d '\n=' | tr '+/' '-_'
    return 0
  fi
  od -An -N "${n}" -tx1 /dev/urandom | tr -d ' \n'
}

sbqd_rand_port() {
  local lo=${1:-${SBQD_PORT_MIN}} hi=${2:-${SBQD_PORT_MAX}}
  printf '%s' $((lo + (RANDOM * 32768 + RANDOM) % (hi - lo + 1)))
}

sbqd_is_port() {
  [[ ${1:-} =~ ^[0-9]{1,5}$ ]] || return 1
  local p=$((10#${1}))
  ((p >= 1 && p <= 65535))
}

sbqd_is_ipv4() {
  [[ ${1:-} =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS=. p
  for p in ${1}; do
    ((10#${p} <= 255)) || return 1
  done
  return 0
}

sbqd_is_ipv6() {
  [[ ${1:-} == *:* ]] || return 1
  [[ ${1} =~ ^[0-9A-Fa-f:]+$ ]] || return 1
}

sbqd_is_domain() {
  [[ ${1:-} =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

sbqd_is_uuid() {
  [[ ${1:-} =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

sbqd_is_email() {
  [[ ${1:-} =~ ^[^@[:space:]]+@[^@[:space:]]+\.[A-Za-z]{2,}$ ]]
}

# --- 端口占用 ---------------------------------------------------------------
sbqd_port_in_use() {
  local port=$1 proto=${2:-tcp}
  sbqd_has_cmd ss || return 1
  if [[ ${proto} == udp ]]; then
    [[ -n "$(ss -H -lnu "sport = :${port}" 2> /dev/null)" ]]
  else
    [[ -n "$(ss -H -lnt "sport = :${port}" 2> /dev/null)" ]]
  fi
}

# --- 时间 -------------------------------------------------------------------
sbqd_iso_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

sbqd_epoch_now() { date +%s; }

# 输入 ISO 时间或日期，输出剩余天数（已过期则为负数/0）
sbqd_days_left() {
  local end start
  end=$(date -d "$1" +%s 2> /dev/null) || {
    printf '0'
    return 0
  }
  start=$(date +%s)
  printf '%s' $(((end - start) / 86400))
}

# --- 文件写入 ---------------------------------------------------------------
# 原子写入：从 stdin 读取内容，写入目标路径（权限 600）
sbqd_atomic_write() {
  local target=$1 dir tmp
  dir=${target%/*}
  [[ -d ${dir} ]] || mkdir -p -- "${dir}"
  tmp=$(mktemp "${target}.XXXXXX")
  cat > "${tmp}"
  chmod 600 "${tmp}"
  mv -f -- "${tmp}" "${target}"
}

# --- 并发锁 -----------------------------------------------------------------
sbqd_lock() {
  if [[ ${SBQD_LOCKED} == 1 ]]; then
    return 0
  fi
  mkdir -p -- "${SBQD_RUN_DIR}"
  if sbqd_has_cmd flock; then
    exec 9> "${SBQD_RUN_DIR}/sbqd.lock"
    if ! flock -n 9; then
      sbqd_die "$(sbqd_t '另一个 sbqd 实例正在运行，请稍后再试' 'another sbqd instance is running, try again later')"
    fi
  else
    if ! mkdir "${SBQD_RUN_DIR}/sbqd.lock.d" 2> /dev/null; then
      sbqd_die "$(sbqd_t '另一个 sbqd 实例正在运行，请稍后再试' 'another sbqd instance is running, try again later')"
    fi
    trap 'rmdir "${SBQD_RUN_DIR}/sbqd.lock.d" 2>/dev/null || true' EXIT
  fi
  SBQD_LOCKED=1
}

# --- 杂项 -------------------------------------------------------------------
# 把逗号/空格分隔的列表标准化为 jq 数组字面量
sbqd_csv_to_json_array() {
  local raw=$1 item out='[]'
  raw=${raw//,/ }
  for item in ${raw}; do
    out=$(jq -c --arg v "${item}" '. + [$v]' <<< "${out}")
  done
  printf '%s' "${out}"
}
