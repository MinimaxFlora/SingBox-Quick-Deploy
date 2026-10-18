# shellcheck shell=bash
# shellcheck disable=SC2154
# =============================================================================
#  ui.sh · 终端界面层
#  职责：颜色/宽度、横幅、状态栏、菜单、表格、进度动画
#  设计：纯 printf 实现，无外部依赖；非 UTF-8 环境自动降级为 ASCII 边框
# =============================================================================

SBQD_UI_W=${SBQD_UI_W:-0}
SBQD_BOX_TL=''
SBQD_BOX_TR=''
SBQD_BOX_BL=''
SBQD_BOX_BR=''
SBQD_BOX_H=''
SBQD_BOX_V=''
SBQD_BOX_ML=''
SBQD_BOX_MR=''
SBQD_SPIN_PID=''

ui_init() {
  if ((SBQD_UTF8)); then
    SBQD_BOX_TL='╭'
    SBQD_BOX_TR='╮'
    SBQD_BOX_BL='╰'
    SBQD_BOX_BR='╯'
    SBQD_BOX_H='─'
    SBQD_BOX_V='│'
    SBQD_BOX_ML='├'
    SBQD_BOX_MR='┤'
  else
    SBQD_BOX_TL='+'
    SBQD_BOX_TR='+'
    SBQD_BOX_BL='+'
    SBQD_BOX_BR='+'
    SBQD_BOX_H='-'
    SBQD_BOX_V='|'
    SBQD_BOX_ML='+'
    SBQD_BOX_MR='+'
  fi

  if ((SBQD_UI_W == 0)); then
    if [[ -t 1 ]] && sbqd_has_cmd tput; then
      SBQD_UI_W=$(tput cols 2> /dev/null || printf '76')
    else
      SBQD_UI_W=76
    fi
  fi
  [[ ${SBQD_UI_W} =~ ^[0-9]+$ ]] || SBQD_UI_W=76
  if ((SBQD_UI_W < 58)); then SBQD_UI_W=58; fi
  if ((SBQD_UI_W > 96)); then SBQD_UI_W=96; fi
}

