# shellcheck shell=bash
# shellcheck disable=SC2154,SC2016
# =============================================================================
#  share.sh · 分享链接、订阅文件与二维码
#  交付格式：URI 列表 / Base64 / sing-box JSON / Mihomo YAML / Quantumult X conf
# =============================================================================

# 节点的对外地址：优先域名，其次公网 IPv4 / IPv6
share_address() {
  local node=$1 domain addr
  domain=$(jq -r '.domain // empty' <<< "${node}")
  if [[ -n ${domain} ]]; then
    printf '%s' "${domain}"
    return 0
  fi

  addr=$(state_value '.settings.public_ipv4')
  if [[ -z ${addr} ]]; then
    addr=$(state_value '.settings.public_ipv6')
  fi
  if [[ -z ${addr} ]]; then
    addr=$(detect_primary_ipv4 2> /dev/null) || addr=''
  fi
  if [[ -z ${addr} ]]; then
    sbqd_err "$(sbqd_t '未检测到公网地址，请先在设置中填写服务器地址' \
      'no public address detected, set the server address in settings first')"
    return 1
  fi

  if sbqd_is_ipv6 "${addr}"; then
    printf '[%s]' "${addr}"
  else
    printf '%s' "${addr}"
  fi
}

share_base64() {
  local input=$1
  printf '%s' "${input}" | base64 -w 0 2> /dev/null || printf '%s' "${input}" | base64 | tr -d '\n'
}

# --- 单节点 URI -------------------------------------------------------------
share_node_uri() {
  local node=$1 type addr
  type=$(jq -r '.type' <<< "${node}")
  addr=$(share_address "${node}") || return 1

  case ${type} in
    vless-reality)
      jq -rn --argjson n "${node}" --arg addr "${addr}" '
        "vless://" + $n.params.uuid + "@" + $addr + ":" + ($n.port | tostring) +
        "?encryption=none&security=reality&sni=" + ($n.params.server_name | @uri) +
        "&fp=chrome&pbk=" + ($n.params.public_key | @uri) +
        "&sid=" + ($n.params.short_id | @uri) +
        "&spx=%2F&type=tcp&flow=" + ($n.params.flow // "xtls-rprx-vision") +
        "#" + ($n.name | @uri)'
      ;;
    hysteria2)
      jq -rn --argjson n "${node}" --arg addr "${addr}" '
        "hysteria2://" + ($n.params.password | @uri) + "@" + $addr + ":" +
        ($n.port | tostring) + "/?sni=" + ($n.domain | @uri) + "&insecure=0" +
        (if ($n.params.obfs // false) then
           "&obfs=salamander&obfs-password=" + ($n.params.obfs_password | @uri)
         else "" end) +
        "#" + ($n.name | @uri)'
      ;;
    anytls)
      jq -rn --argjson n "${node}" --arg addr "${addr}" '
        "anytls://" + ($n.params.password | @uri) + "@" + $addr + ":" +
        ($n.port | tostring) + "/?sni=" + ($n.domain | @uri) + "&insecure=0" +
        "#" + ($n.name | @uri)'
      ;;
    tuic)
      jq -rn --argjson n "${node}" --arg addr "${addr}" '
        "tuic://" + $n.params.uuid + ":" + ($n.params.password | @uri) + "@" +
        $addr + ":" + ($n.port | tostring) +
        "?congestion_control=" + ($n.params.congestion_control // "bbr") +
        "&alpn=h3&sni=" + ($n.domain | @uri) +
        "&udp_relay_mode=native&allow_insecure=0" +
        "#" + ($n.name | @uri)'
      ;;
    vmess-ws)
      local json
      json=$(jq -cn --argjson n "${node}" --arg addr "${addr}" '{
        v: "2",
        ps: $n.name,
        add: $addr,
        port: ($n.port | tostring),
        id: $n.params.uuid,
        aid: "0",
        scy: "auto",
        net: "ws",
        type: "none",
        host: $n.domain,
        path: $n.params.ws_path,
        tls: "tls",
        sni: $n.domain,
        alpn: "http/1.1",
        fp: "chrome"
      }') || return 1
      printf 'vmess://%s' "$(share_base64 "${json}")"
      ;;
    *)
      sbqd_err "$(sbqd_t '未知节点类型：%s' 'unknown node type: %s' "${type}")"
      return 1
      ;;
  esac
}

