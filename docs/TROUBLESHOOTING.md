# 故障排查

先运行：

```bash
sbqd doctor
```

它会检查依赖、内核、状态文件、运行配置、服务状态与证书剩余天数。

## 0. 自签证书节点连不上

自签模式（IP 直连）要求客户端允许不安全连接：

- Shadowrocket：节点设置里打开「允许不安全」；
- Stash / Mihomo：`skip-cert-verify: true`（导出的 YAML 已自动写入）；
- sing-box：`tls.insecure: true`（导出的 JSON 已自动写入）；
- v2rayN：VMess 节点勾选「允许不安全」；
- Hysteria2：链接带 `insecure=1` 与 `pinSHA256`，客户端忽略证书错误但仍校验证书指纹。

如果客户端没有“允许不安全”选项，请改用域名证书模式，或换用支持该选项的客户端。

## 1. 安装失败

### `systemd is not running`

脚本依赖 systemd 管理服务。容器内需要 `--privileged` 或 systemd 支持的镜像；WSL 默认未启用 systemd。

### `unsupported CPU architecture`

仅支持 x86_64 / ARM64（armv7 为尽力支持）。检查 `uname -m`。

### 依赖安装失败

- Debian / Ubuntu：`apt-get update` 后重试；
- RHEL：确认可访问镜像源；`qrencode` 需要 EPEL；
- 离线环境：手动安装 curl、jq、openssl、python3、socat、qrencode 后重试。

### 下载 sing-box 失败

脚本会依次尝试 GitHub 直连与 `ghproxy.net` / `gh-proxy.com` / `ghfast.top` 镜像。仍失败时：

```bash
sbqd install --yes            # 跳过向导重试基础安装
```

或手动下载对应架构的 `sing-box` 放到 `/usr/local/bin/sing-box` 并 `chmod +x`。

## 2. 服务问题

### 服务启动失败

```bash
systemctl status sing-box -l
journalctl -u sing-box -n 100 --no-pager
```

常见原因：

| 日志 | 原因 | 处理 |
| --- | --- | --- |
| `address already in use` | 端口被占用 | 修改节点端口 |
| `certificate not found` | 证书路径错误 | 重新签发域名证书 |
| `permission denied` | 证书/配置权限 | `chown root:sing-box` + `chmod 640` |
| `unknown field` | 配置含已删除字段 | 使用本脚本生成，勿手改 |

### 配置校验失败

```bash
sing-box check -c /etc/sing-box/config.json
```

脚本每次变更都会先校验再替换；失败时会自动恢复 `.bak`。手工修改 `config.json` 会在下次变更时被覆盖。

### 修改后没有生效

- 节点启停、增删会自动重载；
- 手工改证书文件后 sing-box 会自动重载；
- 修改 unit 或环境文件后：`systemctl daemon-reload && systemctl restart sing-box`。

## 3. 证书问题

### 80 端口被占用

```bash
ss -lntp 'sport = :80'
```

停止 nginx / caddy / apache 后重试。脚本使用 HTTP-01 standalone，必须独占 80。

### 域名验证失败

1. `dig +short node.example.com` 是否等于公网 IP；
2. 云安全组是否放行 80；
3. Cloudflare 是否开启代理（橙云）——签发时请先关闭；
4. 是否有 CDN / 反代拦截 `/.well-known/acme-challenge/`；
5. Let's Encrypt 是否限流（等待 1 小时）。

### 证书续期失败

```bash
/root/.acme.sh/acme.sh --cron --home /root/.acme.sh --debug 2
crontab -l | grep acme.sh
```

### 证书与私钥不匹配

脚本在签发后会校验；若手工替换过文件，重新执行「域名与证书 → 续期证书」。

## 4. 节点连不上

### Reality

- 客户端 `pbk` 是否与节点详情一致；
- `sid`（shortId）是否一致；
- `sni` 是否等于服务端 `server_name`；
- 客户端时间误差是否小于 1 分钟；
- 端口是否放行（Reality 走 TCP）。

### Hysteria2 / TUIC

- 使用 UDP，安全组与防火墙都要放行 UDP；
- 域名证书必须有效；
- 客户端需允许 `insecure` 时才能连自签（本脚本不支持自签）；
- 部分网络封锁 UDP/QUIC，可换 TCP 系协议验证。

### AnyTLS / VMess-WS

- 需要域名与证书；
- VMess 的 `path` 与 `Host` 必须与导出链接一致；
- 若前面有 CDN，确认 CDN 支持 WebSocket。

### 全部节点不通

```bash
systemctl status sing-box
ss -lntup | grep -E 'sing-box'
sbqd status
```

确认服务运行、端口监听、云安全组放行。

## 5. 订阅问题

### 404

- 地址中的 Token 是否正确；
- 是否在菜单中重置过 Token；
- 路径必须是 `/sub/<token>`，不要漏 `/sub`。

### 返回内容为空 / 0 节点

- 所有节点是否被停用；
- 客户端 UA 是否被识别；强制加 `?target=base64` 测试；
- 检查 `/etc/sbqd/sub/links.txt` 是否有内容。

### 面板打不开

- 面板路径是 `/sub/<token>/dashboard`；
- 使用 HTTPS 时证书域名必须与访问域名一致；
- 外部面板需要能访问 Clash API（默认只监听 127.0.0.1）。

### 订阅服务启动失败

```bash
systemctl status sbqd-sub -l
journalctl -u sbqd-sub -n 100 --no-pager
```

常见原因：端口占用、证书副本权限、`/etc/sbqd/sub` 权限。

## 6. 客户端问题

参考 [客户端导入指南](CLIENTS.md)。

- **v2rayNG 没有 Hysteria2 / TUIC / AnyTLS**：Xray 内核不支持，属预期。
- **QX 没有节点**：QX 仅支持 VMess，且需要导入 QX conf。
- **Passwall 节点数为 0**：把节点类型切换为 sing-box 内核。
- **Homeproxy 订阅为空**：把 UA 改为 `v2rayN`。

## 7. 回滚与恢复

```bash
sbqd backups
sbqd restore /root/sbqd-backups/sbqd-20260101-120000.tar.gz
```

恢复会停止服务、覆盖状态/配置/证书，再重新校验启动。

## 8. 收集诊断信息

```bash
sbqd doctor > /tmp/sbqd-doctor.txt 2>&1
sbqd status --json >> /tmp/sbqd-doctor.txt
systemctl status sing-box --no-pager >> /tmp/sbqd-doctor.txt
journalctl -u sing-box -n 200 --no-pager >> /tmp/sbqd-doctor.txt
```

提交 Issue 前请删除其中的 UUID、密码、域名与 IP。
