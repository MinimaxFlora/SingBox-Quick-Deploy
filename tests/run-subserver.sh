#!/usr/bin/env bash
# 开发自检：订阅服务（UA 分流 / Token / 面板 / 404）
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

PORT=39001
TOKEN='test-token-1234567890'
ROOT="${PWD}/tests/tmp/subserver"
rm -rf -- "${ROOT}"
mkdir -p -- "${ROOT}"

printf 'vless://uuid@203.0.113.10:28443?security=reality#Node-1\n' > "${ROOT}/links.txt"
printf 'dmxlc3M6Ly91dWlkQDIwMy4wLjExMy4xMDoyODQ0Mz9zZWN1cml0eT1yZWFsaXR5I05vZGUtMQo=\n' > "${ROOT}/links.base64"
printf '{"log":{"level":"warn"},"outbounds":[{"type":"direct","tag":"direct"}],"route":{"final":"direct"}}\n' > "${ROOT}/singbox.json"
printf 'mixed-port: 7890\nproxies:\n  - {name: test, type: vless}\n' > "${ROOT}/mihomo.yaml"
printf '[general]\n[server_local]\n' > "${ROOT}/quantumultx.conf"
printf '{"generated_at":"2026-01-01T00:00:00Z","nodes":1}\n' > "${ROOT}/meta.json"
printf '{"nodes":[{"id":1,"type":"vless-reality","name":"Node 1","port":28443,"domain":"","enabled":true}]}\n' > "${ROOT}/nodes.json"

SBQD_SUB_ROOT="${ROOT}" SBQD_SUB_PORT="${PORT}" SBQD_SUB_HOST=127.0.0.1 \
  SBQD_SUB_TOKEN="${TOKEN}" SBQD_SUB_LANG=zh \
  python3 assets/subserver.py > tests/tmp/subserver.log 2>&1 &
pid=$!
trap 'kill "${pid}" 2>/dev/null || true' EXIT

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "http://127.0.0.1:${PORT}/healthz" > /dev/null 2>&1; then
    break
  fi
  sleep 0.3
done

printf '=== health ===\n'
[[ $(curl -s "http://127.0.0.1:${PORT}/healthz") == 'ok' ]]
printf 'health_ok\n'

printf '=== token ===\n'
code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/sub/wrong-token")
[[ ${code} == '404' ]]
code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/")
[[ ${code} == '404' ]]
printf 'token_ok\n'

printf '=== UA dispatch ===\n'
ct=$(curl -s -D - -o /tmp/sbqd-sub-clash "http://127.0.0.1:${PORT}/sub/${TOKEN}" \
  -H 'User-Agent: ClashMeta/1.19.2' | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type"{print $2}')
[[ ${ct} == text/yaml* ]]
grep -q 'mixed-port' /tmp/sbqd-sub-clash

ct=$(curl -s -D - -o /tmp/sbqd-sub-v2 "http://127.0.0.1:${PORT}/sub/${TOKEN}" \
  -H 'User-Agent: v2rayNG/1.9.16' | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type"{print $2}')
[[ ${ct} == text/plain* ]]
base64 -d /tmp/sbqd-sub-v2 | grep -q '^vless://'

ct=$(curl -s -D - -o /tmp/sbqd-sub-sb "http://127.0.0.1:${PORT}/sub/${TOKEN}" \
  -H 'User-Agent: sing-box/1.14.3' | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type"{print $2}')
[[ ${ct} == application/json* ]]
jq -e '.outbounds[0].type == "direct"' /tmp/sbqd-sub-sb > /dev/null

ct=$(curl -s -D - -o /tmp/sbqd-sub-qx "http://127.0.0.1:${PORT}/sub/${TOKEN}" \
  -H 'User-Agent: Quantumult%20X/1.4.0' | tr -d '\r' | awk -F': ' 'tolower($1)=="content-type"{print $2}')
[[ ${ct} == text/plain* ]]
grep -q 'server_local' /tmp/sbqd-sub-qx

# target 覆盖
curl -s "http://127.0.0.1:${PORT}/sub/${TOKEN}?target=mihomo" | grep -q 'mixed-port'
printf 'ua_dispatch_ok\n'

printf '=== dashboard ===\n'
curl -s "http://127.0.0.1:${PORT}/sub/${TOKEN}/dashboard" | grep -q 'SBQD'
curl -s "http://127.0.0.1:${PORT}/sub/${TOKEN}/api/status" | jq -e '.nodes == 1' > /dev/null
curl -s "http://127.0.0.1:${PORT}/sub/${TOKEN}/api/nodes" | jq -e '.nodes[0].name == "Node 1"' > /dev/null
printf 'dashboard_ok\n'

printf '\n=== headers ===\n'
curl -s -D - -o /dev/null "http://127.0.0.1:${PORT}/sub/${TOKEN}" \
  -H 'User-Agent: Clash' | tr -d '\r' | grep -qi 'profile-update-interval: 24'
printf 'headers_ok\n'

printf 'ALL_OK\n'