# --- 二维码 -----------------------------------------------------------------
share_node_qr() {
  local node=$1 uri
  uri=$(share_node_uri "${node}") || return 1
  if ! sbqd_has_cmd qrencode; then
    printf '%s\n' "${uri}"
    return 0
  fi
  if [[ -t 1 ]]; then
    qrencode -t ANSIUTF8 -m 2 "${uri}"
  else
    qrencode -t ASCII -m 2 "${uri}"
  fi
}

share_node_qr_png() {
  local node=$1 output=$2 uri
  uri=$(share_node_uri "${node}") || return 1
  if ! sbqd_has_cmd qrencode; then
    printf '%s\n' "${uri}" > "${output}.txt"
    return 0
  fi
  qrencode -t PNG -o "${output}" -s 6 -m 2 -l M "${uri}"
}

# --- sing-box 客户端配置 ----------------------------------------------------
share_singbox_outbound() {
  local node=$1 type addr tag
  type=$(jq -r '.type' <<< "${node}")
  addr=$(share_address "${node}") || return 1
  tag="node-$(jq -r '.id' <<< "${node}")"

  case ${type} in
    vless-reality)
      jq -nc --argjson n "${node}" --arg addr "${addr}" --arg tag "${tag}" '
        {type: "vless", tag: $tag, server: $addr, server_port: ($n.port | tonumber),
         uuid: $n.params.uuid, flow: ($n.params.flow // "xtls-rprx-vision"),
         tls: {enabled: true, server_name: $n.params.server_name,
               utls: {enabled: true, fingerprint: "chrome"},
               reality: {enabled: true, public_key: $n.params.public_key,
                         short_id: $n.params.short_id}}}'
      ;;
    hysteria2)
      jq -nc --argjson n "${node}" --arg addr "${addr}" --arg tag "${tag}" '
        {type: "hysteria2", tag: $tag, server: $addr, server_port: ($n.port | tonumber),
         password: $n.params.password,
         tls: {enabled: true, server_name: $n.domain, alpn: ["h3"]}}
        + (if ($n.params.obfs // false) then
             {obfs: {type: "salamander", password: $n.params.obfs_password}}
           else {} end)'
      ;;
    anytls)
      jq -nc --argjson n "${node}" --arg addr "${addr}" --arg tag "${tag}" '
        {type: "anytls", tag: $tag, server: $addr, server_port: ($n.port | tonumber),
         password: $n.params.password,
         tls: {enabled: true, server_name: $n.domain}}'
      ;;
    tuic)
      jq -nc --argjson n "${node}" --arg addr "${addr}" --arg tag "${tag}" '
        {type: "tuic", tag: $tag, server: $addr, server_port: ($n.port | tonumber),
         uuid: $n.params.uuid, password: $n.params.password,
         congestion_control: ($n.params.congestion_control // "bbr"),
         udp_relay_mode: "native",
         tls: {enabled: true, server_name: $n.domain, alpn: ["h3"]}}'
      ;;
    vmess-ws)
      jq -nc --argjson n "${node}" --arg addr "${addr}" --arg tag "${tag}" '
        {type: "vmess", tag: $tag, server: $addr, server_port: ($n.port | tonumber),
         uuid: $n.params.uuid, security: "auto",
         tls: {enabled: true, server_name: $n.domain, alpn: ["http/1.1"]},
         transport: {type: "ws", path: $n.params.ws_path,
                     headers: {Host: $n.domain}}}'
      ;;
    *)
      return 1
      ;;
  esac
}

