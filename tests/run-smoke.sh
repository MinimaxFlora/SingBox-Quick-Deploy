#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2016
# 开发自检：状态层与基础工具（不安装任何东西）
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

export SBQD_ETC="${PWD}/tests/tmp/etc"
export SBQD_STATE_FILE="${SBQD_ETC}/state.json"
export SBQD_LOG_FILE="${PWD}/tests/tmp/sbqd.log"

rm -rf -- tests/tmp
mkdir -p -- tests/tmp

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

sbqd_init
detect_all
printf 'os=%s arch=%s pkg=%s init=%s container=%s\n' \
  "${SBQD_OS_PRETTY}" "${SBQD_ARCH}" "${SBQD_PKG_MGR}" "${SBQD_INIT}" "${SBQD_CONTAINER:-none}"

state_init
state_validate
printf 'state_valid=yes\n'

id=$(state_alloc_id next_node_id)
printf 'alloc_id=%s\n' "${id}"

state_update '.nodes += [$n]' --argjson n "$(jq -nc --argjson id "${id}" '{
  id: $id, type: "vless-reality", name: "test-node", port: 23456,
  enabled: true, domain: "", upstream_id: 0,
  params: {uuid: "11111111-2222-3333-4444-555555555555"}, created_at: "2026-01-01T00:00:00Z"
}')"

printf 'node_count=%s tag=%s\n' "$(state_node_count)" "$(state_node_tag "${id}")"
printf 'node_json=%s\n' "$(state_node_json "${id}")"
printf 'rand_hex=%s rand_port=%s\n' "$(sbqd_rand_hex 8)" "$(sbqd_rand_port)"
printf 'lang=%s\n' "$(state_language)"

sbqd_is_port 443 && printf 'is_port=yes\n'
sbqd_is_domain 'a.example.com' && printf 'is_domain=yes\n'
sbqd_is_uuid '11111111-2222-3333-4444-555555555555' && printf 'is_uuid=yes\n'
! sbqd_is_domain 'not a domain' && printf 'is_domain_negative=yes\n'

state_validate
printf 'ALL_OK\n'
