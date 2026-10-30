# [新手指导](https://github.com/wukongdaily/AutoBuildImmortalWrt/wiki) 👈🏻
# Auto-R4S

**⚠️ 重要声明**

> **本项目为个人独立维护的第三方项目(脚本)，与 ImmortalWrt 官方没有关联。** <br>
> **项目中使用了 ImmortalWrt 官方 ImageBuilder 工具打包生成固件。<br>
> 但用户自行定制产生的任何 bug，均不代表 ImmortalWrt 官方固件的 bug**<br>
> **为了不给 ImmortalWrt 上游维护者增加额外负担和麻烦，所有相关问题请勿在 ImmortalWrt 群内反馈**。  <br>
> **建议各位在本项目 [Discussions](https://github.com/wukongdaily/ImmortalWrt-ImageBuilder/discussions) 中提问或讨论**


---

[![GitHub](https://img.shields.io/github/license/wukongdaily/AutoBuildImmortalWrt.svg?label=LICENSE&logo=github&logoColor=%20)](https://github.com/wukongdaily/AutoBuildImmortalWrt/blob/master/LICENSE)
![GitHub Stars](https://img.shields.io/github/stars/wukongdaily/AutoBuildImmortalWrt.svg?style=flat&logo=appveyor&label=Stars&logo=github)
![GitHub Forks](https://img.shields.io/github/forks/wukongdaily/AutoBuildImmortalWrt.svg?style=flat&logo=appveyor&label=Forks&logo=github)

## 🤔 这是什么？
基于 CI 的 ImageBuilder 工作流，用于自动化构建 ImmortalWrt 固件。
> 1、支持自定义固件大小 默认 3G（可选 1G-4G，推荐 1G-2G；更大需求可用扩容插件）<br>
> 2、支持可选预安装docker（可选）支持在UI上勾选是否集成商店 （24.10.6以下）<br>
> 3、支持按需增加[第三方软件](https://github.com/wukongdaily/store/blob/master/README.md)  如何集成 https://github.com/wukongdaily/AutoBuildImmortalWrt/discussions/209 <br>
> 4、点击这里查看👉🏻[全部支持的机型列表](https://github.com/wukongdaily/AutoBuildImmortalWrt/blob/master/SUPPORT.md) 👈🏻<br>
> 5、在UI上 新增luci版本的可选项，默认最新版25.12.x https://github.com/wukongdaily/AutoBuildImmortalWrt/discussions/426<br>
> 6、支持设置管理地址的ip 比如192.168.1.1 这里强调 这项功能仅针对多网口机型 单网口的逻辑还是自动获取ip模式（dhcp）无固定ip<br>
> 7、对于[插件追新的用户 建议前往run项目 下载run后 ](https://github.com/wukongdaily/RunFilesBuilder/discussions/41)用命令sh xx.run 覆盖安装 <br>
> 8、支持24.10.x 、25.12.x 等版本 （Rockchip 瑞芯微平台，机型为友好NanoPi R4S）

## [基本用法步骤](https://github.com/wukongdaily/AutoBuildImmortalWrt/wiki) 👈🏻
1、fork本项目<br>
2、在fork后的项目中 点击【action】 找到需要的工作流后 run-workflow<br>

## 🔐 安全须知（必读）

- **root 密码**：固件默认 **root 无密码**，首次登录 LuCI / SSH 必须立即设置强密码。
- **防火墙**：WAN 口入站默认 **拒绝（REJECT）**，SSH（dropbear）仅监听 **LAN**，避免公网无密码登录。如确需从外网管理，请在「网络 → 防火墙 → WAN 入站」改为允许，并务必先设置 root 密码。
- **Open-Box 自动安装**：固件**每次开机**都会在网络就绪后尝试安装 Open-Box 代理——`/etc/init.d/openbox-auto`（START=90）调用 `files/etc/openbox-install.sh`，先等默认路由与公网可达（最多约 150 秒），再走多镜像容灾；装好写 `/opt/open-box/.installed` 后不再重试，失败则下次开机继续，日志见 `/etc/config/openbox-install.log`。可在工作流中通过 `enable_openbox=no` 关闭。**完整性提示**：默认只做基础检查（体积 + shebang），且 `.sha256` 与脚本来自同一镜像，默认不构成有效校验；如需强制校验，请在 `rockchip/build.sh` 生成 `openbox-settings` 时填入 `OPENBOX_EXPECTED_SHA256`（可经同名环境变量传入）。
- **PPPoE 凭据**：宽带账号/密码以明文写入固件内 `/etc/config/pppoe-settings`。运营商账号与物理线路绑定，泄露通常无法被他人直接使用；若不想固件内留存凭据，可关闭 PPPoE 后自行在后台配置。启用 PPPoE 时账号/密码为必填（仅校验非空，不限制强度）。

## 如何查询imm仓库内有哪些插件
https://mirrors.sjtug.sjtu.edu.cn/immortalwrt/releases/24.10.4/packages/aarch64_generic/luci/
## 如何查询imm仓库外目前可以集成哪些插件
https://github.com/wukongdaily/store
> 具体方法 https://github.com/wukongdaily/AutoBuildImmortalWrt/discussions/209
## 【视频教程】如何集成第三方插件？
https://www.youtube.com/watch?v=KN6AJYV1hBI <br>
https://www.youtube.com/watch?v=7i6BQeitUtE

## 旁路由的用户必读
近期不少用户修改配置文件中的默认ip地址，误认为这个工作流可以直接设置旁路ip。这是巨大的误解，这样设置就乱套了。<br>
旁路的逻辑应该是单网口模式。根据下面的固件属性可知。单网口默认采取`dhcp模式`，用户应当自行在上一级路由器查看给imm路由器分配的ip地址。
然后通过该ip来访问imm后台页面，在imm后台页面中，根据自己主路由的网段 自行配置旁路的ip地址。

## 正常路由模式必读
所谓正常的路由模式 就是指多网口用户，多网口的意思就是2个或者2个以上网口的情况。<br>
一般wan用于拨号或者自动获取ip <br>
而其他lan一般是给其他设备分配dhcp<br>
这种情况下 你可以修改路由器的默认ip  `192.168.1.1` 比如你可以修改为`192.168.80.1 ` 诸如此类。<br>
没错，修改此ip 无非就是为了避免跟光猫或者跟家庭中的其他路由器网段冲突。大多数用户，无需更改。

## 该固件默认属性？(必读)
- 该固件刷入【单网口设备】默认采用DHCP模式,自动获得ip。类似NAS的做法
- 该固件刷入【多网口设备】默认WAN口采用DHCP模式，LAN 口ip为  `192.168.1.1` <br>其中eth0为WAN 其余网口均为LAN
- 若用户在工作流中勾选了拨号信息 则WAN口模式为pppoe拨号模式。
- 建议拨号用户使用之前重启一次光猫。
- 综合上述特点，【单网口设备】应该先接路由器，先在上级路由器查看一下它的ip 再访问。
- 上述特点 你都可以通过 `99-custom.sh` 配置和调整

## 特别说明
本项目构建的固件 **WAN 口防火墙入站默认已为「拒绝（REJECT）」**（安全优先），SSH 仅监听 LAN。
如你确实需要开放 WAN 入站（例如从外网管理），请到 网络——防火墙—— WAN 的入站 选择「允许」并保存应用；**但务必先设置 root 强密码**。更多讨论[ 请参考这个话题](https://github.com/wukongdaily/AutoBuildImmortalWrt/discussions/341)
<img width="3860" height="870" alt="image" src="https://github.com/user-attachments/assets/d826bccd-f0df-4d4a-877d-b711b81fcf1a" />
同时此项设置的相关代码详见 `files/etc/uci-defaults/99-custom.sh` 行首

## ❤️其它GitHub Action项目推荐🌟 （建议收藏）⬇️
- ### [一键生成run插件] 🆕
- https://github.com/wukongdaily/RunFilesBuilder<br>
- ### [一键生成docker离线镜像] 🆕
- https://github.com/wukongdaily/DockerTarBuilder<br>
- ### [OpenWrt/Armbian IMG安装器ISO] 🆕
- https://github.com/wukongdaily/img-installer


## ❤️如何构建docker版ImmortalWrt（建议收藏）⬇️
https://wkdaily.cpolar.cn/15
# 🎉鸣谢

感谢以下项目与作者对本项目的贡献与灵感 ❤️

<div align="left">

<a href="https://github.com/immortalwrt"><img src="https://avatars.githubusercontent.com/immortalwrt?v=4&s=80" width="80" height="80" alt="immortalwrt" /></a>
<a href="https://github.com/Openwrt-Passwall"><img src="https://avatars.githubusercontent.com/Openwrt-Passwall?v=4&s=80" width="80" height="80" alt="Openwrt-Passwall" /></a>
<a href="https://github.com/sirpdboy"><img src="https://avatars.githubusercontent.com/sirpdboy?v=4&s=80" width="80" height="80" alt="sirpdboy" /></a>
<a href="https://github.com/ophub"><img src="https://avatars.githubusercontent.com/ophub?v=4&s=80" width="80" height="80" alt="ophub" /></a>
<a href="https://github.com/linkease"><img src="https://avatars.githubusercontent.com/linkease?v=4&s=80" width="80" height="80" alt="linkease" /></a>

<a href="https://github.com/coolsnowwolf"><img src="https://avatars.githubusercontent.com/coolsnowwolf?v=4&s=80" width="80" height="80" alt="coolsnowwolf" /></a>
<a href="https://github.com/stackia"><img src="https://avatars.githubusercontent.com/stackia?v=4&s=80" width="80" height="80" alt="stackia" /></a>
<a href="https://github.com/kiddin9"><img src="https://avatars.githubusercontent.com/kiddin9?v=4&s=80" width="80" height="80" alt="kiddin9" /></a>
<a href="https://github.com/sbwml"><img src="https://avatars.githubusercontent.com/sbwml?v=4&s=80" width="80" height="80" alt="sbwml" /></a>
<a href="https://github.com/kenzok8"><img src="https://avatars.githubusercontent.com/kenzok8?v=4&s=80" width="80" height="80" alt="kenzok8" /></a>

<a href="https://github.com/timsaya"><img src="https://avatars.githubusercontent.com/timsaya?v=4&s=80" width="80" height="80" alt="timsaya" /></a>
<a href="https://github.com/AdguardTeam"><img src="https://avatars.githubusercontent.com/AdguardTeam?v=4&s=80" width="80" height="80" alt="AdguardTeam" /></a>
<a href="https://github.com/Thaolga"><img src="https://avatars.githubusercontent.com/Thaolga?v=4&s=80" width="80" height="80" alt="Thaolga" /></a>
<a href="https://github.com/eamonxg"><img src="https://avatars.githubusercontent.com/eamonxg?v=4&s=80" width="80" height="80" alt="eamonxg" /></a>
<a href="https://github.com/nikkinikki-org"><img src="https://avatars.githubusercontent.com/nikkinikki-org?v=4&s=80" width="80" height="80" alt="nikkinikki-org" /></a>

<a href="https://github.com/gdy666"><img src="https://avatars.githubusercontent.com/gdy666?v=4&s=80" width="80" height="80" alt="gdy666" /></a>
<a href="https://github.com/lwb1978"><img src="https://avatars.githubusercontent.com/lwb1978?v=4&s=80" width="80" height="80" alt="lwb1978" /></a>
<a href="https://github.com/Tokisaki-Galaxy"><img src="https://avatars.githubusercontent.com/Tokisaki-Galaxy?v=4&s=80" width="80" height="80" alt="Tokisaki-Galaxy" /></a>
<a href="https://github.com/QiuSimons"><img src="https://avatars.githubusercontent.com/QiuSimons?v=4&s=80" width="80" height="80" alt="QiuSimons" /></a>
<a href="https://xz.vumstar.com/"><img src="https://xz.vumstar.com/static/img/logo.png" width="80" height="80" alt="wukongdaily" /></a>

</div>

## ❤️赞助作者 ⬇️⬇️

<a href="https://wkdaily.cpolar.top/01" target="_blank">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png"
       alt="Buy Me A Coffee"
       style="width:15%; height:auto;">
</a>
