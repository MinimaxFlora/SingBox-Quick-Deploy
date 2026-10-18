# 使用手册

本文覆盖从安装到日常运维的完整流程。所有操作都可以在菜单完成，也可以使用文末的非交互命令。

> **v2 起**：TLS 协议默认使用 IP 自签证书，**不需要域名**；本文第 2 章仅在你想使用域名证书时需要。

## 1. 安装

### 1.1 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/MinimaxFlora/SingBox-Quick-Deploy/main/install.sh)
```

也支持 `curl ... | bash`，脚本会把交互输入切回终端。

安装脚本会：

1. 下载单文件版本到 `/usr/local/bin/sbqd`；
2. 执行 `sbqd install`：检查 root / systemd / 架构，安装依赖与 sing-box，写入 systemd 服务；
3. **直接进入主菜单**，不需要额外的初始化向导。

### 1.2 第一次安装节点

1. 在主菜单选择 `1`-`5` 中的协议；
2. 选择 IP（单 IP 自动跳过；多 IP 支持 `0` 全部、`1-2`、`1,3`）；
3. 选择安装模式：
   - `1) 快速`：随机端口、自签证书、随机 Reality 伪装目标；
   - `2) 自定义`：可填端口、名称、域名（留空=自签）、Reality 伪装目标；
4. 脚本自动生成密钥、写配置、`sing-box check`、热重载；
5. 每个节点立即输出二维码、分享链接与订阅地址。

TLS 协议选择域名时，脚本会校验该域名已在「域名与证书」中签发；否则报错并提示先添加域名。

### 1.3 支持的发行版

- Debian 12 / 13
- Ubuntu 22.04 / 24.04
- Rocky Linux 9 / AlmaLinux 9 / CentOS Stream 9
- 架构：x86_64、ARM64（armv7 会尝试，但未作为主要目标）

OpenWrt、Alpine 与无 systemd 的环境不在支持范围。

## 2. 域名与证书

### 2.1 前置条件

1. 域名 A（或 AAAA）记录指向服务器公网 IP；
2. 云厂商安全组放行 **80/tcp**；
3. 本机 80 端口未被 nginx / caddy 等占用。

脚本使用 acme.sh 的 **HTTP-01 standalone** 模式，签发期间会临时监听 80 端口。

### 2.2 添加域名

菜单：**域名与证书 → 添加域名**

```text
域名：node.example.com
ACME 邮箱：you@example.com
```

脚本会：

- 检查域名解析是否指向本机；
- 检查 80 端口；
- 安装 acme.sh（如未安装）并注册 Let's Encrypt 账户；
- 签发 ECC 证书；
- 安装到 `/etc/sing-box/cert/<domain>/fullchain.pem` 与 `privkey.pem`；
- 设置 `root:sing-box 640`；
- 写入 acme.sh 续期 cron（每天 03:00 检查）。

### 2.3 续期与删除

- **续期**：菜单「域名与证书 → 续期证书」，或 `sbqd domain renew node.example.com`。
- **删除**：先删除或改绑使用该域名的节点，否则脚本会拒绝删除。
- 证书到期时间会显示在首页状态栏。

### 2.4 常见失败原因

| 现象 | 处理 |
| --- | --- |
| `port 80 is already in use` | 停止占用 80 的服务，或改用其他机器签发 |
| `Domain not verified` | 检查 DNS、安全组、Cloudflare 是否开启代理（需关闭橙云） |
| `too many failed authorizations` | Let's Encrypt 限流，等待 1 小时后重试 |
| 证书签发成功但节点握手失败 | 检查域名是否被 CDN 代理、端口是否放行 |

## 3. 节点管理

### 3.1 添加节点

菜单：主菜单选择 `1`-`5` 中的协议，选择 IP 后填写：

- 节点名称（默认 `<协议>-<端口>`，可改）
- 端口（默认随机高端口，可改）
- 域名（可选；留空使用自签证书，填写则使用已签发域名证书）
- 中转上游（可选）
- Reality 伪装目标（仅 Reality）

创建过程会：

1. 生成随机 UUID / 密码 / Reality 密钥对 / shortId；
2. 校验端口未被占用；
3. 写入状态文件；
4. 重新生成 `config.json` 并 `sing-box check`；
5. 热重载服务，失败自动回滚。

创建成功后直接输出分享链接。

### 3.2 节点详情 / 二维码

菜单：**节点管理 → 节点详情**（输入 ID）显示类型、端口、域名、状态、上游与分享链接。
**二维码**菜单会在终端直接渲染 ASCII 二维码，适合手机扫码。

### 3.3 启停 / 删除 / 重置密钥

- **启停**：只影响该节点，服务不中断其他节点。
- **删除**：确认后删除节点并重新生成配置。
- **重置密钥**：重新生成 UUID / 密码 / Reality 密钥，旧客户端立即失效。

### 3.4 多节点与端口

- 同一协议可以无限添加；
- 每个节点端口唯一，脚本会避开系统监听端口、其他节点端口、订阅端口与 Clash API 端口；
- 端口范围在「设置 → 端口范围」调整（默认 20000-60000）。

## 4. 中转上游

### 4.1 添加

菜单：**中转上游 → 添加上游**

SOCKS5：

```text
类型：SOCKS5
名称：HK-Relay
服务器：1.2.3.4
端口：1080
用户名：（可空）
密码：（可空）
```

Shadowsocks：

```text
类型：Shadowsocks
加密方式：aes-128-gcm / aes-256-gcm / chacha20-ietf-poly1305 /
          2022-blake3-aes-128-gcm / 2022-blake3-aes-256-gcm /
          2022-blake3-chacha20-poly1305
