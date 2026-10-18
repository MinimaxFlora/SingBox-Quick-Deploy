#!/usr/bin/env bats
# bats 单元测试：纯函数、状态、链接与配置结构
# 运行：bats tests/bats

setup() {
  export SBQD_ETC="${BATS_TEST_TMPDIR}/etc"
  export SBQD_STATE_FILE="${SBQD_ETC}/state.json"
  export SBQD_LOG_FILE="${BATS_TEST_TMPDIR}/sbqd.log"
  export SBQD_ASSETS_DIR="${BATS_TEST_DIRNAME}/../../assets"
  export SINGBOX_BIN="${SBQD_TEST_SINGBOX:-/nonexistent/sing-box}"
  export SINGBOX_CERT_DIR="${BATS_TEST_TMPDIR}/cert"

  cd "${BATS_TEST_DIRNAME}/../.." || return 1

  # shellcheck disable=SC1091
  source src/lib/core.sh
  # shellcheck disable=SC1091
  source src/lib/ui.sh
  # shellcheck disable=SC1091
  source src/lib/detect.sh
  # shellcheck disable=SC1091
  source src/lib/deps.sh
  # shellcheck disable=SC1091
  source src/lib/state.sh
  # shellcheck disable=SC1091
  source src/lib/kernel.sh
  # shellcheck disable=SC1091
  source src/lib/config.sh
  # shellcheck disable=SC1091
  source src/lib/share.sh

  sbqd_init
  ui_init
  state_init
}

teardown() {
  sbqd_cleanup 2> /dev/null || true
}

@test "port validation accepts 443 and rejects 70000" {
  run sbqd_is_port 443
  [ "${status}" -eq 0 ]
  run sbqd_is_port 70000
  [ "${status}" -ne 0 ]
  run sbqd_is_port abc
  [ "${status}" -ne 0 ]
}

@test "domain validation" {
  run sbqd_is_domain 'node.example.com'
  [ "${status}" -eq 0 ]
  run sbqd_is_domain 'not a domain'
  [ "${status}" -ne 0 ]
  run sbqd_is_domain '-bad.example.com'
  [ "${status}" -ne 0 ]
}

@test "uuid and ipv4 validation" {
  run sbqd_is_uuid '266e7806-36cf-49c8-bbb8-9dc917f0f510'
  [ "${status}" -eq 0 ]
  run sbqd_is_uuid 'not-a-uuid'
  [ "${status}" -ne 0 ]
  run sbqd_is_ipv4 '203.0.113.10'
  [ "${status}" -eq 0 ]
  run sbqd_is_ipv4 '203.0.113.999'
  [ "${status}" -ne 0 ]
}

@test "random port stays within range" {
  local port i
  for i in 1 2 3 4 5; do
    port=$(sbqd_rand_port 20000 60000)
    [ "${port}" -ge 20000 ]
    [ "${port}" -le 60000 ]
  done
}

@test "CJK width counts two columns per character" {
  [ "$(ui_width '中文abc')" -eq 7 ]
  [ "$(ui_width 'abc')" -eq 3 ]
  [ "$(ui_pad '中文' 6)" = '中文  ' ]
}

@test "state allocates sequential ids and validates" {
  [ "$(state_alloc_id next_node_id)" = '1' ]
  [ "$(state_alloc_id next_node_id)" = '2' ]
  run state_validate
  [ "${status}" -eq 0 ]
}

