# SingBox-Quick-Deploy

> One command to deploy sing-box: five protocols, outbound relay chaining, subscriptions / QR codes / multi-client export, acme.sh certificates, IPv6 and firewall — with a bilingual (Chinese / English) colored TUI.

[![CI](https://github.com/MinimaxFlora/SingBox-Quick-Deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/MinimaxFlora/SingBox-Quick-Deploy/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)

## Features

- **Five protocols**: VLESS + TCP + Reality + Vision, Hysteria2, AnyTLS, TUIC v5, VMess + TLS + WebSocket.
- **Unlimited nodes**: add the same protocol repeatedly; ports are randomly allocated in a high range with automatic collision avoidance.
- **Node lifecycle**: add, list, inspect, enable/disable, delete, rotate secrets, QR code — every change is validated and hot-reloaded.
- **Relay chaining**: per-node outbound through SOCKS5 or Shadowsocks upstream.
- **Domains & certificates**: acme.sh HTTP-01 issuance and renewal; sing-box reloads certificates automatically when files change.
- **Subscription server**: token-protected HTTP(S) endpoint with User-Agent based format negotiation and a read-only dashboard.
- **Export anywhere**: share links, Base64, sing-box JSON, Mihomo YAML, Quantumult X conf, per-node QR PNG.
- **Dual stack & firewall**: inbounds listen on `::` (IPv4-only switch), automatic ufw / firewalld rules.
- **Safe by default**: `600` state, `640` config and keys, rollback on validation failure, atomic writes, locking, hardened systemd units.
- **Maintainable**: modular bash sources, single-file release build, shellcheck + shfmt + real sing-box integration tests.

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/MinimaxFlora/SingBox-Quick-Deploy/main/install.sh | bash
```

Then:

```bash
sbqd          # interactive menu
sbqd status   # status
```

Requirements: root, systemd, Debian 12 / Ubuntu 22.04+ or RHEL 9 family; ARM64 supported.

## Protocols

| Protocol | Transport | Domain required | Port |
| --- | --- | --- | --- |
| VLESS + Reality + Vision | TCP | No | random high |
| Hysteria2 | UDP (QUIC) | Yes | random high |
| AnyTLS | TCP | Yes | random high |
| TUIC v5 | UDP (QUIC) | Yes | random high |
| VMess + TLS + WebSocket | TCP | Yes | random high |

Reality uses a real website as handshake target (default `www.microsoft.com`). The other four require a TLS certificate, so add a domain first — self-signed certificates are intentionally not supported.

## Domain & certificate

Only **acme.sh + HTTP-01 standalone** is supported:

1. Point the domain's A record to the server's public IP.
2. Port 80 must be reachable and free.
3. Menu: **Domains & certificates → Add domain**, enter domain and ACME email.

Certificates are installed to `/etc/sing-box/cert/<domain>/` with `root:sing-box 640`, and a renewal cron is written.

## Relay

```text
client → node inbound → route rule → SOCKS5 / SS upstream → destination
```

Upstreams are managed under **Upstream relay**; each node can be bound to one upstream independently, or switched back to direct at any time.

## Subscription

Enable the subscription server to get `https://node.example.com:28471/sub/<token>`. Format is selected by User-Agent:

| Client | Format |
| --- | --- |
| Shadowrocket, v2rayNG, Passwall, Passwall2, SSR Plus, Homeproxy | Base64 URI list |
| Stash, OpenClash, Nikki, FlClash, Clash Meta for Android | Mihomo YAML |
| sing-box (SFI / SFA) | sing-box JSON (with TUN inbound and selector) |
| Quantumult X | QX conf (VMess only, experimental) |

## CLI

```bash
sbqd node add --type vless-reality --name HK --port 28443
sbqd node add --type hysteria2 --domain a.example.com --upstream 1
sbqd node list
sbqd node qr 1
sbqd domain add a.example.com --email you@example.com
sbqd upstream add --type socks5 --server 1.2.3.4 --port 1080
sbqd sub enable --port 28471
sbqd export /root/export
sbqd backup
sbqd doctor
sbqd update kernel
sbqd uninstall
```

Global flags: `--lang zh|en`, `--json`, `--yes`, `--verbose`.

## Paths

| Path | Purpose |
| --- | --- |
| `/etc/sbqd/state.json` | nodes, domains, upstreams, settings (600) |
| `/etc/sbqd/sub/` | generated subscription files |
| `/etc/sing-box/config.json` | runtime config (640 root:sing-box) |
| `/etc/sing-box/cert/<domain>/` | certificates and keys |
| `/usr/local/bin/sing-box` | kernel binary |
| `/usr/local/bin/sbqd` | entrypoint |
| `/root/.acme.sh/` | acme.sh home |
| `/root/sbqd-backups/` | backups |

## Docs

- [Usage](docs/USAGE.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Client import guide](docs/CLIENTS.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Contributing](CONTRIBUTING.md)

## License

[GPL-3.0](LICENSE)
