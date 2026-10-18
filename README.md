# SingBox-Quick-Deploy

> 一条命令部署 sing-box：五种协议、链式中转、订阅 / 二维码 / 多客户端导出、acme.sh 证书、IPv6 与防火墙，全中文彩色菜单（可切英文）。

[![CI](https://github.com/MinimaxFlora/SingBox-Quick-Deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/MinimaxFlora/SingBox-Quick-Deploy/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![sing-box](https://img.shields.io/badge/sing--box-1.12%2B-00b4d8.svg)](https://sing-box.sagernet.org/)
[![Shell](https://img.shields.io/badge/shell-bash%204.4%2B-4eaa25.svg)](https://www.gnu.org/software/bash/)

---

## 特性

| 能力 | 说明 |
| --- | --- |
| 五种协议 | VLESS + TCP + Reality + Vision、Hysteria2、AnyTLS、TUIC v5、VMess + TLS + WebSocket |
| 重复添加 | 同一种协议可添加任意多个节点，端口随机高端口并自动避让冲突 |
| 节点管理 | 添加 / 列表 / 详情 / 启停 / 删除 / 重置密钥 / 二维码，改动即时校验与热重载 |
| 链式中转 | 节点流量经 SOCKS5 或 Shadowsocks 上游出站，按节点独立绑定，支持随时改绑或取消 |
| 域名证书 | acme.sh HTTP-01 自动签发与续期，证书文件变更后 sing-box 自动重载 |
| 订阅服务 | 带随机 Token 的 HTTP(S) 订阅端点，按 User-Agent 返回对应客户端格式，附只读状态面板 |
| 一键导入 | Base64、sing-box JSON、Mihomo YAML、Quantumult X conf、单节点 URI 与二维码 |
| 双栈与防火墙 | 入站默认监听 `::`（可切 IPv4-only），自动放行 ufw / firewalld 端口 |
| 安全 | 状态文件 600、配置校验失败自动回滚、原子写入、并发锁、systemd 权限收敛 |
| 双语界面 | 中文 / English 彩色 TUI，所有命令同时提供非交互子命令 |
| 可维护 | 模块化源码 + 单文件构建，shellcheck + shfmt + 真实 sing-box 集成测试 |

## 快速开始

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/MinimaxFlora/SingBox-Quick-Deploy/main/install.sh)
```

安装完成后运行：

```bash
sbqd          # 打开管理菜单
sbqd status   # 查看状态
```

> 需要 root、systemd、Debian 12 / Ubuntu 22.04+ 或 RHEL 9 系（Rocky / AlmaLinux / CentOS Stream）。
> ARM64 同样支持，脚本会按架构下载对应二进制。

### 界面预览

```text
  ╭──────────────────────────────────────────────────────────────────────────╮
  │                    ███████╗██████╗  ██████╗ ██████╗                      │
  │                    ██╔════╝██╔══██╗██╔═══██╗██╔══██╗                     │
  │                    ███████╗██████╔╝██║   ██║██║  ██║                     │
  │                    ╚════██║██╔══██╗██║   ██║██║  ██║                     │
  │                    ███████║██████╔╝╚██████╔╝██████╔╝                     │
  │                    ╚══════╝╚═════╝  ╚═════╝ ╚═════╝                      │
  │            v0.1.0   sing-box 一键部署 · 多协议 · 中转 · 订阅             │
  ╰──────────────────────────────────────────────────────────────────────────╯

  sing-box 1.14.3  ·  运行中  ·  节点 3/3
  域名 1  ·  证书 82 天  ·  订阅 运行中
  Debian GNU/Linux 12 · amd64  ·  203.0.113.10

  ▌ 管理
   1   节点管理                   3 个节点
   2   订阅与导出
   3   域名与证书                 1
   4   中转上游                    1
   5   系统与服务
   6   设置
   7   帮助
   0   退出
```

## 协议与域名

| 协议 | 传输 | 需要域名 | 默认端口 |
| --- | --- | --- | --- |
| VLESS + Reality + Vision | TCP | 否 | 随机高端口 |
| Hysteria2 | UDP (QUIC) | 是 | 随机高端口 |
| AnyTLS | TCP | 是 | 随机高端口 |
| TUIC v5 | UDP (QUIC) | 是 | 随机高端口 |
| VMess + TLS + WebSocket | TCP | 是 | 随机高端口 |

- **Reality** 不需要域名与证书，用真实网站作为握手目标（默认 `www.microsoft.com`，可自选）。
- 其余四种依赖 TLS，必须先添加域名并签发证书；没有域名时脚本会明确拒绝创建，避免自签证书带来的客户端兼容问题。
- 端口默认在 `20000-60000` 内随机分配，可在「设置 → 端口范围」调整。

## 域名与证书

仅支持 **acme.sh + HTTP-01 standalone**（按需求确认）：

1. 域名 A 记录指向本机公网 IP；
2. 放行 80 端口（脚本会在有域名时自动放行）；
3. 菜单「域名与证书 → 添加域名」，填写域名与 ACME 邮箱。

脚本自动完成签发、安装到 `/etc/sing-box/cert/<domain>/`、设置 `root:sing-box 640`、写入续期 cron。
证书文件被覆盖后 sing-box 会自动重载，无需重启。

## 中转（出站链式代理）

```text
客户端 → 节点入站 → route 规则 → SOCKS5 / SS 上游 → 目标网站
```

- 上游在「中转上游」中添加，支持 SOCKS5（可选用户名密码）与 Shadowsocks。
- 添加节点时可直接选择上游，也可在节点详情里随时改绑或取消。
- 每个节点独立生效，互不影响；上游删除后相关节点自动回落到直连。

## 订阅与客户端

开启订阅后得到形如 `https://node.example.com:28471/sub/<token>` 的地址，按 UA 自动返回：

| 客户端 | 交付格式 |
| --- | --- |
| Shadowrocket、v2rayNG、Passwall、Passwall2、SSR Plus、Homeproxy | Base64 URI 列表 |
| Stash、OpenClash、Nikki、FlClash、Clash Meta for Android | Mihomo YAML |
| sing-box（SFI / SFA） | sing-box JSON（含 TUN 入站与 selector） |
| Quantumult X | QX conf（仅 VMess，实验性，面板中会提示） |

单节点还可导出分享链接与二维码；「订阅与导出 → 导出配置包」会生成完整目录（链接、Base64、JSON、YAML、QX、每节点二维码 PNG）。

## 常用命令

```bash
sbqd install                         # 安装 / 补全安装
sbqd status --json                   # 状态（机器可读）
sbqd node add --type vless-reality --name HK --port 28443
sbqd node add --type hysteria2 --domain a.example.com --upstream 1
sbqd node list
sbqd node show 1
sbqd node link 1
sbqd node qr 1
sbqd node delete 1
sbqd node rotate 1
sbqd node set-upstream 1 2
sbqd domain add a.example.com --email you@example.com
sbqd domain list
sbqd upstream add --type socks5 --server 1.2.3.4 --port 1080 --user u --pass p
sbqd sub enable --port 28471 --domain a.example.com
sbqd sub url
sbqd export /root/export
sbqd backup
sbqd restore /root/sbqd-backups/sbqd-20260101-120000.tar.gz
sbqd update kernel
sbqd update self
sbqd doctor
sbqd uninstall
```

全局选项：`--lang zh|en`、`--json`、`--yes`、`--verbose`。

## 文件与路径

| 路径 | 用途 |
| --- | --- |
| `/etc/sbqd/state.json` | 节点、域名、上游、设置（600） |
| `/etc/sbqd/sub/` | 生成的订阅文件（750，组 `sbqd-sub`） |
| `/etc/sing-box/config.json` | sing-box 运行配置（640 root:sing-box） |
| `/etc/sing-box/cert/<domain>/` | 证书与私钥 |
| `/usr/local/bin/sing-box` | 内核 |
| `/usr/local/bin/sbqd` | 脚本入口 |
| `/usr/local/lib/sbqd/subserver.py` | 订阅服务 |
| `/root/.acme.sh/` | acme.sh 与证书源文件 |
| `/root/sbqd-backups/` | 备份归档 |

## 安全设计

- 状态文件、环境文件、备份均为 `600`；配置与私钥为 `640 root:sing-box`。
- 服务以专用用户 `sing-box` 运行，`NoNewPrivileges` + `ProtectSystem=strict` + 只暴露必要 capability。
- 订阅服务以 `sbqd-sub` 运行，只读 `/etc/sbqd/sub`，Token 使用常量时间比较。
- 配置生成后先 `sing-box check`，失败自动回滚到上一份可用配置。
- 不执行远程脚本的内容；安装包仅从 GitHub Release 下载并做语法校验。

## 兼容性

- sing-box **1.12+**（推荐 1.14.x），配置使用 1.12 新语法，不使用任何 1.13 已删除字段。
- Debian 12 / 13、Ubuntu 22.04 / 24.04、Rocky / AlmaLinux / CentOS Stream 9。
- systemd 必需；OpenWrt / Alpine 不在支持范围（可作为后续扩展）。

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
