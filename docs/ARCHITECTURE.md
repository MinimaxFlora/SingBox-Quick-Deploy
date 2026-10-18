# 架构与状态模型

## 1. 设计目标

- **单一事实来源**：所有节点、域名、上游与设置都保存在一个 JSON 状态文件中，配置由状态纯函数生成。
- **可回滚**：任何变更先校验再落盘，失败时恢复旧配置与旧状态。
- **可测试**：配置生成、链接生成是纯函数，可在没有 root / systemd 的环境下用真实 sing-box 校验。
- **可发布**：模块化源码通过 `build/build.sh` 合并为单文件，安装时无需仓库。

## 2. 目录结构

```text
.
├── install.sh               # 一键安装引导
├── src/
│   ├── main.sh              # 源码入口（source 所有模块）
│   ├── modules.txt          # 单文件构建的模块顺序
│   └── lib/
│       ├── core.sh          # 常量、路径、日志、错误、校验、锁
│       ├── ui.sh            # 终端 UI（盒子、菜单、表格、spinner）
│       ├── detect.sh        # 发行版 / 架构 / systemd / 公网 IP
│       ├── deps.sh          # 依赖安装、acme.sh、下载器
│       ├── state.sh         # state.json 读写与领域查询
│       ├── kernel.sh        # sing-box 安装 / 升级 / 密钥生成
│       ├── service.sh       # systemd unit 与生命周期
│       ├── cert.sh          # acme.sh HTTP-01
│       ├── config.sh        # 状态 → config.json → check → reload
│       ├── nodes.sh         # 五种节点的 CRUD
│       ├── relay.sh         # SOCKS5 / SS 上游
│       ├── share.sh         # URI / Base64 / JSON / YAML / QX / QR
│       ├── subserver.sh     # 订阅服务与面板
│       ├── firewall.sh      # ufw / firewalld
│       ├── backup.sh        # 备份、恢复、卸载
│       ├── installer.sh     # 安装与自更新
│       ├── menu.sh          # TUI 菜单
│       └── cmd.sh           # 非交互命令分发
├── assets/subserver.py      # 订阅服务 + 状态面板（标准库）
├── build/
│   ├── build.sh             # 单文件构建（内嵌 Python）
│   └── format.sh            # shfmt
├── tests/                   # 集成自检脚本
└── docs/
```

模块之间没有循环依赖：`core` 不引用其他模块；业务模块只依赖更底层的模块；`menu` / `cmd` 位于最上层。

## 3. 状态模型

`/etc/sbqd/state.json`（schema 1，权限 600）：

```json
{
  "schema": 1,
  "created_at": "2026-10-18T07:00:00Z",
  "updated_at": "2026-10-18T07:10:00Z",
  "next_node_id": 4,
  "next_upstream_id": 2,
  "next_domain_id": 2,
  "settings": {
    "language": "zh",
    "port_min": 20000,
    "port_max": 60000,
    "ipv6": true,
    "public_ipv4": "203.0.113.10",
    "public_ipv6": "",
    "clash_api": {
      "enabled": true,
      "listen": "127.0.0.1",
      "port": 39091,
      "secret": "..."
    },
    "subscription": {
      "enabled": true,
      "port": 28471,
      "token": "...",
      "tls": true,
      "domain": "node.example.com",
      "panel_url": ""
    },
    "singbox": {"version": "1.14.3", "mirror": ""}
  },
  "domains": [
    {
      "id": 1,
      "domain": "node.example.com",
      "email": "you@example.com",
      "cert_path": "/etc/sing-box/cert/node.example.com/fullchain.pem",
      "key_path": "/etc/sing-box/cert/node.example.com/privkey.pem",
      "issued_at": "2026-10-18T07:00:00Z",
      "expires_at": "2027-01-16T07:00:00Z",
      "auto_renew": true
    }
  ],
  "upstreams": [
    {
      "id": 1,
      "type": "socks5",
      "name": "HK-Relay",
      "server": "198.51.100.20",
      "port": 1080,
      "username": "u",
      "password": "p",
      "method": "",
      "created_at": "..."
    }
  ],
  "nodes": [
    {
      "id": 1,
      "type": "vless-reality",
      "name": "HK-Reality",
      "port": 28443,
      "enabled": true,
      "domain": "",
      "upstream_id": 1,
      "params": {
        "uuid": "...",
        "private_key": "...",
        "public_key": "...",
        "short_id": "...",
        "flow": "xtls-rprx-vision",
        "handshake_server": "www.microsoft.com",
        "handshake_port": 443,
        "server_name": "www.microsoft.com"
      },
      "created_at": "..."
    }
  ]
}
```

