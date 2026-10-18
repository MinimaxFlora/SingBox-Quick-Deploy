#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2155
# 开发自检：用真实 sing-box 校验配置生成器
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

SB="${SBQD_TEST_SINGBOX:-${HOME}/.cache/sbqd/sing-box-1.14.3-linux-amd64/sing-box}"
if [[ ! -x ${SB} ]]; then
  printf 'SKIP: %s not found\n' "${SB}"
  exit 0
fi

export SBQD_ETC="${PWD}/tests/tmp/config/etc"
export SBQD_STATE_FILE="${SBQD_ETC}/state.json"
export SBQD_LOG_FILE="${PWD}/tests/tmp/config/sbqd.log"
export SINGBOX_BIN="${SB}"
export SINGBOX_CERT_DIR="${PWD}/tests/tmp/config/cert"
export SINGBOX_CONFIG_DIR="${PWD}/tests/tmp/config/singbox"
export SINGBOX_CONFIG_FILE="${SINGBOX_CONFIG_DIR}/config.json"
export SINGBOX_USER
SINGBOX_USER="$(id -un)"

rm -rf -- tests/tmp/config
mkdir -p -- "${SINGBOX_CERT_DIR}/a.example.com"

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

sbqd_init
state_init
state_update '.settings.ipv6 = true'

openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -keyout "${SINGBOX_CERT_DIR}/a.example.com/privkey.pem" \
  -out "${SINGBOX_CERT_DIR}/a.example.com/fullchain.pem" -days 30 \
  -subj '/CN=a.example.com' > /dev/null 2>&1
chmod 640 "${SINGBOX_CERT_DIR}/a.example.com/"*.pem

state_update '.domains += [{id: 1, domain: "a.example.com", email: "a@example.com",
  cert_path: "", key_path: "", issued_at: "2026-01-01", expires_at: "2027-01-01", auto_renew: true}]'

state_update '.upstreams += [
  {id: 1, type: "socks5", name: "socks", server: "127.0.0.1", port: 1080, username: "u", password: "p"},
  {id: 2, type: "shadowsocks", name: "ss", server: "127.0.0.1", port: 8388, method: "aes-128-gcm", password: "sspass"}
]'

state_update '.nodes += [
  {id: 1, type: "vless-reality", name: "r1", port: 28443, enabled: true, domain: "", upstream_id: 1,
   params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510", flow: "xtls-rprx-vision",
            private_key: "EKsXUquIRacmmLZ9iqUxyyFSvB5XwzbYF6cSQdrpZWg",
            public_key: "7W9N9tr2kh5cIUkqKqfGeetuY5IDHug-5SsFs3o0LH4",
            short_id: "b2911a2458024ce4", server_name: "www.microsoft.com",
            handshake_server: "www.microsoft.com", handshake_port: 443}},
  {id: 2, type: "hysteria2", name: "h2", port: 28444, enabled: true, domain: "a.example.com", upstream_id: 0,
   params: {password: "hy2pass", obfs: true, obfs_password: "obfspass"}},
  {id: 3, type: "anytls", name: "a1", port: 28445, enabled: true, domain: "a.example.com", upstream_id: 0,
   params: {password: "anypass"}},
  {id: 4, type: "tuic", name: "t1", port: 28446, enabled: true, domain: "a.example.com", upstream_id: 2,
   params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510", password: "tuicpass",
            congestion_control: "bbr", zero_rtt: false}},
  {id: 5, type: "vmess-ws", name: "v1", port: 28447, enabled: true, domain: "a.example.com", upstream_id: 0,
   params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510", ws_path: "/ws-test"}},
  {id: 6, type: "vless-reality", name: "disabled", port: 28448, enabled: false, domain: "", upstream_id: 0,
   params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510", flow: "xtls-rprx-vision",
            private_key: "EKsXUquIRacmmLZ9iqUxyyFSvB5XwzbYF6cSQdrpZWg",
            short_id: "b2911a2458024ce4", server_name: "www.microsoft.com",
            handshake_server: "www.microsoft.com", handshake_port: 443}}
]'

printf '=== config_generate ===\n'
config_generate > "${SBQD_TMP}/server.json"
printf 'shape=inbounds:%s outbounds:%s rules:%s\n' \
  "$(jq '.inbounds | length' "${SBQD_TMP}/server.json")" \
  "$(jq '.outbounds | length' "${SBQD_TMP}/server.json")" \
  "$(jq '.route.rules | length' "${SBQD_TMP}/server.json")"
printf 'state_upstreams=%s\n' "$(jq '.upstreams | length' "${SBQD_STATE_FILE}")"
jq -c '[.outbounds[].tag]' "${SBQD_TMP}/server.json"
jq -e '.inbounds | length == 5' "${SBQD_TMP}/server.json" > /dev/null
jq -e '.outbounds | length == 3' "${SBQD_TMP}/server.json" > /dev/null
jq -e '.route.rules | length == 2' "${SBQD_TMP}/server.json" > /dev/null
jq -e '.route.final == "direct"' "${SBQD_TMP}/server.json" > /dev/null

printf '=== sing-box check ===\n'
config_check "${SBQD_TMP}/server.json" && printf 'server_check=OK\n'

printf '=== sing-box format (strict decode) ===\n'
"${SB}" format -c "${SBQD_TMP}/server.json" > /dev/null && printf 'format=OK\n'

printf '=== ipv4-only listen ===\n'
state_update '.settings.ipv6 = false'
config_generate > "${SBQD_TMP}/v4.json"
config_check "${SBQD_TMP}/v4.json"
jq -e '[.inbounds[].listen] | all(. == "0.0.0.0")' "${SBQD_TMP}/v4.json" > /dev/null
printf 'ipv4_listen=OK\n'

printf '=== missing cert detection ===\n'
state_update '.nodes = [.nodes[] | select(.id == 2) | .domain = "b.example.com"]'
if config_check_domains 2> /dev/null; then
  printf 'ERROR: expected domain check failure\n'
  exit 1
fi
printf 'missing_cert_detected=OK\n'

printf 'ALL_OK\n'
