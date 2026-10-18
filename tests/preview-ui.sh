#!/usr/bin/env bash
# 开发用：预览 TUI 效果（不随发布包安装）
set -Eeuo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
# shellcheck source=../src/lib/core.sh
. src/lib/core.sh
# shellcheck source=../src/lib/ui.sh
. src/lib/ui.sh

sbqd_init
ui_init

ui_clear
ui_banner
ui_section "节点管理  Node management"
ui_item 1 "添加节点" "Reality / HY2 / AnyTLS / TUIC / VMess-WS"
ui_item 2 "节点列表" "查看 / 二维码 / 链接"
ui_item 3 "删除节点" ""
ui_section "订阅与导出  Subscription & export"
ui_item 4 "订阅服务" "已开启 · 端口 28471"
ui_item 5 "导出配置" "Base64 / JSON / YAML / QR"

printf '\n'
ui_table "ID|类型|名称|端口|状态" \
  "1|vless-reality|HK-Reality|28443|运行" \
  "2|hysteria2|JP-HY2|28444|运行" \
  "3|anytls|SG-AnyTLS|28445|停用"

printf '\n'
ui_kv "sing-box" "1.14.3 (running)" "${SBQD_C_GREEN}"
ui_kv "订阅地址" "https://example.com:28471/sub/xxxx" "${SBQD_C_CYAN}"
ui_pause
