# 客户端导入指南

## 1. 能力矩阵

| 客户端 | VLESS Reality | Hysteria2 | TUIC v5 | AnyTLS | VMess WS | 推荐格式 |
| --- | --- | --- | --- | --- | --- | --- |
| Shadowrocket（小火箭） | ✅ | ✅ | ✅ | ✅ | ✅ | Base64 订阅 / 单条二维码 |
| Stash | ✅ | ✅ | ✅ | ✅ | ✅ | Mihomo YAML |
| Quantumult X | ❌ | ❌ | ❌ | ❌ | ✅ | QX conf（实验性） |
| sing-box（SFI / SFA） | ✅ | ✅ | ✅ | ✅ | ✅ | sing-box JSON |
| v2rayNG | ✅ | ❌ | ❌ | ❌ | ✅ | Base64 订阅 / 二维码 |
| FlClash | ✅ | ✅ | ✅ | ✅ | ✅ | Mihomo YAML |
| Clash Meta for Android | ✅ | ✅ | ✅ | ✅ | ✅ | Mihomo YAML |
| Passwall / Passwall2 | ✅ | ✅ | ✅ | ✅ | ✅ | Base64（内核选 sing-box） |
| SSR Plus | ✅ | ❓ | ❓ | ❓ | ✅ | Base64 |
| OpenClash | ✅ | ✅ | ✅ | ✅ | ✅ | Mihomo YAML |
| Nikki | ✅ | ✅ | ✅ | ✅ | ✅ | Mihomo YAML |
| Homeproxy | ✅ | ✅ | ✅ | ✅ | ✅ | Base64（UA 设为 v2rayN） |

说明：

- **Quantumult X** 不支持 Reality、Hysteria2、TUIC、AnyTLS，也不支持 Base64 订阅列表；脚本只导出 VMess 节点，且为实验性格式。
- **v2rayNG** 使用 Xray 内核，不支持 Hysteria2 / TUIC / AnyTLS；这些节点请用 sing-box 或 Clash Meta 系客户端。
- **Stash** 对 Reality 的兼容性取决于版本；若失败请改用 sing-box / Shadowrocket。
- 标记 ❓ 的组合缺少公开明确资料，建议先单节点导入验证。

## 2. 订阅地址

在「订阅与导出 → 订阅服务设置」开启后得到：

```text
https://node.example.com:28471/sub/<token>
```

服务按 User-Agent 自动选择格式，无需手动加参数。也可以强制指定：

```text
https://node.example.com:28471/sub/<token>?target=mihomo
https://node.example.com:28471/sub/<token>?target=singbox
https://node.example.com:28471/sub/<token>?target=base64
https://node.example.com:28471/sub/<token>?target=qx
```

可用 target：`links`、`base64`、`singbox`、`mihomo`、`clash`、`qx`。

## 3. iOS

### Shadowrocket

1. 首页右上角 `+`；
2. 类型选「Subscribe」；
3. URL 填订阅地址；
4. 保存后下拉更新。

单节点：扫描「节点详情」里的二维码，或复制分享链接后打开 App 自动识别。

### Stash

1. 「配置」→ 下载配置；
2. URL 填订阅地址（Stash UA 会返回 Mihomo YAML）；
3. 下载后选中该配置。

### sing-box（SFI）

1. 「配置」→ 新建 → 远程；
2. URL 填订阅地址；
3. 客户端会拿到带 TUN 入站与 selector 的完整 JSON。

### Quantumult X

1. 先确认存在 VMess-WS 节点；
2. 菜单导出 `quantumultx.conf`；
3. 通过 AirDrop / 文件 App 导入，或把该文件放到可访问的 URL 后在 QX 中下载。

QX 不支持 Reality / Hysteria2 / TUIC / AnyTLS，缺失属预期行为。

## 4. Android

### v2rayNG

1. 左上角菜单 → 订阅设置 → 添加订阅；
2. URL 填订阅地址；
3. 返回后点击订阅 → 更新。

注意：Reality 与 VMess 可用，Hysteria2 / TUIC / AnyTLS 不支持。

### FlClash / Clash Meta for Android

1. 「配置」→ 添加 → URL；
2. 填订阅地址；
3. 下载并启用。

### sing-box（SFA）

1. 「配置」→ 新建 → 远程；
2. 填订阅地址；
3. 选择该配置启动。

## 5. 软路由

### OpenClash / Nikki

1. 配置文件 → 订阅 → 添加；
2. URL 填订阅地址；
3. 更新并切换配置。

### Passwall / Passwall2

1. 节点订阅 → 添加；
2. URL 填订阅地址；
3. 节点类型选 sing-box 内核以支持 TUIC / AnyTLS / Hysteria2。

### Homeproxy

1. 节点 → 订阅 → 添加；
2. URL 填订阅地址；
3. 若识别为 0 节点，把 UA 改成 `v2rayN`。

### SSR Plus

1. 服务器 → 订阅 → 添加；
2. URL 填订阅地址；
3. 若新协议未出现，说明固件的 Xray 内核不支持。

## 6. 单节点二维码

- 菜单：节点管理 → 二维码 → 输入 ID；
- 命令：`sbqd node qr 1`；
- 导出包：`qr/<type>-<id>-<name>.png`。

二维码内容是单条分享链接，所有客户端扫码即可添加单个节点。

## 7. 常见问题

- **订阅 404**：Token 错误或已在菜单中重置，重新复制地址。
- **订阅 200 但 0 节点**：检查客户端 UA；必要时加 `?target=base64`。
- **QX 导入后没有节点**：确认有 VMess-WS 节点；QX 不支持其他四种。
- **Stash 中 Reality 不可用**：升级 Stash 或改用 sing-box。
- **Passwall 缺节点**：把节点类型切换为 sing-box 内核后重新订阅。
