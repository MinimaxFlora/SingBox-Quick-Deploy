#!/usr/bin/env bash
# 开发自检：IP 直连自签证书 / 链接 insecure / schema 迁移
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

SB="${SBQD_TEST_SINGBOX:-${HOME}/.cache/sbqd/sing-box-1.14.3-linux-amd64/sing-box}"
if [[ ! -x ${SB} ]]; then
  printf 'SKIP: %s not found\n' "${SB}"
  exit 0
fi

export SBQD_ETC="${PWD}/tests/tmp/selfsigned/etc"
export SBQD_STATE_FILE="${SBQD_ETC}/state.json"
export SBQD_LOG_FILE="${PWD}/tests/tmp/selfsigned/sbqd.log"
export SINGBOX_BIN="${SB}"
export SINGBOX_CERT_DIR="${PWD}/tests/tmp/selfsigned/cert"
export SINGBOX_CONFIG_DIR="${PWD}/tests/tmp/selfsigned/singbox"
export SINGBOX_CONFIG_FILE="${SINGBOX_CONFIG_DIR}/config.json"
export SINGBOX_USER
SINGBOX_USER=$(id -un)

rm -rf -- tests/tmp/selfsigned
mkdir -p -- tests/tmp/selfsigned

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
# shellcheck source=../src/lib/cert.sh
. src/lib/cert.sh
# shellcheck source=../src/lib/config.sh
. src/lib/config.sh
# shellcheck source=../src/lib/share.sh
. src/lib/share.sh

sbqd_init
state_init
state_update '.settings.public_ipv4 = "203.0.113.10"'

printf '=== self-signed certificate ===\n'
cert_selfsigned_ensure '203.0.113.10'
[[ -s $(cert_selfsigned_fullchain '203.0.113.10') ]]
openssl x509 -in "$(cert_selfsigned_fullchain '203.0.113.10')" -noout -text |
  grep -q 'IP Address:203.0.113.10'
pin=$(cert_selfsigned_pin '203.0.113.10')
[[ ${pin} =~ ^[0-9a-f]{64}$ ]]
printf 'cert_ok pin=%s...\n' "${pin:0:16}"

printf '=== config with self-signed TLS ===\n'
state_update '.nodes += [
  {id: 1, type: "hysteria2", name: "hy2", port: 28444, enabled: true,
   server: "203.0.113.10", domain: "", tls_mode: "selfsigned", listen: "::",
   params: {password: "p", obfs: false, pin: $pin}},
  {id: 2, type: "anytls", name: "any", port: 28445, enabled: true,
   server: "203.0.113.10", domain: "", tls_mode: "selfsigned", listen: "::",
   params: {password: "p"}},
  {id: 3, type: "tuic", name: "tuic", port: 28446, enabled: true,
   server: "203.0.113.10", domain: "", tls_mode: "selfsigned", listen: "::",
   params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510", password: "p"}},
  {id: 4, type: "vmess-ws", name: "vmess", port: 28447, enabled: true,
   server: "203.0.113.10", domain: "", tls_mode: "selfsigned", listen: "::",
   params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510", ws_path: "/ws"}}
]' --arg pin "${pin}"

config_generate > "${SBQD_TMP}/server.json"
"${SB}" check -c "${SBQD_TMP}/server.json"
jq -e '[.inbounds[].tls.certificate_path] | all(contains("selfsigned"))' "${SBQD_TMP}/server.json" > /dev/null
jq -e '[.inbounds[].tls.server_name] | all(. == "203.0.113.10")' "${SBQD_TMP}/server.json" > /dev/null
printf 'server_check=OK\n'

printf '=== share links insecure ===\n'
hy2=$(share_node_uri "$(state_node_json 1)")
any=$(share_node_uri "$(state_node_json 2)")
tuic=$(share_node_uri "$(state_node_json 3)")
vmess=$(share_node_uri "$(state_node_json 4)")

[[ ${hy2} == *'insecure=1'* ]]
[[ ${hy2} == *"pinSHA256=${pin}"* ]]
[[ ${any} == *'insecure=1'* ]]
[[ ${tuic} == *'allow_insecure=1'* ]]
[[ ${vmess} == vmess://* ]]
printf 'links_ok\n'

printf '=== sing-box client profile ===\n'
share_singbox_profile > "${SBQD_TMP}/profile.json"
"${SB}" check -c "${SBQD_TMP}/profile.json"
jq -e '[.outbounds[] | select(.tls) | .tls.insecure] | all(. == true)' "${SBQD_TMP}/profile.json" > /dev/null
printf 'profile_ok\n'

printf '=== mihomo skip-cert-verify ===\n'
share_mihomo_yaml > "${SBQD_TMP}/mihomo.yaml"
[[ $(grep -c 'skip-cert-verify: true' "${SBQD_TMP}/mihomo.yaml") -eq 4 ]]
grep -q "server: '203.0.113.10'" "${SBQD_TMP}/mihomo.yaml"
printf 'mihomo_ok\n'

printf '=== schema 1 migration ===\n'
jq '.schema = 1 |
  .nodes = [{id: 9, type: "vless-reality", name: "old", port: 29001,
             enabled: true, domain: "", upstream_id: 0,
             params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510",
                      private_key: "x", public_key: "y", short_id: "z",
                      server_name: "www.microsoft.com",
                      handshake_server: "www.microsoft.com", handshake_port: 443}}]' \
  "${SBQD_STATE_FILE}" > "${SBQD_TMP}/v1.json"
cp "${SBQD_TMP}/v1.json" "${SBQD_ETC}/v1-state.json"
old_state=${SBQD_STATE_FILE}
SBQD_STATE_FILE="${SBQD_ETC}/v1-state.json"
state_migrate
jq -e '.schema == 2 and (.nodes[0].server == "203.0.113.10") and
  (.nodes[0].tls_mode == "reality") and (.nodes[0].listen == "::")' "${SBQD_STATE_FILE}" > /dev/null
SBQD_STATE_FILE=${old_state}
printf 'migration_ok\n'

printf 'ALL_OK\n'
