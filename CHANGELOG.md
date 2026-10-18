# 更新日志

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。
格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

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