share_singbox_profile() {
  local outbounds='[]' tags='[]' node frag tag
  local has_nodes=0

  while IFS= read -r node; do
    [[ $(jq -r '.enabled' <<< "${node}") == 'true' ]] || continue
    if ! frag=$(share_singbox_outbound "${node}"); then
      return 1
    fi
    tag="node-$(jq -r '.id' <<< "${node}")"
    outbounds=$(jq -c --argjson f "${frag}" '. + [$f]' <<< "${outbounds}")
    tags=$(jq -c --arg t "${tag}" '. + [$t]' <<< "${tags}")
    has_nodes=1
  done < <(jq -c '.nodes[]' "${SBQD_STATE_FILE}")

  local inbounds selector
  inbounds='[{"type":"tun","tag":"tun-in","address":["172.19.0.1/30","fdfe:dcba:9876::1/126"],"auto_route":true,"strict_route":true}]'

  if ((has_nodes)); then
    selector=$(jq -nc --argjson tags "${tags}" '{type: "selector", tag: "proxy", outbounds: $tags, default: $tags[0]}')
    outbounds=$(jq -c --argjson s "${selector}" '[$s] + .' <<< "${outbounds}")
  fi
  outbounds=$(jq -c '. + [{"type":"direct","tag":"direct"}]' <<< "${outbounds}")

  jq -n --argjson inbounds "${inbounds}" --argjson outbounds "${outbounds}" --arg final "$([[ ${has_nodes} == 1 ]] && printf 'proxy' || printf 'direct')" '{
    log: {level: "warn", timestamp: true},
    inbounds: $inbounds,
    outbounds: $outbounds,
    route: {final: $final, auto_detect_interface: true}
  }'
}

# --- Mihomo YAML ------------------------------------------------------------
share_yaml_quote() {
  local s=$1
  s=${s//\'/\'\'}
  printf "'%s'" "${s}"
}

share_mihomo_proxy() {
  local node=$1 type addr name
  type=$(jq -r '.type' <<< "${node}")
  addr=$(share_address "${node}") || return 1
  name=$(jq -r '.name' <<< "${node}")

  local q_name q_addr q_domain
  q_name=$(share_yaml_quote "${name}")
  q_addr=$(share_yaml_quote "${addr}")
  q_domain=$(share_yaml_quote "$(jq -r '.domain // empty' <<< "${node}")")

  case ${type} in
    vless-reality)
      printf "  - {name: %s, type: vless, server: %s, port: %s, uuid: '%s', udp: true, tls: true, servername: '%s', flow: %s, client-fingerprint: chrome, reality-opts: {public-key: '%s', short-id: '%s'}}\n" \
        "${q_name}" "${q_addr}" "$(jq -r '.port' <<< "${node}")" \
        "$(jq -r '.params.uuid' <<< "${node}")" \
        "$(jq -r '.params.server_name' <<< "${node}")" \
        "$(jq -r '.params.flow // "xtls-rprx-vision"' <<< "${node}")" \
        "$(jq -r '.params.public_key' <<< "${node}")" \
        "$(jq -r '.params.short_id' <<< "${node}")"
      ;;
    hysteria2)
      local obfs=''
      if [[ $(jq -r '.params.obfs // false' <<< "${node}") == 'true' ]]; then
        obfs=", obfs: salamander, obfs-password: '$(jq -r '.params.obfs_password' <<< "${node}")'"
      fi
      printf "  - {name: %s, type: hysteria2, server: %s, port: %s, password: '%s', up: '100 Mbps', down: '100 Mbps', sni: %s, skip-cert-verify: false, alpn: [h3]%s}\n" \
        "${q_name}" "${q_domain}" "$(jq -r '.port' <<< "${node}")" \
        "$(jq -r '.params.password' <<< "${node}")" "${q_domain}" "${obfs}"
      ;;
    anytls)
      printf "  - {name: %s, type: anytls, server: %s, port: %s, password: '%s', sni: %s, skip-cert-verify: false, client-fingerprint: chrome, udp: true}\n" \
        "${q_name}" "${q_domain}" "$(jq -r '.port' <<< "${node}")" \
        "$(jq -r '.params.password' <<< "${node}")" "${q_domain}"
      ;;
    tuic)
      printf "  - {name: %s, type: tuic, server: %s, port: %s, uuid: '%s', password: '%s', congestion-controller: %s, alpn: [h3], sni: %s, skip-cert-verify: false, udp-relay-mode: native}\n" \
        "${q_name}" "${q_domain}" "$(jq -r '.port' <<< "${node}")" \
        "$(jq -r '.params.uuid' <<< "${node}")" \
        "$(jq -r '.params.password' <<< "${node}")" \
        "$(jq -r '.params.congestion_control // "bbr"' <<< "${node}")" "${q_domain}"
      ;;
    vmess-ws)
      printf "  - {name: %s, type: vmess, server: %s, port: %s, uuid: '%s', alterId: 0, cipher: auto, udp: true, tls: true, servername: %s, network: ws, ws-opts: {path: '%s', headers: {Host: %s}}}\n" \
        "${q_name}" "${q_domain}" "$(jq -r '.port' <<< "${node}")" \
        "$(jq -r '.params.uuid' <<< "${node}")" "${q_domain}" \
        "$(jq -r '.params.ws_path' <<< "${node}")" "${q_domain}"
      ;;
    *)
      return 1
      ;;
  esac
}

