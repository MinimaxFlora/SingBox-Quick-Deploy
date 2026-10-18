#!/usr/bin/env bash
# root 集成测试：ensure_base + 自签节点（用桩 systemctl，不写真实 systemd）
# CI 以非 root 运行时自动跳过
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

if ((EUID != 0)); then
  printf 'SKIP: requires root (run with sudo)\n'
  exit 0
fi

ROOT="${PWD}/tests/tmp/install-mock"
rm -rf -- "${ROOT}"
mkdir -p -- "${ROOT}/bin" "${ROOT}/etc" "${ROOT}/cert" "${ROOT}/singbox" "${ROOT}/state" "${ROOT}/sub" "${ROOT}/lib"
# 让 detect_init 认为 systemd 可用（实际命令由桩替换）
mkdir -p /run/systemd/system

cat > "${ROOT}/bin/systemctl" << 'EOF'
#!/usr/bin/env bash
case "$1" in
  is-active) exit 0 ;;
  is-enabled) exit 0 ;;
  show) printf '4242\n' ;;
  status) exit 0 ;;
  cat) exit 0 ;;
  *) exit 0 ;;
esac
EOF
cat > "${ROOT}/bin/journalctl" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "${ROOT}/bin/qrencode" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "${ROOT}/bin/socat" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "${ROOT}/bin/crontab" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${ROOT}/bin/"*
export PATH="${ROOT}/bin:${PATH}"

export SBQD_ETC="${ROOT}/etc"
export SBQD_STATE_FILE="${SBQD_ETC}/state.json"
export SBQD_SUB_DIR="${ROOT}/sub"
export SBQD_LOG_FILE="${ROOT}/sbqd.log"
export SBQD_LIB_DIR="${ROOT}/lib"
export SBQD_BIN_DIR="${ROOT}/bin"
export SBQD_RUN_DIR="${ROOT}/run"
export SINGBOX_CONFIG_DIR="${ROOT}/singbox"
export SINGBOX_CONFIG_FILE="${SINGBOX_CONFIG_DIR}/config.json"
export SINGBOX_CERT_DIR="${ROOT}/cert"
export SINGBOX_STATE_DIR="${ROOT}/state"
export SINGBOX_UNIT_FILE="${ROOT}/sing-box.service"
export SINGBOX_BIN="${ROOT}/bin/sing-box"
export SINGBOX_USER='root'
export SBQD_SUB_USER='root'
export ACME_SH='/bin/true'

cp "${SBQD_TEST_SINGBOX:-${HOME}/.cache/sbqd/sing-box-1.14.3-linux-amd64/sing-box}" "${SINGBOX_BIN}"
chmod 755 "${SINGBOX_BIN}"

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

sbqd_init
ui_init
detect_all

printf '=== ensure_base ===\n'
sbqd_ensure_base
[[ -f ${SBQD_STATE_FILE} ]]
[[ -f ${SINGBOX_CONFIG_FILE} ]]
[[ -f ${SINGBOX_UNIT_FILE} ]]
grep -q 'Managed by SingBox-Quick-Deploy' "${SINGBOX_UNIT_FILE}"
"${SINGBOX_BIN}" check -c "${SINGBOX_CONFIG_FILE}"
printf 'base_ok\n'

printf '=== self-signed node ===\n'
nodes_create 'hysteria2' 'hy2' '28444' '' 0 '203.0.113.10' 'selfsigned' > /dev/null
nodes_create 'vless-reality' 'reality' '28443' '' 0 '203.0.113.10' 'reality' > /dev/null

[[ $(jq '.nodes | length' "${SBQD_STATE_FILE}") -eq 2 ]]
[[ $(jq -r '.nodes[0].tls_mode' "${SBQD_STATE_FILE}") == 'selfsigned' ]]
[[ -s $(cert_selfsigned_fullchain '203.0.113.10') ]]
"${SINGBOX_BIN}" check -c "${SINGBOX_CONFIG_FILE}"
[[ $(jq '.inbounds | length' "${SINGBOX_CONFIG_FILE}") -eq 2 ]]
printf 'nodes_ok\n'

printf '=== share ===\n'
hy2_uri=$(share_node_uri "$(state_node_json 1)")
[[ ${hy2_uri} == *'insecure=1'* ]]
[[ ${hy2_uri} == *'pinSHA256='* ]]
reality_uri=$(share_node_uri "$(state_node_json 2)")
[[ ${reality_uri} == vless://*'security=reality'* ]]
nodes_list
printf 'share_ok\n'

printf 'ALL_OK\n'
