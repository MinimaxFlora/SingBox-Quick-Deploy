# 安全策略

## 支持版本

| 版本 | 支持 |
| --- | --- |
| 0.1.x | ✅ |

## 报告漏洞

请通过 GitHub Security Advisory 私下报告：

<https://github.com/MinimaxFlora/SingBox-Quick-Deploy/security/advisories/new>

请勿在公开 Issue 中披露可利用细节、真实节点密钥或服务器地址。报告时请包含：

- 版本（`sbqd --version`）；
- 发行版与架构；
- 复现步骤与影响；
- 相关日志（脱敏）。

## 安全设计

- 状态文件、订阅环境文件、备份：`600`；
- sing-box 配置、证书、私钥：`640 root:sing-box`；
- 订阅文件：`640 root:sbqd-sub`，目录 `750`；
- sing-box 服务：`User=sing-box`、`NoNewPrivileges`、`ProtectSystem=strict`、最小 capability；
- 订阅服务：`User=sbqd-sub`、只读 `/etc/sbqd/sub`、Token 常量时间比较、白名单文件访问；
- 配置变更：先 `sing-box check`，失败自动恢复；
- 脚本不使用 `eval`，不执行远程脚本内容；
- 下载的发布文件会做 `bash -n` 语法校验。

## 用户责任

- 服务器 root 权限意味着脚本可以访问全部系统资源，请只从官方仓库获取脚本；
- 导出的配置包包含节点密钥，请勿上传到公开位置；
- 定期运行 `sbqd doctor` 并关注证书到期时间；
- 建议限制 SSH 来源、启用密钥登录，并保留云厂商安全组的最小放行原则。

## 依赖安全

- 内核来自 SagerNet/sing-box 官方 Release；
- acme.sh 来自 acmesh-official/acme.sh 官方仓库；
- 其余依赖来自系统包管理器；
- 脚本会校验 GitHub Release 提供的 SHA-256（若存在）。