share_mihomo_yaml() {
  local node name names='' proxies=''
  local count=0

  while IFS= read -r node; do
    [[ $(jq -r '.enabled' <<< "${node}") == 'true' ]] || continue
    proxies+="$(share_mihomo_proxy "${node}")"$'\n'
    name=$(jq -r '.name' <<< "${node}")
    names+="$(share_yaml_quote "${name}"), "
    count=$((count + 1))
  done < <(jq -c '.nodes[]' "${SBQD_STATE_FILE}")

  printf 'mixed-port: 7890\n'
  printf 'allow-lan: false\n'
  printf 'mode: rule\n'
  printf 'log-level: info\n'
  printf 'proxies:\n'
  if ((count == 0)); then
    printf '  []\n'
  else
    printf '%s' "${proxies}"
  fi
  printf 'proxy-groups:\n'
  if ((count == 0)); then
    printf '  - {name: PROXY, type: select, proxies: [DIRECT]}\n'
  else
    printf '  - {name: PROXY, type: select, proxies: [AUTO, %sDIRECT]}\n' "${names}"
    printf '  - {name: AUTO, type: url-test, url: "http://www.gstatic.com/generate_204", interval: 300, tolerance: 50, proxies: [%s]}\n' "${names}"
  fi
  printf 'rules:\n'
  printf '  - MATCH,PROXY\n'
}

