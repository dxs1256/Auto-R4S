# Changelog

本项目自 2026-10-30 起独立维护（脱离 fork 关系）。更早的历史见 git 记录。

## 2026-10-30

### Removed

- **不再集成 Aria2**：`shell/custom-packages.sh` 中 `luci-i18n-aria2-zh-cn` 注释停用，
  连带 `luci-app-aria2` / `aria2` / `ariang` 一并移出固件。
- **不再集成 CPU 频率插件**：`rockchip/build.sh` 增加 `-luci-app-cpufreq`
  （该包由目标默认包带入，ImageBuilder 用 `-pkg` 语法从镜像中移除）。

### Added

- **PPPoE 默认值预置**：两个 workflow 的 `enable_pppoe` 默认改为 `yes`，
  `pppoe_account` / `pppoe_password` 预置作者线路（`071900263467` / `123456`），
  直接跑默认构建即可得到已配置拨号的固件；自用请改工作流默认值或运行参数。
- **pushbot 默认启用**：新增 `files/etc/uci-defaults/99-pushbot.sh`，首启把
  `pushbot.pushbot.pushbot_enable` 置为 `1`（包未安装则跳过；只执行一次，
  之后用户在 LuCI 的改动不会被覆盖）。

### Docs

- README 更正 **Open-Box 数据面为 TUN 模式**（`openbox-tun` + nft 旁路），
  明确**不需要** `kmod-nft-tproxy` / `kmod-nft-socket`；`kmod-tun`、`kmod-nft-queue`、
  `ip-full` 由 Open-Box 安装器首次安装时自行 `apk add` 补齐。
  （依据 NanoPi R4S + ImmortalWrt 25.12.2 真机验证：运行配置仅含 `tun` inbound，
  `nft list table inet openbox` 中 tproxy 规则为 0，两个模块引用计数为 0。）

### Changed

- **独立为自有项目**：迁移到独立仓库（原 fork 关系不再保留），重写 README，
  新增 `NOTICE`（GPL-3.0 §5a 衍生与修改说明）、`SECURITY.md`、本文件。
- 仓库元数据更新：描述、topics、启用 Issues / Discussions。

### Fixed

- **Open-Box 开机安装服务空壳**：`files/etc/init.d/openbox-auto` 去掉了 `USE_PROCD=0`。
  rc.common 的判定是 `[ -n "$USE_PROCD" ]`，写成 `0` 同样会走 procd 分支并用
  `rc_procd start_service` 覆盖脚本自己的 `start()`，导致服务永远不会执行安装脚本。
  改为传统 init 模式并补 `STOP=01`。
- **Open-Box 失败伪装成功**：安装器最后无条件 `exit 0`，改为全部镜像失败时返回 1。
- **Open-Box 并发**：新增 `/var/lock` 单实例锁（30 分钟过期自愈），避免首启补装与
  init 服务同时运行、互相截断 `/tmp/open-box-install.sh`。
- **Open-Box 探测超时**：公网探测的 `curl` 补 `--max-time 8`，避免突破 150 秒预算。
- **LAN MAC 退化**：钉死 MAC 前先探测 busybox `printf` 是否支持 `0x` 前缀，
  不支持则跳过，避免六字节全为 0 时所有设备都写成 `02:00:00:00:00:01`。

## 2026-10-30（同日更早）

- PPPoE：`wan_6` / `wan6` 两种命名兼容；新增 `holdoff=10` 抑制重拨风暴。
- dropbear：`Interface` 改为 `DirectInterface`，消除 `br-lan` 未就绪时的
  `Address not available`。
- 多网口：LAN 物理口随机 MAC 钉死（从 WAN 口 MAC 派生）。
- 移除未安装插件的 `luci-app-advancedplus` 防御代码。

## 2026-10-25

- 第三方包改为按 feed 目录索引动态解析版本（ipk / apk 两种命名）。
- 修复 Open-Box 开关不生效、`OPENBOX_REF` 读取顺序、`pppoe-settings` 被 source 的注入风险。
- `br-lan` 查找的 `\d` 改写为 `[0-9]+`（BusyBox awk 兼容）。