# 显示宽度：CJK 按 2 列估算；UTF-8 下 (字节数 + 字符数)/2 对 CJK+ASCII 精确
ui_width() {
  local s=$1 chars bytes set_lc_all=0 old_lc_all=''
  chars=${#s}
  if [[ -n ${LC_ALL+x} ]]; then
    set_lc_all=1
    old_lc_all=${LC_ALL}
  fi
  LC_ALL=C
  bytes=${#s}
  if ((set_lc_all)); then
    LC_ALL=${old_lc_all}
  else
    unset LC_ALL
  fi
  printf '%s' $(((bytes + chars) / 2))
}

ui_pad() {
  local s=$1 want=$2 w
  w=$(ui_width "${s}")
  printf '%s' "${s}"
  if ((w < want)); then
    printf '%*s' $((want - w)) ''
  fi
}

ui_repeat() {
  local ch=$1 n=$2 out=''
  while ((n > 0)); do
    out+="${ch}"
    n=$((n - 1))
  done
  printf '%s' "${out}"
}

ui_clear() {
  [[ -t 1 ]] || return 0
  printf '\033[H\033[2J'
}

ui_hr() {
  local ch=${1:-${SBQD_BOX_H}}
  printf '  %s%s%s\n' "${SBQD_C_DIM}" "$(ui_repeat "${ch}" $((SBQD_UI_W - 2)))" "${SBQD_C_RESET}"
}

# --- 盒子 -------------------------------------------------------------------
ui_box_top() {
  local title=${1:-} inner left right
  inner=$((SBQD_UI_W - 4))
  printf '\n  %s%s%s%s%s\n' "${SBQD_C_DIM}" "${SBQD_BOX_TL}" \
    "$(ui_repeat "${SBQD_BOX_H}" $((SBQD_UI_W - 2)))" "${SBQD_BOX_TR}" "${SBQD_C_RESET}"
  if [[ -n ${title} ]]; then
    left=$(((inner - $(ui_width "${title}")) / 2))
    if ((left < 0)); then left=0; fi
    right=$((inner - left - $(ui_width "${title}")))
    if ((right < 0)); then right=0; fi
    printf '  %s%s%s %s%s%s%s%s%s%s%s\n' \
      "${SBQD_C_DIM}" "${SBQD_BOX_V}" "${SBQD_C_RESET}" \
      "$(ui_repeat ' ' "${left}")" "${SBQD_C_ACCENT}${SBQD_C_BOLD}" "${title}" "${SBQD_C_RESET}" \
      "$(ui_repeat ' ' "${right}")" "${SBQD_C_DIM}" "${SBQD_BOX_V}" "${SBQD_C_RESET}"
    printf '  %s%s%s%s%s\n' "${SBQD_C_DIM}" "${SBQD_BOX_ML}" \
      "$(ui_repeat "${SBQD_BOX_H}" $((SBQD_UI_W - 2)))" "${SBQD_BOX_MR}" "${SBQD_C_RESET}"
  fi
}

ui_box_line() {
  local text=$1 color=${2:-} inner padded
  inner=$((SBQD_UI_W - 4))
  padded=$(ui_pad "${text}" "${inner}")
  printf '  %s%s%s %s%s%s %s%s%s\n' \
    "${SBQD_C_DIM}" "${SBQD_BOX_V}" "${SBQD_C_RESET}" \
    "${color}" "${padded}" "${SBQD_C_RESET}" \
    "${SBQD_C_DIM}" "${SBQD_BOX_V}" "${SBQD_C_RESET}"
}

ui_box_center() {
  local text=$1 color=${2:-} inner left right padded
  inner=$((SBQD_UI_W - 4))
  left=$(((inner - $(ui_width "${text}")) / 2))
  if ((left < 0)); then left=0; fi
  right=$((inner - left - $(ui_width "${text}")))
  if ((right < 0)); then right=0; fi
  padded="$(ui_repeat ' ' "${left}")${text}$(ui_repeat ' ' "${right}")"
  ui_box_line "${padded}" "${color}"
}

ui_box_sep() {
  printf '  %s%s%s%s%s\n' "${SBQD_C_DIM}" "${SBQD_BOX_ML}" \
    "$(ui_repeat "${SBQD_BOX_H}" $((SBQD_UI_W - 2)))" "${SBQD_BOX_MR}" "${SBQD_C_RESET}"
}

ui_box_bottom() {
  printf '  %s%s%s%s%s\n' "${SBQD_C_DIM}" "${SBQD_BOX_BL}" \
    "$(ui_repeat "${SBQD_BOX_H}" $((SBQD_UI_W - 2)))" "${SBQD_BOX_BR}" "${SBQD_C_RESET}"
}

# --- 横幅 -------------------------------------------------------------------
# Logo 由等宽方块字符组成（固定 33 列），不能用 CJK 宽度公式估算，单独处理
ui_logo_line() {
  local text=$1 color=${2:-} inner left right line
  inner=$((SBQD_UI_W - 4))
  left=$(((inner - 33) / 2))
  if ((left < 0)); then left=0; fi
  right=$((inner - left - 33))
  if ((right < 0)); then right=0; fi
  line="$(ui_repeat ' ' "${left}")${text}$(ui_repeat ' ' "${right}")"
  printf '  %s%s%s %s%s%s %s%s%s\n' \
    "${SBQD_C_DIM}" "${SBQD_BOX_V}" "${SBQD_C_RESET}" \
    "${color}" "${line}" "${SBQD_C_RESET}" \
    "${SBQD_C_DIM}" "${SBQD_BOX_V}" "${SBQD_C_RESET}"
}

ui_banner() {
  local tagline
  ui_box_top ''
  ui_box_line '' ''

  if ((SBQD_UTF8)); then
    ui_logo_line '███████╗██████╗  ██████╗ ██████╗ ' "${SBQD_C_PRIMARY}"
    ui_logo_line '██╔════╝██╔══██╗██╔═══██╗██╔══██╗' "${SBQD_C_CYAN}"
    ui_logo_line '███████╗██████╔╝██║   ██║██║  ██║' "${SBQD_C_BLUE}"
    ui_logo_line '╚════██║██╔══██╗██║   ██║██║  ██║' "${SBQD_C_MAGENTA}"
    ui_logo_line '███████║██████╔╝╚██████╔╝██████╔╝' "${SBQD_C_MAGENTA}"
    ui_logo_line '╚══════╝╚═════╝  ╚═════╝ ╚═════╝ ' "${SBQD_C_MAGENTA}"
  else
    ui_box_center 'S B Q D' "${SBQD_C_PRIMARY}"
    ui_box_center 'SingBox Quick Deploy' "${SBQD_C_CYAN}"
  fi

  tagline=$(sbqd_t 'sing-box 一键部署 · 多协议 · 中转 · 订阅' \
    'sing-box one-click deploy · multi-protocol · relay · subscription')
  ui_box_line '' ''
  ui_box_center "v${SBQD_VERSION}   ${tagline}" "${SBQD_C_DIM}"
  ui_box_bottom
}

# --- 分区与菜单项 -----------------------------------------------------------
ui_section() {
  local title=$1
  printf '\n  %s▌%s %s%s%s\n' "${SBQD_C_PRIMARY}" "${SBQD_C_RESET}" \
    "${SBQD_C_BOLD}" "${title}" "${SBQD_C_RESET}"
}

ui_item() {
  local num=$1 label=$2 hint=${3:-} pad=26
  printf '   %s%s%-2s%s  %s' "${SBQD_C_ACCENT}" "${SBQD_C_BOLD}" "${num}" "${SBQD_C_RESET}" \
    "$(ui_pad "${label}" "${pad}")"
  if [[ -n ${hint} ]]; then
    printf ' %s%s%s' "${SBQD_C_DIM}" "${hint}" "${SBQD_C_RESET}"
  fi
  printf '\n'
}

ui_ask() {
  local zh=${1:-'请选择'} en=${2:-'Select'} prompt
  prompt=$(sbqd_t "${zh}" "${en}")
  printf '\n   %s%s%s %s›%s ' "${SBQD_C_DIM}" "${prompt}" "${SBQD_C_RESET}" \
    "${SBQD_C_PRIMARY}" "${SBQD_C_RESET}" >&2
  if ! IFS= read -r REPLY; then
    printf '\n' >&2
    exit 0
  fi
}

ui_pause() {
  printf '\n   %s%s%s ' "${SBQD_C_DIM}" \
    "$(sbqd_t '按回车返回…' 'Press Enter to return…')" "${SBQD_C_RESET}" >&2
  IFS= read -r _ || true
}

# --- 表格 -------------------------------------------------------------------
# 用法：ui_table "ID|类型|名称|端口" "1|vless-reality|HK|28443" ...
ui_table() {
  local header=$1
  shift
  local -a hs cells widths
  local i n row w
  IFS='|' read -r -a hs <<< "${header}"
  n=${#hs[@]}
  for ((i = 0; i < n; i++)); do
    widths[i]=$(ui_width "${hs[i]}")
  done
  for row in "$@"; do
    IFS='|' read -r -a cells <<< "${row}"
    for ((i = 0; i < n; i++)); do
      w=$(ui_width "${cells[i]:-}")
      if ((w > widths[i])); then
        widths[i]=${w}
      fi
    done
  done

  for ((i = 0; i < n; i++)); do
    printf '  %s%s%s  ' "${SBQD_C_DIM}" "$(ui_pad "${hs[i]}" "${widths[i]}")" "${SBQD_C_RESET}"
  done
  printf '\n  %s%s%s\n' "${SBQD_C_DIM}" \
    "$(ui_repeat '─' $((SBQD_UI_W - 2)))" "${SBQD_C_RESET}"

  for row in "$@"; do
    IFS='|' read -r -a cells <<< "${row}"
    for ((i = 0; i < n; i++)); do
      printf '  %s  ' "$(ui_pad "${cells[i]:-}" "${widths[i]}")"
    done
    printf '\n'
  done
}

# --- 键值对 -----------------------------------------------------------------
ui_kv() {
  local key=$1 value=$2 color=${3:-}
  printf '   %s%s%s  %s%s%s\n' "${SBQD_C_DIM}" "$(ui_pad "${key}" 16)" "${SBQD_C_RESET}" \
    "${color}" "${value}" "${SBQD_C_RESET}"
}

# --- 进度动画 ---------------------------------------------------------------
ui_spinner_start() {
  local msg=$1
  [[ -t 2 ]] || return 0
  (
    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 len
    ((SBQD_UTF8)) || frames='-\|/'
    len=${#frames}
    while :; do
      printf '\r   %s%s%s %s' "${SBQD_C_PRIMARY}" \
        "${frames:i%len:1}" "${SBQD_C_RESET}" "${msg}" >&2
      i=$((i + 1))
      sleep 0.1
    done
  ) &
  SBQD_SPIN_PID=$!
  disown 2> /dev/null || true
}

ui_spinner_stop() {
  [[ -n ${SBQD_SPIN_PID} ]] || return 0
  kill "${SBQD_SPIN_PID}" 2> /dev/null || true
  wait "${SBQD_SPIN_PID}" 2> /dev/null || true
  printf '\r\033[K' >&2
  SBQD_SPIN_PID=''
}

# --- 状态徽章 ---------------------------------------------------------------
ui_badge() {
  local text=$1 color=${2:-${SBQD_C_GREEN}}
  printf '%s[%s]%s' "${color}" "${text}" "${SBQD_C_RESET}"
}
