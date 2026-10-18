#!/usr/bin/env bash
# =============================================================================
#  main.sh · 源码入口（开发/仓库模式）
#  发布时由 build/build.sh 合并为单文件 dist/sbqd.sh
# =============================================================================
set -Eeuo pipefail

SBQD_SRC_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SBQD_ASSETS_DIR="${SBQD_SRC_DIR}/../assets"
SBQD_SELF=$(readlink -f -- "${BASH_SOURCE[0]}" 2> /dev/null || printf '%s' "${BASH_SOURCE[0]}")

# shellcheck source=lib/core.sh
. "${SBQD_SRC_DIR}/lib/core.sh"
# shellcheck source=lib/ui.sh
. "${SBQD_SRC_DIR}/lib/ui.sh"
# shellcheck source=lib/detect.sh
. "${SBQD_SRC_DIR}/lib/detect.sh"
# shellcheck source=lib/deps.sh
. "${SBQD_SRC_DIR}/lib/deps.sh"
# shellcheck source=lib/state.sh
. "${SBQD_SRC_DIR}/lib/state.sh"
# shellcheck source=lib/kernel.sh
. "${SBQD_SRC_DIR}/lib/kernel.sh"
# shellcheck source=lib/service.sh
. "${SBQD_SRC_DIR}/lib/service.sh"
# shellcheck source=lib/cert.sh
. "${SBQD_SRC_DIR}/lib/cert.sh"
# shellcheck source=lib/config.sh
. "${SBQD_SRC_DIR}/lib/config.sh"
# shellcheck source=lib/nodes.sh
. "${SBQD_SRC_DIR}/lib/nodes.sh"
# shellcheck source=lib/relay.sh
. "${SBQD_SRC_DIR}/lib/relay.sh"
# shellcheck source=lib/share.sh
. "${SBQD_SRC_DIR}/lib/share.sh"
# shellcheck source=lib/subserver.sh
. "${SBQD_SRC_DIR}/lib/subserver.sh"
# shellcheck source=lib/firewall.sh
. "${SBQD_SRC_DIR}/lib/firewall.sh"
# shellcheck source=lib/backup.sh
. "${SBQD_SRC_DIR}/lib/backup.sh"
# shellcheck source=lib/installer.sh
. "${SBQD_SRC_DIR}/lib/installer.sh"
# shellcheck source=lib/menu.sh
. "${SBQD_SRC_DIR}/lib/menu.sh"
# shellcheck source=lib/cmd.sh
. "${SBQD_SRC_DIR}/lib/cmd.sh"

sbqd_main "$@"