### 3.1 各类型节点的 params

| 类型 | 字段 |
| --- | --- |
| `vless-reality` | `uuid` `private_key` `public_key` `short_id` `flow` `handshake_server` `handshake_port` `server_name` |
| `hysteria2` | `password` `obfs` `obfs_password` |
| `anytls` | `password` |
| `tuic` | `uuid` `password` `congestion_control` `zero_rtt` |
| `vmess-ws` | `uuid` `ws_path` |

### 3.2 写入规则

- `state_update` 是唯一写入口：`jq` 过滤 → 备份 `.prev` → 更新 `updated_at` → 原子替换；
- 所有写操作在 `flock` 保护下进行；
- 变更失败时调用方恢复变更前的状态快照；
- `state_validate` 校验 schema、数组类型、节点 ID/端口唯一、节点类型合法。

## 4. 配置生成管线

```text
state.json
   │  config_generate（纯函数）
   ▼
config.json.tmp
   │  sing-box check -c
   ▼
校验失败 ──► 报错（旧配置不动）
   │
   ▼ 成功
原子替换 /etc/sing-box/config.json（640 root:sing-box）
   │
   ▼
systemctl reload sing-box（SIGHUP）
   │
   ├─ 失败 / 进程未存活 ──► 恢复 .bak + restart
   ▼
刷新订阅文件 → 同步防火墙 → 完成
```

### 4.1 入站

- 所有入站共用 `listen: "::"`（双栈）或 `0.0.0.0`（IPv4-only）。
- tag 固定为 `<type>-<id>`，例如 `vless-reality-1`。
- Reality 使用 `handshake.server/server_port`、`private_key`、`short_id` 数组。
- Hysteria2 默认启用 salamander 混淆与 `masquerade: https://<domain>/`。
- TUIC 默认 `bbr` 拥塞控制、`alpn: ["h3"]`。
- VMess 使用 `alterId: 0`、WebSocket `path`、`Host` 头与 early data。

### 4.2 出站与链式

- 固定存在 `direct`；
- 每个上游生成 `upstream-<id>` outbound（`socks` / `shadowsocks`）；
- 绑定了上游的节点生成路由规则：

```json
{"inbound": ["hysteria2-2"], "action": "route", "outbound": "upstream-1"}
```

- `route.final = direct`，未命中规则的流量直连；
- 不使用 `detour`，因为入站流量只需要选择最终出口，上游本身即落地代理。

### 4.3 DNS

不生成 `dns` 段，使用 sing-box 默认解析。上游为 SOCKS5 时域名由上游解析，减少本地 DNS 泄漏；Hysteria2 / TUIC 的 QUIC 流量要求上游支持 UDP。

### 4.4 兼容性

- 目标 minimum **1.12.0**，发布线 1.14.x；
- 不使用 1.13 已删除字段（legacy inbound 字段、`block`/`dns` outbound、`domain_strategy`）；
- 路由规则统一 `action: "route"`；
- 证书使用 `certificate_path` / `key_path`，不使用已废弃的 inline `tls.acme`。

## 5. 证书

- 仅 HTTP-01 standalone：`acme.sh --issue --standalone -d <domain> --httpport 80 --server letsencrypt`；
- 安装到 `/etc/sing-box/cert/<domain>/{fullchain,privkey}.pem`；
- 签发后校验证书与私钥匹配；
- 续期由 acme.sh cron 完成，`--install-cert` 自带的 reloadcmd 触发 `systemctl reload sing-box`；
- sing-box 监测到证书文件变化也会自动重载。

## 6. 订阅服务

`assets/subserver.py`（仅标准库）：

