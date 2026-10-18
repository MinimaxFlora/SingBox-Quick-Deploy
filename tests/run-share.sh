#!/usr/bin/env bash
# 开发自检：分享链接 / 订阅文件 / 单文件构建
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

SB="${SBQD_TEST_SINGBOX:-${HOME}/.cache/sbqd/sing-box-1.14.3-linux-amd64/sing-box}"

export SBQD_ETC="${PWD}/tests/tmp/share/etc"
export SBQD_STATE_FILE="${SBQD_ETC}/state.json"
export SBQD_SUB_DIR="${PWD}/tests/tmp/share/sub"
export SBQD_LOG_FILE="${PWD}/tests/tmp/share/sbqd.log"
export SINGBOX_BIN="${SB}"
export SINGBOX_CERT_DIR="${PWD}/tests/tmp/share/cert"
export SBQD_SUB_USER
SBQD_SUB_USER=$(id -un)

rm -rf -- tests/tmp/share
mkdir -p -- tests/tmp/share/cert

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
# shellcheck source=../src/lib/share.sh
. src/lib/share.sh
# shellcheck source=../src/lib/config.sh
. src/lib/config.sh

sbqd_init
state_init
state_update '.settings.public_ipv4 = "203.0.113.10"'
state_update '.settings.subscription.enabled = true |
  .settings.subscription.port = 28471 |
  .settings.subscription.token = "test-token" |
  .settings.subscription.domain = ""'

state_update '.domains += [{id: 1, domain: "a.example.com", email: "a@example.com",
  cert_path: "", key_path: "", issued_at: "2026-01-01", expires_at: "2027-01-01"}]'

state_update '.nodes += [
  {id: 1, type: "vless-reality", name: "HK Reality", port: 28443, enabled: true,
   domain: "", upstream_id: 0,
   params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510", flow: "xtls-rprx-vision",
            private_key: "EKsXUquIRacmmLZ9iqUxyyFSvB5XwzbYF6cSQdrpZWg",
            public_key: "7W9N9tr2kh5cIUkqKqfGeetuY5IDHug-5SsFs3o0LH4",
            short_id: "b2911a2458024ce4", server_name: "www.microsoft.com",
            handshake_server: "www.microsoft.com", handshake_port: 443}},
  {id: 2, type: "hysteria2", name: "JP HY2", port: 28444, enabled: true,
   domain: "a.example.com", upstream_id: 0,
   params: {password: "hy2pass", obfs: true, obfs_password: "obfspass"}},
  {id: 3, type: "anytls", name: "SG AnyTLS", port: 28445, enabled: true,
   domain: "a.example.com", upstream_id: 0, params: {password: "anypass"}},
  {id: 4, type: "tuic", name: "US TUIC", port: 28446, enabled: true,
   domain: "a.example.com", upstream_id: 0,
   params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510", password: "tuicpass",
            congestion_control: "bbr", zero_rtt: false}},
  {id: 5, type: "vmess-ws", name: "DE VMess", port: 28447, enabled: true,
   domain: "a.example.com", upstream_id: 0,
   params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510", ws_path: "/ws-test"}}
]'

printf '=== URIs ===\n'
u1=$(share_node_uri "$(state_node_json 1)")
u2=$(share_node_uri "$(state_node_json 2)")
u3=$(share_node_uri "$(state_node_json 3)")
u4=$(share_node_uri "$(state_node_json 4)")
u5=$(share_node_uri "$(state_node_json 5)")

[[ ${u1} == vless://*security=reality*'pbk='*'flow=xtls-rprx-vision'* ]]
[[ ${u2} == hysteria2://hy2pass@a.example.com:28444/*obfs=salamander* ]]
[[ ${u3} == anytls://anypass@a.example.com:28445/*sni=a.example.com* ]]
[[ ${u4} == tuic://*'congestion_control=bbr'*'sni=a.example.com'* ]]
[[ ${u5} == vmess://* ]]
printf 'uri_ok\n'
printf '%s\n' "${u1}" "${u2}" "${u3}" "${u4}" "${u5}" | sed 's/\(.\{110\}\).*/\1.../'

printf '\n=== vmess base64 ===\n'
vm_json=$(printf '%s' "${u5#vmess://}" | base64 -d)
jq -e '.net == "ws" and .tls == "tls" and .port == "28447"' <<< "${vm_json}" > /dev/null
printf 'vmess_json_ok %s\n' "$(jq -c '{net,path,host,sni}' <<< "${vm_json}")"

printf '\n=== sing-box client profile ===\n'
share_singbox_profile > "${SBQD_TMP}/profile.json"
"${SB}" check -c "${SBQD_TMP}/profile.json"
jq -e '.outbounds | length == 7' "${SBQD_TMP}/profile.json" > /dev/null
jq -e '.outbounds[0].type == "selector"' "${SBQD_TMP}/profile.json" > /dev/null
printf 'profile_check=OK\n'

printf '\n=== mihomo yaml ===\n'
share_mihomo_yaml > "${SBQD_TMP}/mihomo.yaml"
grep -c '^  - {name:' "${SBQD_TMP}/mihomo.yaml" | grep -qx '7' &&
  printf 'mihomo_proxies=7\n'
grep -q 'reality-opts' "${SBQD_TMP}/mihomo.yaml"
grep -q 'hysteria2' "${SBQD_TMP}/mihomo.yaml"
printf 'mihomo_ok\n'

printf '\n=== quantumult x ===\n'
share_qx_conf > "${SBQD_TMP}/qx.conf"
grep -q '^vmess=a.example.com:28447' "${SBQD_TMP}/qx.conf"
grep -q 'obfs=wss' "${SBQD_TMP}/qx.conf"
grep -q '没有 VMess-WS 节点' "${SBQD_TMP}/qx.conf" && exit 1
printf 'qx_ok\n'

printf '\n=== publish ===\n'
share_publish
[[ -s ${SBQD_SUB_DIR}/links.base64 ]]
[[ -s ${SBQD_SUB_DIR}/mihomo.yaml ]]
[[ -s ${SBQD_SUB_DIR}/singbox.json ]]
[[ -s ${SBQD_SUB_DIR}/nodes.json ]]
lines=$(base64 -d "${SBQD_SUB_DIR}/links.base64" | grep -c '://')
[[ ${lines} == '5' ]]
printf 'publish_ok lines=%s\n' "${lines}"

printf '\n=== single-file build ===\n'
bash build/build.sh > /dev/null
bash dist/sbqd.sh --version | grep -q '^sbqd 0\.1\.0$'
bash dist/sbqd.sh --help | grep -qi 'usage'
printf 'build_ok\n'

printf 'ALL_OK\n'