@test "share link for reality contains required parameters" {
  state_update '.settings.public_ipv4 = "203.0.113.10"'
  state_update '.nodes += [{
    id: 1, type: "vless-reality", name: "HK Reality", port: 28443,
    enabled: true, domain: "", upstream_id: 0,
    params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510",
             private_key: "EKsXUquIRacmmLZ9iqUxyyFSvB5XwzbYF6cSQdrpZWg",
             public_key: "7W9N9tr2kh5cIUkqKqfGeetuY5IDHug-5SsFs3o0LH4",
             short_id: "b2911a2458024ce4", server_name: "www.microsoft.com",
             handshake_server: "www.microsoft.com", handshake_port: 443}}]'

  local uri
  uri=$(share_node_uri "$(state_node_json 1)")
  [[ ${uri} == vless://* ]]
  [[ ${uri} == *'security=reality'* ]]
  [[ ${uri} == *'flow=xtls-rprx-vision'* ]]
  [[ ${uri} == *'sid=b2911a2458024ce4'* ]]
}

@test "base64 helper round-trips unicode" {
  local encoded decoded
  encoded=$(share_base64 '节点 one')
  decoded=$(printf '%s' "${encoded}" | base64 -d)
  [ "${decoded}" = '节点 one' ]
}

@test "mihomo yaml contains five proxy types" {
  state_update '.settings.public_ipv4 = "203.0.113.10"'
  state_update '.domains += [{id: 1, domain: "a.example.com"}]'
  state_update '.nodes += [
    {id: 1, type: "vless-reality", name: "r", port: 28443, enabled: true, domain: "",
     params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510",
              public_key: "7W9N9tr2kh5cIUkqKqfGeetuY5IDHug-5SsFs3o0LH4",
              short_id: "b2911a2458024ce4", server_name: "www.microsoft.com"}},
    {id: 2, type: "hysteria2", name: "h", port: 28444, enabled: true, domain: "a.example.com",
     params: {password: "p", obfs: true, obfs_password: "o"}},
    {id: 3, type: "anytls", name: "a", port: 28445, enabled: true, domain: "a.example.com",
     params: {password: "p"}},
    {id: 4, type: "tuic", name: "t", port: 28446, enabled: true, domain: "a.example.com",
     params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510", password: "p"}},
    {id: 5, type: "vmess-ws", name: "v", port: 28447, enabled: true, domain: "a.example.com",
     params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510", ws_path: "/ws"}}]'

  run share_mihomo_yaml
  [ "${status}" -eq 0 ]
  [[ ${output} == *'type: vless'* ]]
  [[ ${output} == *'reality-opts'* ]]
  [[ ${output} == *'type: hysteria2'* ]]
  [[ ${output} == *'type: anytls'* ]]
  [[ ${output} == *'type: tuic'* ]]
  [[ ${output} == *'type: vmess'* ]]
}

@test "config generator excludes disabled nodes" {
  state_update '.settings.public_ipv4 = "203.0.113.10"'
  state_update '.nodes += [
    {id: 1, type: "vless-reality", name: "on", port: 28443, enabled: true, domain: "",
     params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510",
              private_key: "EKsXUquIRacmmLZ9iqUxyyFSvB5XwzbYF6cSQdrpZWg",
              public_key: "7W9N9tr2kh5cIUkqKqfGeetuY5IDHug-5SsFs3o0LH4",
              short_id: "b2911a2458024ce4", server_name: "www.microsoft.com",
              handshake_server: "www.microsoft.com", handshake_port: 443}},
    {id: 2, type: "vless-reality", name: "off", port: 28448, enabled: false, domain: "",
     params: {uuid: "266e7806-36cf-49c8-bbb8-9dc917f0f510",
              private_key: "EKsXUquIRacmmLZ9iqUxyyFSvB5XwzbYF6cSQdrpZWg",
              public_key: "7W9N9tr2kh5cIUkqKqfGeetuY5IDHug-5SsFs3o0LH4",
              short_id: "b2911a2458024ce4", server_name: "www.microsoft.com",
              handshake_server: "www.microsoft.com", handshake_port: 443}}]'

  local config
  config=$(config_generate)
  [ "$(jq '.inbounds | length' <<< "${config}")" -eq 1 ]
  [ "$(jq -r '.inbounds[0].tag' <<< "${config}")" = 'vless-reality-1' ]
  [ "$(jq -r '.route.final' <<< "${config}")" = 'direct' ]
}
