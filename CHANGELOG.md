# 更新日志

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [2.0.0] - 2026-10-18

按 geto.im oneclick 的交互重写，核心变化是 **IP 直连优先**。

### 新增

- 扁平主菜单：安装协议 → 选 IP → 快速/自定义 → 立即输出链接/二维码/订阅。
- IP 直连自签证书：`CN=<IP>` + `subjectAltName=IP:<IP>`，无需域名。
- 多 IP 批量安装：自动探测本机全部公网 IPv4，支持 `0` / `1-2` / `1,3` 选择。
- 快速模式与自定义模式（端口、名称、域名、Reality 伪装目标）。
- Hysteria2 `pinSHA256` 指纹，客户端可跳过校验但仍校验证书。
- 节点新增 `server` / `tls_mode` / `listen` 字段；schema 1 自动迁移。
- `sbqd install` 安装后直接进入菜单；`sbqd` 空参数直接打开菜单。
- 安装时把单文件持久化为 `/usr/local/bin/sbqd`。
- 根权限 mock 安装测试（桩 systemctl），覆盖 ensure_base 与自签节点。

### 变更

- TLS 协议不再强制域名；域名模式仍使用 acme.sh HTTP-01。
- 订阅导出的 Mihomo / sing-box / QX 会按自签模式写入 `skip-cert-verify` / `insecure` / `tls-verification=false`。
- 节点列表新增地址与 TLS 模式列。
- 安装/使用合并：首次选择协议时才安装依赖与 sing-box。

### 修复

- `curl | bash` 时交互输入切回 `/dev/tty`，避免无法操作菜单。
- 自签证书目录归属 `root:sing-box`，服务用户可读。

## [0.1.1] - 2026-10-18

### 修复

- 证书目录归属 `root:sing-box`，避免 sing-box 以非 root 运行时无法读取证书。
- 订阅目录与文件统一设置 `sbqd-sub` 组权限，修复订阅服务读不到生成文件。
- 无 git tag 时构建版本回退到 `VERSION` 文件（修复 CI 构建断言）。
- 订阅服务重新配置端口前先停止旧实例，避免误判端口占用。
- 订阅面板显示完整 URL，并在日志中隐藏 Token。
- Quantumult X 导出时清理节点名中的空格、逗号与斜杠。

### 变更

- `install.sh` 在 Release 下载失败时自动回退到源码构建。
- 仅修改节点名称时也会刷新订阅文件。
- 安装失败后不再进入空状态菜单。

## [0.1.0] - 2026-10-18

首个可用版本。

### 新增

- 五种协议：VLESS + TCP + Reality + Vision、Hysteria2、AnyTLS、TUIC v5、VMess + TLS + WebSocket。
- 同类型节点可重复添加，端口在 20000-60000 随机分配并自动避让冲突。
- 节点管理：添加、列表、详情、启停、删除、重置密钥、设置中转、二维码。
- 出站链式中转：SOCKS5（含认证）与 Shadowsocks，按节点独立绑定。
- 域名与证书：acme.sh HTTP-01 自动签发、续期、域名删除保护。
- 订阅服务：Token 保护、UA 分流（Base64 / Mihomo YAML / sing-box JSON / QX conf）、只读状态面板与外部面板入口。
- 导出：单节点 URI、Base64、sing-box JSON、Mihomo YAML、Quantumult X conf、二维码 PNG。
- IPv4 / IPv6 双栈入站，可切换 IPv4-only。
- 防火墙自动放行（ufw / firewalld），nftables / iptables 给出提示。
- Clash API 与流量统计。
- 备份、恢复、脚本自更新、内核更新、卸载。
- 配置校验失败自动回滚；原子写入；并发锁。
- 中英双语彩色 TUI 与非交互 CLI。
- 单文件构建（内嵌订阅服务）、ShellCheck、shfmt、真实 sing-box 集成测试、GitHub Actions。

### 已知限制

- 仅支持 acme.sh HTTP-01（需要 80 端口可达）。
- Quantumult X 仅支持 VMess（QX 不支持 Reality / Hysteria2 / TUIC / AnyTLS）。
- v2rayNG 不支持 Hysteria2 / TUIC / AnyTLS（Xray 内核限制）。
- 不支持 OpenWrt / Alpine 本机部署。

[0.1.0]: https://github.com/MinimaxFlora/SingBox-Quick-Deploy/releases/tag/v0.1.0
