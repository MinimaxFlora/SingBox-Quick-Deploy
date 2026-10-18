# SingBox-Quick-Deploy

> One command, one menu: **works with a bare IP**. Five sing-box protocols, self-signed or acme.sh domain certificates, multi-IP install, and links / QR / subscription right after creation.

[![CI](https://github.com/MinimaxFlora/SingBox-Quick-Deploy/actions/workflows/ci.yml/badge.svg)](https://github.com/MinimaxFlora/SingBox-Quick-Deploy/actions/workflows/ci.yml)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![sing-box](https://img.shields.io/badge/sing--box-1.12%2B-00b4d8.svg)](https://sing-box.sagernet.org/)

## No domain required

- Hysteria2 / AnyTLS / TUIC / VMess-WS default to a **self-signed certificate with IP SAN**.
- Add a domain later to switch a node to an **acme.sh HTTP-01** certificate.
- Every node prints its QR code, share link and subscription URL immediately.
- Multi-IP VPS: one node per public IPv4, with separate ports and keys.
- Quick mode is fully automatic; custom mode lets you set port, name, domain and Reality target.

## Quick start

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/MinimaxFlora/SingBox-Quick-Deploy/main/install.sh)
```

Piping also works (the installer reconnects stdin to the terminal):

```bash
curl -fsSL https://raw.githubusercontent.com/MinimaxFlora/SingBox-Quick-Deploy/main/install.sh | bash
```

Then run:

```bash
sbqd
```

Requirements: root, systemd, Debian 12/13, Ubuntu 22.04+, RHEL 9 family; x86_64 / ARM64.

## Menu

```text
Current environment
OS: Debian GNU/Linux 12 (bookworm)
Server IP: 203.0.113.10
--------------------------------------------------
Version: v2.0.0     sing-box: 1.14.3 (running)
Nodes: 2/2    Domains: 0    Subscription: running
--------------------------------------------------

Install (co-exist, one at a time)
  1) VLESS + TCP + Reality + Vision      direct (recommended)
  2) Hysteria2                           UDP acceleration
  3) AnyTLS                              TCP camouflage
  4) TUIC v5                             low-latency UDP
  5) VMess + TLS + WebSocket             best compatibility

Relay
  6) Add upstream (SOCKS5 / Shadowsocks)

Manage
  7) Nodes / links / QR
  8) Domains & certificates (acme.sh)
  9) Subscription & export
 10) Settings
 11) System / logs / backup
 12) Uninstall
  0) Exit
```

## Protocols

| Protocol | Transport | Domain | Notes |
| --- | --- | --- | --- |
| VLESS + Reality + Vision | TCP | No | Best anti-censorship |
| Hysteria2 | UDP (QUIC) | Optional | Self-signed + `pinSHA256`, or domain |
| AnyTLS | TCP | Optional | Self-signed or domain |
| TUIC v5 | UDP (QUIC) | Optional | Self-signed or domain |
| VMess + TLS + WebSocket | TCP | Optional | Self-signed or domain |

Ports are randomly allocated in `20000-60000` and avoid system ports, other nodes, the subscription port and the Clash API port.

## TLS modes

**Self-signed (default)** — ECC certificate with `CN=<IP>` and `subjectAltName=IP:<IP>`; links carry `insecure=1` (Hysteria2 also `pinSHA256`); Mihomo / sing-box exports use `skip-cert-verify` / `insecure`.

**Domain (optional)** — point DNS to the server, open port 80, add the domain under `8) Domains & certificates`, then use it in custom mode. Renewal is automatic.

## Subscription

```text
https://node.example.com:28471/sub/<token>
```

User-Agent based format negotiation:

| Client | Format |
| --- | --- |
| Shadowrocket, v2rayNG, Passwall, Passwall2, SSR Plus, Homeproxy | Base64 URI list |
| Stash, OpenClash, Nikki, FlClash, Clash Meta for Android | Mihomo YAML |
| sing-box (SFI / SFA) | sing-box JSON |
| Quantumult X | QX conf (VMess only) |

## CLI

```bash
sbqd node add --type vless-reality --server 203.0.113.10
sbqd node add --type hysteria2 --server 203.0.113.10 --tls-mode selfsigned
sbqd node add --type tuic --server 203.0.113.10 --domain node.example.com
sbqd node list
sbqd node qr 1
sbqd domain add node.example.com --email you@example.com
sbqd sub enable --port 28471
sbqd export /root/export
sbqd status --json
sbqd doctor
sbqd uninstall
```

Global flags: `--lang zh|en`, `--json`, `--yes`, `--verbose`.

## Paths

| Path | Purpose |
| --- | --- |
| `/etc/sbqd/state.json` | nodes, domains, upstreams, settings (600) |
| `/etc/sbqd/sub/` | subscription files |
| `/etc/sing-box/config.json` | runtime config (640 root:sing-box) |
| `/etc/sing-box/cert/` | domain and self-signed certificates |
| `/usr/local/bin/sbqd` | entrypoint |

## Security

State and backups are `600`; config and keys are `640 root:sing-box`. sing-box runs as an unprivileged user with `NoNewPrivileges` and `ProtectSystem=strict`. Configs are validated and rolled back on failure. Self-signed certificates are for transport encryption only — switch to a domain certificate for production.

## Upgrade from v1

State schema 1 migrates to schema 2 automatically on first run: nodes get `server` / `tls_mode` / `listen`, domain nodes stay in domain mode, and TLS nodes without a domain become self-signed.

## Docs

- [Usage](docs/USAGE.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Client guide](docs/CLIENTS.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Contributing](CONTRIBUTING.md)

## License

[GPL-3.0](LICENSE)
