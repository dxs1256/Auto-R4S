# Auto-R4S

面向 **FriendlyARM NanoPi R4S**（RK3399，双千兆网口）的 **ImmortalWrt 云端构建器**：把官方 ImageBuilder 跑在 GitHub Actions 上，选几个参数、点一下，约 6 分钟产出可刷写的固件。

> 本项目与 ImmortalWrt 官方、上游模板作者均无隶属关系。
> 衍生自 [`wukongdaily/ImmortalWrt-ImageBuilder`](https://github.com/wukongdaily/ImmortalWrt-ImageBuilder)（GPL-3.0），针对 R4S 单机型重写了构建流水线并做了若干安全加固。来源与修改说明见 [NOTICE](./NOTICE)。

---

## ✨ 特性

- **一条流水线两种包体系**：24.10.x（opkg）与 25.12.x（apk）分别有独立配置与包清单
- **参数化构建**：Luci 版本、根分区大小（1G–4G）、是否集成 Docker、是否配置 PPPoE、是否首启安装 Open-Box、管理地址
- **产物可追溯**：Release 附完整包清单（`firmware-packages.txt`）与插件清单（`Plugin-list.txt`）
- **首启自适应**：自动识别单/多网口，多网口按 `eth0=WAN、其余=LAN` 配置，并可钉死随机 MAC 的 LAN 口
- **默认安全姿态**：WAN 入站 REJECT（发行版默认值）、SSH 只监听 LAN

## 🚀 快速开始

1. 打开本仓库的 **Actions** 页面；
2. 选择 `Auto-R4S Build 24.10.x Rockchip`（或 25.12 版本）；
3. 点 **Run workflow**，按需填写参数（不填即用默认值）；
4. 等待约 6 分钟，到 **Releases** 下载 `*.img.gz`。

刷写后用网线接 LAN 口访问 `http://192.168.1.1`（默认地址，可在构建时改）。

## ⚙️ 构建参数

| 参数 | 取值 | 默认 | 说明 |
|---|---|---|---|
| `luci_version` | 24.10.0–24.10.6 / 25.12.0–25.12.2 | 24.10.6 / 25.12.1 | 对应 ImageBuilder 镜像 tag |
| `profile` | `friendlyarm_nanopi-r4s` | 同左 | 当前仅支持该机型 |
| `custom_router_ip` | 如 `192.168.1.1` | `192.168.1.1` | 仅对**多网口**生效；单网口走 DHCP |
| `rootfs_partsize` | `1G` / `2G` / `3G` / `4G` | `3G` | 根分区大小（MiB） |
| `include_docker` | `yes` / `no` | `yes` | 含 `docker` + `dockerd` + Dockerman 界面 |
| `enable_pppoe` | `yes` / `no` | `no` | 开启后账号密码**明文写入固件** |
| `pppoe_account` / `pppoe_password` | 文本 | 空 | 启用 PPPoE 时必填 |
| `enable_openbox` | `yes` / `no` | `yes` | 是否每次开机尝试安装 Open-Box |

## 📦 产物

| 文件 | 内容 |
|---|---|
| `immortalwrt-<ver>-rockchip-armv8-friendlyarm_nanopi-r4s-squashfs-sysupgrade.img.gz` | 固件镜像 |
| `firmware-packages.txt` | 固件内全部软件包及版本 |
| `Plugin-list.txt` | 仅 LuCI 插件清单 |

## 🧩 固件默认行为

- **网口**：单网口 → LAN 走 DHCP；多网口 → `eth0` 为 WAN（DHCP 或 PPPoE），其余进 `br-lan`，LAN 静态 IP 为上面的管理地址
- **防火墙**：WAN 入站 `REJECT`（发行版默认值，非本项目新增）
- **SSH**：dropbear 仅监听 LAN（`DirectInterface='lan'`）
- **root**：**默认无密码**，首次登录请立即设置
- **DNS**：`time.android.com` 固定解析到 `203.107.6.88`（兼容安卓 TV）
- **Docker**：检测到引擎时追加 `docker` zone（`172.16.0.0/12`）与三条转发规则
- **MAC**：LAN 口若为内核随机生成（本地管理位被置位），从 WAN 口 MAC 派生一个稳定地址
- **Open-Box**：每次开机在网络就绪后后台尝试安装，成功后写 `/opt/open-box/.installed`，失败下次开机继续；日志 `/etc/config/openbox-install.log`
  - 数据面为 **TUN 模式**（`openbox-tun` + nft 旁路），**不需要** `kmod-nft-tproxy` / `kmod-nft-socket`；`kmod-tun`、`kmod-nft-queue`、`ip-full` 由安装器在首次安装时自行 `apk add` 补齐
- **pushbot**：镜像内**默认启用**（首启写入 `pushbot_enable=1`），不需要可在 LuCI「服务 → PushBot」关闭；不装 `wrtbwmon` / `nlbwmon` 时流量统计模块不可用，其余推送正常
- **标识**：`/etc/openwrt_release` 的 `DISTRIB_DESCRIPTION` 改为 `Packaged by Auto-R4S`

## 🔐 安全须知（必读）

1. **PPPoE 凭据会进固件**：`/etc/config/pppoe-settings` 为明文，且固件会发布到公开 Release。不需要就不要开。
2. **Open-Box 默认不校验安装器**：安装脚本从第三方 GitHub 代理下载，默认只做"体积 + shebang"检查，且 `.sha256` 与脚本同源。介意的话把 `enable_openbox` 设为 `no`。
3. **root 无密码**：任何接入 LAN 的设备都能进 LuCI。请第一时间设置强密码。
4. **第三方软件包**：从 `down.dllkids.xyz` 拉取，构建时不做内容校验。

## 🗂 仓库结构

```
.github/workflows/
  build-rockchip-24.10.yml   # 24.10 入口（workflow_dispatch）
  build-rockchip-25.12.yml   # 25.12 入口
  build-reusable.yml         # 公共构建流水线
  clean-workflow.yml         # 清理旧运行记录
arch/arch.conf               # opkg 架构优先级
files/etc/uci-defaults/99-custom.sh   # 首启配置脚本
files/etc/openbox-install.sh          # Open-Box 安装器（等网 + 多镜像 + 幂等）
files/etc/init.d/openbox-auto         # Open-Box 开机服务（START=90）
rockchip/build.sh            # 容器内构建脚本（两套包体系合一）
rockchip/imm.config          # 24.10 ImageBuilder 配置
rockchip/imm25.config        # 25.12 ImageBuilder 配置
shell/custom-packages.sh     # 24.10 包清单
shell/apk-custom-packages.sh # 25.12 包清单
```

## 🔧 构建原理

```
workflow_dispatch
  → 校验参数 → 拉取第三方包（按 feed 索引选最新）
  → docker run immortalwrt/imagebuilder
        └─ 挂载 bin / files / shell / build.sh / .config
        └─ make image PROFILE=… PACKAGES=… FILES=… ROOTFS_PARTSIZE=…
  → 收集 manifest → 生成清单 → 发布 Release
```

首启逻辑不在镜像构建阶段，而在固件内的 `files/etc/uci-defaults/99-custom.sh`：由 `/etc/init.d/boot` 以 `.`（source）方式执行，返回 0 后自动删除（失败会保留到下次启动重试）。

## 📄 许可

[GPL-3.0](./LICENSE)。衍生来源与修改说明见 [NOTICE](./NOTICE)；变更记录见 [CHANGELOG.md](./CHANGELOG.md)。
