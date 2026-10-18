# SingBox-Quick-Deploy

> 一条命令、一个菜单：**IP 直连即可用**。五种 sing-box 协议、自签证书 / acme.sh 域名双模式、多 IP 批量安装、装完立即出链接 / 二维码 / 订阅。

[![CI](https://github.com/MinimaxFlora/SingBox-Quick-Deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/MinimaxFlora/SingBox-Quick-Deploy/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![sing-box](https://img.shields.io/badge/sing--box-1.12%2B-00b4d8.svg)](https://sing-box.sagernet.org/)
[![Shell](https://img.shields.io/badge/shell-bash%204.4%2B-4eaa25.svg)](https://www.gnu.org/software/bash/)

---

## 这不是又一个“必须先有域名”的脚本

- **没有域名也能用**：Hysteria2 / AnyTLS / TUIC / VMess-WS 默认生成 **IP SAN 自签证书**，客户端勾选“允许不安全”即可连接。
- **有域名更好**：随时在菜单里用 **acme.sh HTTP-01** 签发证书，节点切换为域名模式，客户端不再需要跳过校验。
- **装完就能扫**：每个节点创建后立刻输出二维码、分享链接和订阅地址，不用再翻二级菜单。
- **多 IP 机器**：自动探测所有公网 IPv4，一次为每个 IP 生成独立端口、独立密钥的节点。
- **两种模式**：快速模式全自动；自定义模式可改端口、名称、域名与 Reality 伪装目标。

## 快速开始

推荐进程替换方式（交互输入更稳）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/MinimaxFlora/SingBox-Quick-Deploy/main/install.sh)
```

也支持管道方式（脚本会自动把输入切回终端）：

```bash
curl -fsSL https://raw.githubusercontent.com/MinimaxFlora/SingBox-Quick-Deploy/main/install.sh | bash
```

安装完成后输入：

```bash
sbqd
```

要求：root、systemd、Debian 12/13、Ubuntu 22.04+、RHEL 9 系；x86_64 / ARM64。

## 界面

```text
当前检测到信息
操作系统：Debian GNU/Linux 12 (bookworm)
服务器IP：203.0.113.10
--------------------------------------------------
当前版本：v2.0.1     sing-box：1.14.3（运行中）
节点：2/2    域名：0    订阅：运行中
--------------------------------------------------

安装（可共存，一次装一种）
  1) VLESS + TCP + Reality + Vision      直连（最推荐）
  2) Hysteria2                           UDP 加速
  3) AnyTLS                              TCP 伪装
  4) TUIC v5                             UDP 低延迟
  5) VMess + TLS + WebSocket             兼容性最好

中转
  6) 添加中转（SOCKS5 / Shadowsocks）

管理
  7) 查看节点 / 链接 / 二维码
  8) 域名与证书（acme.sh）
  9) 订阅与导出
 10) 设置
 11) 系统状态 / 日志 / 备份
 12) 卸载
  0) 退出