# --- Quantumult X（仅 VMess 节点，实验性） ---------------------------------
share_qx_conf() {
  local node name count=0

  printf '[general]\n'
  printf 'server_check_url=http://www.gstatic.com/generate_204\n\n'
  printf '[server_local]\n'

  while IFS= read -r node; do
    [[ $(jq -r '.type' <<< "${node}") == 'vmess-ws' ]] || continue
    [[ $(jq -r '.enabled' <<< "${node}") == 'true' ]] || continue
    name=$(jq -r '.name' <<< "${node}")
    name=${name// /-}
    name=${name//,/-}
    name=${name//\//-}
    printf 'vmess=%s:%s, method=none, password=%s, obfs=wss, obfs-host=%s, obfs-uri=%s, tls-verification=true, fast-open=false, udp-relay=false, tag=%s\n' \
      "$(jq -r '.domain' <<< "${node}")" \
      "$(jq -r '.port' <<< "${node}")" \
      "$(jq -r '.params.uuid' <<< "${node}")" \
      "$(jq -r '.domain' <<< "${node}")" \
      "$(jq -r '.params.ws_path' <<< "${node}")" \
      "${name}"
    count=$((count + 1))
  done < <(jq -c '.nodes[]' "${SBQD_STATE_FILE}")

  if ((count == 0)); then
    printf '# 没有 VMess-WS 节点：Quantumult X 不支持 Reality / Hysteria2 / TUIC / AnyTLS\n'
  fi

  printf '\n[policy]\n'
  printf 'static=PROXY, server_local, direct\n\n'
  printf '[filter_local]\n'
  printf 'final, PROXY\n'
}

# --- 订阅地址与发布 ---------------------------------------------------------
share_sub_url() {
  local enabled port token domain scheme host
  enabled=$(state_value '.settings.subscription.enabled' 'false')
  port=$(state_value '.settings.subscription.port' '0')
  token=$(state_value '.settings.subscription.token' '')
  if [[ ${enabled} != 'true' || ! ${port} =~ ^[0-9]+$ ]] || ((port == 0)) || [[ -z ${token} ]]; then
    return 1
  fi

  domain=$(state_value '.settings.subscription.domain' '')
  if [[ -n ${domain} ]]; then
    host=${domain}
  else
    host=$(state_value '.settings.public_ipv4' '')
    if [[ -z ${host} ]]; then
      host=$(state_value '.settings.public_ipv6' '')
    fi
  fi
  [[ -n ${host} ]] || return 1

  if [[ $(state_value '.settings.subscription.tls' 'false') == 'true' ]]; then
    scheme='https'
  else
    scheme='http'
  fi
  if sbqd_is_ipv6 "${host}"; then
    host="[${host}]"
  fi
  printf '%s://%s:%s/sub/%s' "${scheme}" "${host}" "${port}" "${token}"
}

share_links() {
  local node
  while IFS= read -r node; do
    [[ $(jq -r '.enabled' <<< "${node}") == 'true' ]] || continue
    share_node_uri "${node}"
    printf '\n'
  done < <(jq -c '.nodes[]' "${SBQD_STATE_FILE}")
}

# 生成订阅静态文件
share_publish() {
  local links dir meta tmpdir nodes_json

  state_require
  dir=${SBQD_SUB_DIR}
  mkdir -p -- "${dir}"
  chmod 750 "${dir}"
  if getent group "${SBQD_SUB_USER}" > /dev/null 2>&1; then
    chgrp "${SBQD_SUB_USER}" "${dir}" 2> /dev/null || true
  fi

  tmpdir=$(mktemp -d "${SBQD_TMP}/publish.XXXXXX")

  links=$(share_links)
  printf '%s' "${links}" > "${tmpdir}/links.txt"

  printf '%s\n' "$(share_base64 "${links}")" > "${tmpdir}/links.base64"

  share_singbox_profile > "${tmpdir}/singbox.json"
  share_mihomo_yaml > "${tmpdir}/mihomo.yaml"
  share_qx_conf > "${tmpdir}/quantumultx.conf"

  meta=$(jq -nc \
    --arg at "$(sbqd_iso_now)" \
    --argjson nodes "$(state_node_count)" \
    '{generated_at: $at, nodes: $nodes}')

  printf '%s\n' "${meta}" > "${tmpdir}/meta.json"

  nodes_json=$(jq -c '[.nodes[] | {id, type, name, port, domain, enabled, upstream_id}]' "${SBQD_STATE_FILE}")
  printf '%s\n' "${nodes_json}" > "${tmpdir}/nodes.json"

  local f
  for f in links.txt links.base64 singbox.json mihomo.yaml quantumultx.conf meta.json nodes.json; do
    if ! install -m 640 -o root -g "${SBQD_SUB_USER}" "${tmpdir}/${f}" "${dir}/${f}" 2> /dev/null; then
      install -m 640 "${tmpdir}/${f}" "${dir}/${f}"
    fi
  done
  if getent group "${SBQD_SUB_USER}" > /dev/null 2>&1; then
    chgrp -R "${SBQD_SUB_USER}" "${dir}" 2> /dev/null || true
  fi

  sbqd_debug "subscription files published to ${dir}"
  return 0
}

# 导出到用户目录（含二维码）
share_export_dir() {
  local out=$1 node name safe png links
  mkdir -p -- "${out}/qr"

  links=$(share_links)
  printf '%s' "${links}" > "${out}/links.txt"
  share_base64 "${links}" > "${out}/links.base64"
  share_singbox_profile > "${out}/singbox.json"
  share_mihomo_yaml > "${out}/mihomo.yaml"
  share_qx_conf > "${out}/quantumultx.conf"

  while IFS= read -r node; do
    [[ $(jq -r '.enabled' <<< "${node}") == 'true' ]] || continue
    name=$(jq -r '.name' <<< "${node}")
    safe=${name//[^A-Za-z0-9._-]/_}
    png="${out}/qr/$(jq -r '.type' <<< "${node}")-$(jq -r '.id' <<< "${node}")-${safe}.png"
    share_node_qr_png "${node}" "${png}" || true
  done < <(jq -c '.nodes[]' "${SBQD_STATE_FILE}")

  cat > "${out}/README.txt" << EOF
SingBox-Quick-Deploy export
Generated: $(date '+%F %T %Z')

files:
  links.txt          one share link per line
  links.base64       base64 of links.txt (v2rayN / Shadowrocket / Homeproxy)
  singbox.json       sing-box client profile (SFI / SFA / SFA)
  mihomo.yaml        Mihomo / Clash Meta / Stash / OpenClash / Nikki / FlClash
  quantumultx.conf   Quantumult X (VMess only, experimental)
  qr/                per-node QR PNG

secrets are included — keep this directory private.
EOF
  sbqd_ok "$(sbqd_t '已导出到 %s' 'exported to %s' "${out}")"
}
