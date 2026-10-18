#!/usr/bin/env bash
# 开发探针：用真实 sing-box 校验计划中的配置结构
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

SB="${HOME}/.cache/sbqd/sing-box-1.14.3-linux-amd64/sing-box"
OUT=tests/tmp/probe
rm -rf -- "${OUT}"
mkdir -p -- "${OUT}/cert"

printf '=== version ===\n'
"${SB}" version | head -3

printf '\n=== generate reality-keypair ===\n'
"${SB}" generate reality-keypair
printf '\n=== generate uuid ===\n'
"${SB}" generate uuid
printf '\n=== generate rand --hex 8 ===\n'
"${SB}" generate rand --hex 8
printf '\n=== generate rand --base64 16 ===\n'
"${SB}" generate rand --base64 16

# 自签测试证书
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -keyout "${OUT}/cert/key.pem" -out "${OUT}/cert/fullchain.pem" -days 30 \
  -subj '/CN=probe.example.com' > /dev/null 2>&1

kp=$("${SB}" generate reality-keypair)
pk=$(sed -n 's/^PrivateKey: //p' <<< "${kp}")
pub=$(sed -n 's/^PublicKey: //p' <<< "${kp}")
uuid=$("${SB}" generate uuid)
sid=$("${SB}" generate rand --hex 8)

jq -n \
  --arg pk "$pk" --arg uuid "$uuid" --arg sid "$sid" \
  --arg cert "${PWD}/${OUT}/cert/fullchain.pem" \
  --arg key "${PWD}/${OUT}/cert/key.pem" \
  '{
    log: {level: "info", timestamp: true},
    inbounds: [
      {type: "vless", tag: "vless-reality-1", listen: "::", listen_port: 28443,
       users: [{name: "u", uuid: $uuid, flow: "xtls-rprx-vision"}],
       tls: {enabled: true, server_name: "www.microsoft.com",
             reality: {enabled: true,
                       handshake: {server: "www.microsoft.com", server_port: 443},
                       private_key: $pk, short_id: [$sid], max_time_difference: "1m"}}},
      {type: "hysteria2", tag: "hysteria2-2", listen: "::", listen_port: 28444,
       users: [{name: "u", password: "hy2-pass"}],
       obfs: {type: "salamander", password: "obfs-pass"},
       masquerade: "https://probe.example.com/",
       tls: {enabled: true, server_name: "probe.example.com", alpn: ["h3"],
             certificate_path: $cert, key_path: $key}},
      {type: "anytls", tag: "anytls-3", listen: "::", listen_port: 28445,
       users: [{name: "u", password: "anytls-pass"}],
       tls: {enabled: true, server_name: "probe.example.com",
             certificate_path: $cert, key_path: $key}},
      {type: "tuic", tag: "tuic-4", listen: "::", listen_port: 28446,
       users: [{name: "u", uuid: $uuid, password: "tuic-pass"}],
       congestion_control: "bbr", auth_timeout: "3s", zero_rtt_handshake: false,
       tls: {enabled: true, server_name: "probe.example.com", alpn: ["h3"],
             certificate_path: $cert, key_path: $key}},
      {type: "vmess", tag: "vmess-ws-5", listen: "::", listen_port: 28447,
       users: [{name: "u", uuid: $uuid, alterId: 0}],
       transport: {type: "ws", path: "/ws-probe", headers: {Host: "probe.example.com"},
                   max_early_data: 2048, early_data_header_name: "Sec-WebSocket-Protocol"},
       tls: {enabled: true, server_name: "probe.example.com", alpn: ["http/1.1"],
             certificate_path: $cert, key_path: $key}}
    ],
    outbounds: [
      {type: "direct", tag: "direct"},
      {type: "socks", tag: "upstream-1", server: "127.0.0.1", server_port: 1080,
       version: "5", username: "u", password: "p"},
      {type: "shadowsocks", tag: "upstream-2", server: "127.0.0.1", server_port: 8388,
       method: "aes-128-gcm", password: "ss-pass"}
    ],
    route: {
      rules: [
        {inbound: ["vless-reality-1"], action: "route", outbound: "upstream-1"},
        {inbound: ["vmess-ws-5"], action: "route", outbound: "upstream-2"}
      ],
      final: "direct"
    },
    experimental: {
      cache_file: {enabled: true},
      clash_api: {external_controller: "127.0.0.1:29090", secret: "probe", default_mode: "rule"}
    }
  }' > "${OUT}/server.json"

printf '\n=== check full server config ===\n'
"${SB}" check -c "${OUT}/server.json" && printf 'CHECK_OK\n'

printf '\n=== empty inbound config ===\n'
jq -n '{log:{level:"info"}, inbounds: [], outbounds:[{type:"direct",tag:"direct"}], route:{final:"direct"}}' > "${OUT}/empty.json"
"${SB}" check -c "${OUT}/empty.json" && printf 'EMPTY_OK\n'

printf '\n=== client profile (outbounds + selector + tun) ===\n'
jq -n --arg uuid "$uuid" --arg pub "$pub" --arg sid "$sid" --arg cert "${PWD}/${OUT}/cert/fullchain.pem" '{
  log: {level: "warn"},
  inbounds: [{type: "tun", tag: "tun-in", address: ["172.19.0.1/30", "fdfe:dcba:9876::1/126"], auto_route: true, strict_route: true}],
  outbounds: [
    {type: "selector", tag: "proxy", outbounds: ["vless-reality-1"], default: "vless-reality-1"},
    {type: "vless", tag: "vless-reality-1", server: "203.0.113.10", server_port: 28443,
     uuid: $uuid, flow: "xtls-rprx-vision",
     tls: {enabled: true, server_name: "www.microsoft.com",
           utls: {enabled: true, fingerprint: "chrome"},
           reality: {enabled: true, public_key: $pub, short_id: $sid}}},
    {type: "direct", tag: "direct"}
  ],
  route: {final: "proxy"}
}' > "${OUT}/client.json"
"${SB}" check -c "${OUT}/client.json" && printf 'CLIENT_OK\n'

printf '\n=== format check ===\n'
"${SB}" format "${OUT}/server.json" | jq -e '.inbounds | length == 5' > /dev/null && printf 'FORMAT_OK\n'
