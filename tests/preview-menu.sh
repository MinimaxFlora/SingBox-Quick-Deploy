#!/usr/bin/env bash
# 开发用：预览 geto 风格主菜单（输入 0 退出）
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

export SBQD_ETC="${PWD}/tests/tmp/menu/etc"
export SBQD_STATE_FILE="${SBQD_ETC}/state.json"
export SBQD_LOG_FILE="${PWD}/tests/tmp/menu/sbqd.log"
export SINGBOX_BIN="${HOME}/.cache/sbqd/sing-box-1.14.3-linux-amd64/sing-box"
export SINGBOX_CERT_DIR="${PWD}/tests/tmp/menu/cert"

rm -rf -- tests/tmp/menu
mkdir -p -- tests/tmp/menu

# shellcheck source=../src/lib/core.sh
. src/lib/core.sh
# shellcheck source=../src/lib/ui.sh
. src/lib/ui.sh
# shellcheck source=../src/lib/detect.sh
. src/lib/detect.sh
# shellcheck source=../src/lib/deps.sh
. src/lib/deps.sh
# shellcheck source=../src/lib/state.sh
. src/lib/state.sh
# shellcheck source=../src/lib/kernel.sh
. src/lib/kernel.sh
# shellcheck source=../src/lib/service.sh
. src/lib/service.sh
# shellcheck source=../src/lib/cert.sh
. src/lib/cert.sh
# shellcheck source=../src/lib/config.sh
. src/lib/config.sh
# shellcheck source=../src/lib/nodes.sh
. src/lib/nodes.sh
# shellcheck source=../src/lib/relay.sh
. src/lib/relay.sh
# shellcheck source=../src/lib/share.sh
. src/lib/share.sh
# shellcheck source=../src/lib/subserver.sh
. src/lib/subserver.sh
# shellcheck source=../src/lib/firewall.sh
. src/lib/firewall.sh
# shellcheck source=../src/lib/backup.sh
. src/lib/backup.sh
# shellcheck source=../src/lib/installer.sh
. src/lib/installer.sh
# shellcheck source=../src/lib/menu.sh
. src/lib/menu.sh

sbqd_init
ui_init
detect_all

# 无状态时的菜单头
printf '0\n' | sbqd_menu_main