- `ThreadingHTTPServer`，可选 TLS（复用域名证书副本）；
- 路由：
  - `GET /healthz`
  - `GET /sub/<token>` → 按 UA 返回
  - `GET /sub/<token>/<target>` → `links|base64|singbox|mihomo|clash|qx`
  - `GET /sub/<token>/dashboard` → 状态页
  - `GET /sub/<token>/api/status` → Clash API 聚合
  - `GET /sub/<token>/api/nodes` → 脱敏节点列表
- Token 使用 `hmac.compare_digest`；
- 只读取白名单文件，拒绝路径穿越；
- 配置来自 `/etc/sbqd/sub.env`（600），由 systemd `EnvironmentFile` 注入，避免出现在进程参数中。

## 7. 安全模型

| 资产 | 权限 |
| --- | --- |
| state.json / sub.env / 备份 | 600 root |
| config.json | 640 root:sing-box |
| 证书 / 私钥 | 640 root:sing-box |
| 订阅文件 | 640 root:sbqd-sub，目录 750 |
| subserver.py | 644 root |

- sing-box 以 `sing-box` 用户运行，`ProtectSystem=strict`、`NoNewPrivileges`、最小 capability；
- 订阅服务以 `sbqd-sub` 运行，只读 `/etc/sbqd/sub`；
- 配置校验失败自动回滚，避免坏配置导致断网；
- 脚本不使用 `eval`，不拼接可执行字符串。

## 8. 构建与测试

### 构建

```bash
bash build/build.sh 0.1.0
# dist/sbqd.sh + dist/sbqd.sh.sha256
```

构建脚本：

1. 读取 `src/modules.txt` 顺序合并；
2. 注入 `SBQD_VERSION`、`SBQD_SELF`；
3. 把 `assets/subserver.py` 以 Base64 内嵌；
4. `bash -n` 语法校验；
5. 输出 SHA-256。

### 测试

| 脚本 | 覆盖 |
| --- | --- |
| `tests/run-smoke.sh` | 状态读写、ID 分配、校验函数 |
| `tests/run-config.sh` | 真实 sing-box 校验五种入站、链式出站、IPv6 切换、缺证书检测 |
| `tests/run-share.sh` | 五种 URI、VMess Base64、sing-box profile、Mihomo YAML、QX、发布、构建 |
| `tests/run-subserver.sh` | UA 分流、Token、面板 API、响应头、404 |

CI 在 Ubuntu 上安装 shellcheck、shfmt 与 sing-box 1.14.3 后执行全部脚本。

## 9. 扩展新协议

1. 在 `nodes.sh` 的 `nodes_generate_params` 增加参数生成；
2. 在 `config.sh` 的 `config_node_inbound` 增加入站；
3. 在 `share.sh` 增加 URI、sing-box outbound、Mihomo proxy；
4. 在 `nodes.sh` 的 `nodes_type_*` 增加类型元数据；
5. 更新 `state_validate` 白名单、菜单与文档；
6. 在 `tests/run-config.sh` 与 `tests/run-share.sh` 增加断言。

## 10. v2 状态模型补充

v2 在 schema 2 中为节点增加三个字段：

| 字段 | 取值 | 说明 |
| --- | --- | --- |
| `server` | IP 或域名 | 对外通告地址，分享链接使用 |
| `domain` | 空或域名 | 仅域名证书模式使用 |
| `tls_mode` | `reality` / `domain` / `selfsigned` | 决定证书来源与客户端参数 |
| `listen` | `::` / `0.0.0.0` | 监听地址 |

- 自签证书：`/etc/sing-box/cert/selfsigned/<地址>/`，`CN=<地址>`，`subjectAltName=IP/DNS:<地址>`；
- Hysteria2 自签节点在 `params.pin` 保存 SHA-256 指纹；
- 分享层根据 `tls_mode` 自动写入 `insecure=1` / `allow_insecure=1` / `skip-cert-verify: true`；
- `state_migrate` 会把 schema 1 节点补成 schema 2：有域名的保持 `domain`，无域名的 TLS 节点转为 `selfsigned`。

安装流程改为惰性：`sbqd_ensure_base` 在第一次安装协议时执行依赖、内核、服务初始化，之后由 `SBQD_BASE_READY` 避免重复。
