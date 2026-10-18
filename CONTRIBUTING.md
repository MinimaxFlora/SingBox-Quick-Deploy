# 贡献指南

感谢参与改进 SingBox-Quick-Deploy。本文说明开发环境、代码规范与提交流程。

## 1. 开发环境

- Linux（Debian 12 / Ubuntu 22.04+ 推荐）或 WSL2；
- Bash 4.4+；
- shellcheck、shfmt、jq、openssl、python3；
- 可选：真实 sing-box 1.14.x 二进制用于配置校验。

```bash
git clone https://github.com/MinimaxFlora/SingBox-Quick-Deploy.git
cd SingBox-Quick-Deploy
bash tests/run-smoke.sh
```

## 2. 目录约定

- `src/lib/*.sh` 按职责拆分，新增模块需要在 `src/main.sh` 与 `src/modules.txt` 中登记；
- 所有全局变量以 `SBQD_` 开头；
- 所有函数以 `sbqd_<领域>_` 或 `<领域>_` 开头；
- 用户可见文案必须同时提供中文与英文（`sbqd_t '中文' 'English'`）；
- 不在业务模块中硬编码路径，使用 `core.sh` 中的变量。

## 3. 代码规范

### 必须

- `set -Eeuo pipefail`；
- 变量加引号：`"${var}"`；
- 不使用 `eval`；
- 不使用裸 `cat file` 解析结构化数据，使用 `jq`；
- 配置写入必须原子化并保留回滚；
- 新增命令需同时提供 `--json` 或非交互路径（如适用）。

### 禁止

- `cd` 到未校验的变量路径；
- 把密钥写入日志或命令行参数；
- 在 `set -e` 下使用裸 `[[ ... ]] && cmd`（条件为假会退出）；
- 直接修改 `/etc/sing-box/config.json`（必须经 `config_apply`）。

### 格式化与静态检查

```bash
bash build/format.sh
shellcheck -x -S warning src/lib/*.sh src/main.sh build/*.sh install.sh tests/*.sh
```

CI 会以 `shfmt -d -i 2 -ci -sr` 与 shellcheck 为准。

## 4. 测试

| 脚本 | 说明 |
| --- | --- |
| `tests/run-smoke.sh` | 状态层与工具函数 |
| `tests/run-config.sh` | 用真实 sing-box 校验配置（需二进制） |
| `tests/run-share.sh` | URI / 订阅 / 构建 |
| `tests/run-subserver.sh` | 订阅服务端点 |

下载测试用内核：

```bash
curl -fsSL -o sb.tgz \
  https://github.com/SagerNet/sing-box/releases/download/v1.14.3/sing-box-1.14.3-linux-amd64.tar.gz
tar -xzf sb.tgz
export SBQD_TEST_SINGBOX="$PWD/sing-box-1.14.3-linux-amd64/sing-box"
```

新增协议时，至少补充：

1. `tests/run-config.sh` 的入站断言；
2. `tests/run-share.sh` 的链接与客户端配置断言；
3. `docs/CLIENTS.md` 的能力矩阵。

## 5. 提交规范

使用 Conventional Commits：

```text
feat(node): support hysteria2 obfs
fix(cert): retry install-cert after renewal
docs(readme): clarify quantumult x limits
test(config): assert tuic alpn
```

提交前确保：

- `bash build/build.sh` 成功；
- 全部测试通过；
- 不包含 `tests/tmp/`、`dist/` 与个人配置。

## 6. 新增协议清单

- [ ] `nodes.sh`：类型元数据、参数生成、交互流程
- [ ] `config.sh`：服务端入站
- [ ] `share.sh`：URI、sing-box outbound、Mihomo proxy
- [ ] `state.sh`：`state_validate` 类型白名单
- [ ] `menu.sh` / `cmd.sh`：入口与文案
- [ ] `tests/`：配置与链接断言
- [ ] `docs/`：协议表与客户端矩阵
- [ ] `README.md` / `README.en.md`：特性说明

## 7. 分支与 PR

1. 从 `main` 建分支：`feat/xxx`、`fix/xxx`、`docs/xxx`；
2. 一个 PR 只做一件事；
3. PR 描述包含：动机、变更点、测试方式、兼容性影响；
4. CI 全绿后合并。

## 8. 安全

发现安全问题请勿公开提交 Issue，参见 [SECURITY.md](SECURITY.md)。