```

选择协议后：

1. 选择要安装的 IP（多 IP 支持 `0` 全部、`1-2`、`1,3`）；
2. 选择快速或自定义；
3. 自动安装依赖与 sing-box、创建节点、热重载；
4. 直接输出二维码、链接、订阅地址。

## 协议

| 协议 | 传输 | 域名 | 说明 |
| --- | --- | --- | --- |
| VLESS + TCP + Reality + Vision | TCP | 不需要 | 伪装真实网站，抗封锁最好 |
| Hysteria2 | UDP (QUIC) | 可选 | 自签 + `pinSHA256`，或域名证书 |
| AnyTLS | TCP | 可选 | 自签或域名证书 |
| TUIC v5 | UDP (QUIC) | 可选 | 自签或域名证书 |
| VMess + TLS + WebSocket | TCP | 可选 | 自签或域名证书，兼容性最好 |

端口默认在 `20000-60000` 内随机分配，自动避让系统端口、其他节点、订阅端口与 Clash API 端口。

## TLS 两种模式

### 自签（默认，无需域名）

- 为节点地址生成 `CN=<IP>`、`subjectAltName=IP:<IP>` 的 ECC 证书；
- 证书位于 `/etc/sing-box/cert/selfsigned/<地址>/`；
- 分享链接自动带 `insecure=1`（Hysteria2 额外带 `pinSHA256`）；
- Mihomo / sing-box 客户端配置带 `skip-cert-verify: true` / `insecure: true`；
- 客户端需允许“不安全连接”。

### 域名（可选）

1. 域名 A 记录指向本机；
2. 放行 80 端口；
3. 菜单 `8) 域名与证书 → 添加域名`，填写域名与邮箱；
4. 创建节点时在自定义模式填写该域名。

证书自动续期，sing-box 检测到证书文件变化后自动重载。

## 多 IP

- 自动收集本机所有公网 IPv4（排除私网），并补充出口 IP；
- 默认全部安装，也可只选部分；
- 每个 IP 使用独立端口与独立密钥；
- 每个 IP 生成独立自签证书。

## 订阅与客户端

菜单 `9) 订阅与导出` 可开启带 Token 的订阅服务：

```text
https://node.example.com:28471/sub/<token>
```

按 UA 自动返回：

| 客户端 | 格式 |
| --- | --- |
| Shadowrocket、v2rayNG、Passwall、Passwall2、SSR Plus、Homeproxy | Base64 URI 列表 |
| Stash、OpenClash、Nikki、FlClash、Clash Meta for Android | Mihomo YAML |
| sing-box（SFI / SFA） | sing-box JSON |
| Quantumult X | QX conf（仅 VMess，实验性） |

自签节点在 Clash / sing-box 配置里已标记跳过证书校验；QX 标记 `tls-verification=false`。

单节点：创建后直接显示二维码与链接；也可在 `7) 查看节点` 中重新输出。

导出包包含：`links.txt`、`links.base64`、`singbox.json`、`mihomo.yaml`、`quantumultx.conf`、每节点二维码 PNG。

## 中转

- 支持 SOCKS5（可选认证）与 Shadowsocks；
- 节点创建时可选上游，也可后续在节点管理中改绑；
- 每个节点独立生效，删除上游自动回落直连。

## 常用命令

```bash
sbqd                                             # 菜单
sbqd node add --type vless-reality --server 203.0.113.10
sbqd node add --type hysteria2 --server 203.0.113.10 --tls-mode selfsigned
sbqd node add --type tuic --server 203.0.113.10 --domain node.example.com
sbqd node list
sbqd node show 1
sbqd node link 1
sbqd node qr 1
sbqd node delete 1
sbqd node rotate 1
sbqd node set-upstream 1 2
sbqd domain add node.example.com --email you@example.com
sbqd upstream add --type socks5 --server 1.2.3.4 --port 1080
sbqd sub enable --port 28471
sbqd export /root/export
sbqd status --json
sbqd doctor
sbqd update kernel
sbqd update self
sbqd uninstall
```

全局选项：`--lang zh|en`、`--json`、`--yes`、`--verbose`。

## 路径

| 路径 | 用途 |
| --- | --- |
| `/etc/sbqd/state.json` | 节点、域名、上游、设置（600） |
| `/etc/sbqd/sub/` | 订阅文件（750，组 `sbqd-sub`） |
| `/etc/sing-box/config.json` | 运行配置（640 root:sing-box） |
| `/etc/sing-box/cert/` | 域名证书与自签证书 |
| `/usr/local/bin/sing-box` | 内核 |
| `/usr/local/bin/sbqd` | 入口（安装时持久化） |
| `/root/sbqd-backups/` | 备份 |

## 安全

- 状态、环境文件、备份 `600`；配置与私钥 `640 root:sing-box`；
- sing-box 以专用用户运行，`NoNewPrivileges` + `ProtectSystem=strict`；
- 订阅服务以 `sbqd-sub` 运行，Token 常量时间比较、只读订阅目录；
- 配置先 `sing-box check` 再原子替换，失败自动回滚；
- 自签证书仅用于加密传输，**生产环境建议尽快切换到域名证书**。

## 兼容性

- sing-box 1.12+（推荐 1.14.x），使用 1.12 新语法；
- Debian 12/13、Ubuntu 22.04/24.04、Rocky / AlmaLinux / CentOS Stream 9；
- systemd 必需；不支持 OpenWrt / Alpine 本机部署。

## 从 v1 升级

首次运行会自动把 schema 1 状态迁移到 schema 2：

- 为旧节点补齐 `server` / `tls_mode` / `listen`；
- 原来有域名的节点保持域名模式；
- 原来没有域名的 TLS 节点自动转为自签模式。

备份文件仍可直接恢复。

## 文档

- [使用手册](docs/USAGE.md)
- [架构与状态模型](docs/ARCHITECTURE.md)
- [客户端导入指南](docs/CLIENTS.md)
- [故障排查](docs/TROUBLESHOOTING.md)
- [贡献指南](CONTRIBUTING.md)
- [更新日志](CHANGELOG.md)

## English

See [README.en.md](README.en.md).

## License

[GPL-3.0](LICENSE)