密码：...
```

### 4.2 绑定与测试

- 添加节点时选择上游，或在「节点管理 → 设置中转」中改绑；
- 选择「直连」即取消中转；
- 「中转上游 → 测试连通性」会做 TCP 可达性检查，SOCKS5 还会用 curl 实际请求 `generate_204`。

### 4.3 注意

- 上游必须支持 UDP，否则 Hysteria2 / TUIC 的 QUIC 流量会失败；
- 删除上游会把使用它的节点自动改为直连；
- 上游密码保存在 600 的状态文件中，请勿分享该文件。

## 5. 订阅与导出

### 5.1 开启订阅

菜单：**订阅与导出 → 订阅服务设置 → 开启 / 修改端口**

- 端口：默认随机，可自定义；
- 域名：留空则 HTTP，填写已托管域名则 HTTPS（复用同证书）；
- 外部面板：可选，填写 YACD / metacubexd 地址后显示在状态页。

开启后得到：

```text
https://node.example.com:28471/sub/<token>
```

- Token 为 24 字节随机串，可在菜单重置（旧地址立即失效）；
- 按 UA 自动返回 Base64 / YAML / JSON / QX；
- 面板地址：`https://node.example.com:28471/sub/<token>/dashboard`。

### 5.2 导出配置包

菜单：**订阅与导出 → 导出配置包**，默认输出到 `/root/sbqd-export-<时间>/`：

```text
links.txt          每行一条分享链接
links.base64       Base64（v2rayN / Shadowrocket / Homeproxy）
singbox.json       sing-box 客户端配置（含 TUN 与 selector）
mihomo.yaml        Mihomo / Stash / OpenClash / Nikki / FlClash / CMFA
quantumultx.conf   Quantumult X（仅 VMess）
qr/                每个节点的二维码 PNG
README.txt         说明
```

导出目录包含节点密钥，请妥善保管。

### 5.3 单节点链接

- 节点详情页直接显示；
- `sbqd node link <ID>` 输出到 stdout；
- `sbqd node qr <ID>` 终端二维码。

## 6. 系统与服务

### 6.1 状态与日志

菜单：**系统与服务 → 运行状态 / 服务日志**

等价的文件：

- 配置：`/etc/sing-box/config.json`
- 服务：`systemctl status sing-box`
- 日志：`journalctl -u sing-box -f`

### 6.2 内核更新

菜单：**系统与服务 → 更新内核**，等价 `sbqd update kernel`。

- 从 GitHub Release 下载最新稳定版；
- 校验 GitHub 提供的 SHA-256（若有）；
- 安装后重新校验配置并热重载；
- 若新版本不兼容，可手动指定版本重装。

### 6.3 脚本更新

`sbqd update self` 会从 Releases 下载最新 `sbqd.sh`，做语法校验后覆盖当前入口。

### 6.4 备份与恢复

```bash
sbqd backup                                  # 生成 /root/sbqd-backups/sbqd-<时间>.tar.gz
sbqd backups                                 # 列出备份
sbqd restore /root/sbqd-backups/xxx.tar.gz   # 恢复
```

备份包含：状态、订阅文件、sing-box 配置、证书、unit 文件。恢复会停止服务、覆盖文件、重新校验并启动。

### 6.5 卸载

```bash
sbqd uninstall           # 保留 /etc/sbqd 与 /etc/sing-box
sbqd uninstall --purge   # 删除配置、证书、内核与用户
```

## 7. 设置

菜单：**设置**

| 项 | 说明 |
| --- | --- |
| 界面语言 | 中文 / English |
| 公网地址 | 分享链接使用的 IPv4 / IPv6；安装时自动探测 |
| 端口范围 | 随机端口区间，默认 20000-60000 |
| Clash API 密钥 | 重置后需要重新打开面板 |
| 面板地址 | 状态页上的外部面板入口 |

Clash API 默认监听 `127.0.0.1:<随机端口>`，不对公网开放。需要在本地通过 SSH 隧道访问：

```bash
ssh -L 9090:127.0.0.1:9090 root@server
```

## 8. 命令速查

```text
sbqd                                  交互菜单
sbqd install [--yes]                  安装
sbqd status [--json]                  状态
sbqd node add --type TYPE [...]       添加节点
sbqd node list [--json]               节点列表
sbqd node show ID                     节点详情
sbqd node delete ID [--yes]           删除
sbqd node enable|disable|toggle ID    启停
sbqd node rotate ID                   重置密钥
sbqd node link ID                     分享链接
sbqd node qr ID                       二维码
sbqd node set-upstream ID UPSTREAM    绑定中转
sbqd domain add DOMAIN --email EMAIL  添加域名
sbqd domain list|renew|delete         域名管理
sbqd upstream add --type ...          添加中转
sbqd upstream list|test|delete        中转管理
sbqd sub enable|disable|status|url    订阅服务
sbqd sub rotate|refresh               Token / 文件
sbqd export [DIR]                     导出配置包
sbqd backup|restore|backups           备份
sbqd update kernel|self               更新
sbqd doctor                           自检
sbqd uninstall [--purge]              卸载
```

## 9. 非交互示例

```bash
# 添加 Reality 节点并绑定 1 号上游
sbqd node add --type vless-reality --name HK --port 28443 --upstream 1

# 添加 Hysteria2 节点：IP 直连 + 自签证书
sbqd node add --type hysteria2 --name JP --server 203.0.113.10 --tls-mode selfsigned

# 添加 TUIC 节点：使用已签发域名证书
sbqd node add --type tuic --name US --server 203.0.113.10 --domain us.example.com

# 机器可读状态
sbqd status --json | jq '.nodes'

# 导出并打包
sbqd export /root/export && tar -czf /root/export.tar.gz -C /root export
```
