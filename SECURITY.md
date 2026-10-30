# 安全策略

## 支持范围

当前维护的构建线：`24.10.x`、`25.12.x`（对应 `master` 分支上的两套 workflow）。
更早的构建产物不再单独修复，建议重新构建。

## 报告漏洞

请**不要**在公开 Issue 中披露安全问题。请使用 GitHub 的私密渠道：

1. 打开本仓库 **Security** 标签页；
2. 点击 **Report a vulnerability**（GitHub Security Advisories）；
3. 描述影响版本、复现步骤与影响面。

一般 7 天内回应。涉及构建流水线凭据、发布产物被篡改类的报告会优先处理。

## 已知且已知情的风险（不属于漏洞，但请务必了解）

| 风险 | 说明 | 关闭方式 |
|---|---|---|
| PPPoE 凭据明文进固件 | 写入 `/etc/config/pppoe-settings`，固件发布在公开 Release | 不使用 `enable_pppoe` |
| Open-Box 安装器默认不校验 | 从第三方 GitHub 代理下载 script 后执行；`.sha256` 与脚本同源，`OPENBOX_EXPECTED_SHA256` 目前无人填充 | `enable_openbox: no` |
| root 默认无密码 | 与 OpenWrt 默认一致；靠 WAN 入站 REJECT + SSH 仅 LAN 兜底 | 刷机后立即 `passwd` |
| 第三方软件包未校验 | 构建时从 `down.dllkids.xyz` 直接下载 | 修改 `shell/custom-packages.sh` 移除 |

## 不在范围内

- ImmortalWrt / OpenWrt 上游自身的问题（请报给上游）；
- 运营商侧 PPPoE 相关限制；
- 已获得设备物理访问权限后的攻击（本项目的模型不防御物理接触）。
