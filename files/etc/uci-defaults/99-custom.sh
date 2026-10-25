#!/bin/sh
# 99-custom.sh 就是immortalwrt固件首次启动时运行的脚本 位于固件内的/etc/uci-defaults/99-custom.sh
# Log file for debugging
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE
# 默认安全策略：WAN 入站【拒绝】(REJECT)。
# 说明：早期版本为方便单网口虚拟机首次访问而默认 ACCEPT，存在「root 无密码 + WAN 暴露」被公网登录的风险。
# 现已默认拒绝。如确需从外网管理，请在「网络 → 防火墙 → WAN 入站」改为允许，并务必先设置 root 密码。
uci -q set firewall.wan.input='REJECT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 检查配置文件pppoe-settings是否存在 该文件由build.sh动态生成
# 安全说明：这里刻意【不使用 . 直接 source 该文件】。
# 宽带密码可能含 $() / 反引号 / 引号 / 空格等特殊字符，直接 source 会被 shell 当作命令执行或截断，
# 轻则配置损坏，重则首启时执行任意命令。改为按行取值（只做文本提取，不做 shell 解析）。
SETTINGS_FILE="/etc/config/pppoe-settings"
enable_pppoe="no"
pppoe_account=""
pppoe_password=""
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >>$LOGFILE
else
    # 读取pppoe信息($enable_pppoe、$pppoe_account、$pppoe_password)
    # 取 "key=" 之后到行尾的原样文本
    enable_pppoe=$(sed -n 's/^enable_pppoe=//p' "$SETTINGS_FILE" | tail -n1)
    pppoe_account=$(sed -n 's/^pppoe_account=//p' "$SETTINGS_FILE" | tail -n1)
    pppoe_password=$(sed -n 's/^pppoe_password=//p' "$SETTINGS_FILE" | tail -n1)
    echo "PPPoE settings loaded (enable=$enable_pppoe)." >>$LOGFILE
fi

# 1. 先获取所有物理接口列表
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        ifnames="$ifnames $iface_name"
    fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')

count=$(echo "$ifnames" | wc -w)
echo "Detected physical interfaces: $ifnames" >>$LOGFILE
echo "Interface count: $count" >>$LOGFILE

# 2. 根据板子型号映射WAN和LAN接口
board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
echo "Board detected: $board_name" >>$LOGFILE

wan_ifname=""
lan_ifnames=""
# 默认第一个接口为WAN，其余为LAN
wan_ifname=$(echo "$ifnames" | awk '{print $1}')
lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)
echo "Using default mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>"$LOGFILE"

# 3. 配置网络
if [ "$count" -eq 1 ]; then
    # 单网口设备，DHCP模式
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr
    uci delete network.lan.netmask
    uci delete network.lan.gateway
    uci delete network.lan.dns
    uci commit network
elif [ "$count" -gt 1 ]; then
    # 多网口设备配置
    # 配置WAN
    uci set network.wan=interface
    uci set network.wan.device="$wan_ifname"
    uci set network.wan.proto='dhcp'

    # 配置WAN6
    uci set network.wan6=interface
    uci set network.wan6.device="$wan_ifname"
    uci set network.wan6.proto='dhcpv6'

    # 查找 br-lan 设备 section
    # 注意：\\d 不是 POSIX awk 正则，BusyBox awk 下会当字面 'd'，故改用 [0-9]+
    section=$(uci show network | awk -F '[.=]' '/\.@?device\[[0-9]+\]\.name=.br-lan.$/ {print $2; exit}')
    if [ -z "$section" ]; then
        echo "error：cannot find device 'br-lan'." >>$LOGFILE
    else
        # 删除原有ports
        uci -q delete "network.$section.ports"
        # 添加LAN接口端口
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports"="$port"
        done
        echo "Updated br-lan ports: $lan_ifnames" >>$LOGFILE
    fi

    # LAN口设置静态IP
    uci set network.lan.proto='static'
    # 多网口设备 支持修改为别的管理后台地址 在Github Action 的UI上自行输入即可 
    uci set network.lan.netmask='255.255.255.0'
    # 设置路由器管理后台地址
    IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
    if [ -f "$IP_VALUE_FILE" ]; then
        CUSTOM_IP=$(cat "$IP_VALUE_FILE")
        # 用户在UI上设置的路由器后台管理地址
        uci set network.lan.ipaddr=$CUSTOM_IP
        echo "custom router ip is $CUSTOM_IP" >> $LOGFILE
    else
        uci set network.lan.ipaddr='192.168.1.1'
        echo "default router ip is 192.168.1.1" >> $LOGFILE
    fi

    # PPPoE设置
    echo "enable_pppoe value: $enable_pppoe" >>$LOGFILE
    if [ "$enable_pppoe" = "yes" ]; then
        echo "PPPoE enabled, configuring..." >>$LOGFILE
        uci set network.wan.proto='pppoe'
        uci set network.wan.username="$pppoe_account"
        uci set network.wan.password="$pppoe_password"
        uci set network.wan.peerdns='1'
        uci set network.wan.auto='1'
        uci set network.wan6.proto='none'
        echo "PPPoE config done." >>$LOGFILE
    else
        echo "PPPoE not enabled." >>$LOGFILE
    fi

    uci commit network
fi

# 仅允许从 LAN 访问 SSH，避免 WAN 无密码登录（如需外网 SSH，请改为 'wan' 并先设 root 密码）
uci set dropbear.@dropbear[0].Interface='lan'
uci commit

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by Auto-R4S"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

# 若luci-app-advancedplus (进阶设置)已安装 则去除zsh的调用 防止命令行报 /usb/bin/zsh: not found的提示
if [ -f /usr/lib/lua/luci/controller/advancedplus.lua ]; then
    sed -i '/\/usr\/bin\/zsh/d' /etc/profile
    sed -i '/\/bin\/zsh/d' /etc/init.d/advancedplus
    sed -i '/\/usr\/bin\/zsh/d' /etc/init.d/advancedplus
    echo "fix ttyd show msg: /usb/bin/zsh: not found" >>$LOGFILE
fi

# 只有安装了 luci-app-quickfile 才执行
if [ -f /usr/bin/quickfile ]; then
    uci set nginx.global.uci_enable='true'
    uci del nginx._lan 2>/dev/null
    uci del nginx._redirect2ssl 2>/dev/null

    uci add nginx server
    uci rename nginx.@server[-1]='_lan'

    uci set nginx._lan.server_name='_lan'
    uci add_list nginx._lan.listen='80 default_server'
    uci add_list nginx._lan.listen='[::]:80 default_server'
    uci add_list nginx._lan.include='conf.d/*.locations'
    uci set nginx._lan.access_log='off; # logd openwrt'

    uci commit nginx
    echo "fix quickfile nginx config" >>$LOGFILE
fi

# 若安装了dockerd 则设置docker的防火墙规则
# 扩大docker涵盖的子网范围 '172.16.0.0/12'
# 方便各类docker容器的端口顺利通过防火墙 
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..."
    FW_FILE="/etc/config/firewall"

    # 删除所有名为 docker 的 zone
    uci delete firewall.docker

    # 先获取所有 forwarding 索引，倒序排列删除
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        echo "Checking forwarding index $idx: src=$src dest=$dest"
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            echo "Deleting forwarding @forwarding[$idx]"
            uci delete firewall.@forwarding[$idx]
        fi
    done
    # 提交删除
    uci commit firewall

# 追加新的 zone + forwarding 配置
cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF

else
    echo "未检测到 Docker，跳过防火墙配置。"
fi


# ============= Open-Box 自动安装（可开关 + 多镜像容灾 + SHA256 校验） =============
# 安全设计：
#  - 由构建时生成的 /etc/config/openbox-settings 控制是否安装（ENABLE_OPENBOX），默认 yes。
#  - install.sh 下载后做 SHA256 校验：优先用仓库同路径的 install.sh.sha256 校验和；
#    否则用构建时写入的 OPENBOX_EXPECTED_SHA256；都没有则仅做基础检查并明确告警（仍有供应链风险）。
#  - 全镜像校验/安装失败则不动 /opt/open-box。
# 注意：必须先 source 开关配置，再据此计算 install.sh 路径，否则开关/REF 不生效
OPENBOX_SETTINGS="/etc/config/openbox-settings"
ENABLE_OPENBOX="yes"
OPENBOX_REF="main"
OPENBOX_EXPECTED_SHA256=""
if [ -f "$OPENBOX_SETTINGS" ]; then
  . "$OPENBOX_SETTINGS"
fi

OPENBOX_REPO="liandu2024/Open-Box"
OPENBOX_INSTALL_SH="$OPENBOX_REF/scripts/install.sh"
OPENBOX_INSTALLED="/opt/open-box/.installed"
OPENBOX_TMP="/tmp/open-box-install.sh"
OPENBOX_SHA_TMP="/tmp/open-box-install.sh.sha256"
LOGFILE="/etc/config/uci-defaults-log.txt"

# 镜像前缀列表（优先级从高到低）
OPENBOX_MIRRORS="
gh-proxy.com
ghfast.top
gh.dpik.top
ghproxy.homeboyc.cn
"

ob_verify() {
  f="$1"
  sz=$(wc -c < "$f" 2>/dev/null || echo 0)
  [ "$sz" -lt 1000 ] && { echo "Open-Box: install.sh 体积异常($sz)，拒绝执行" >> "$LOGFILE"; return 1; }
  head -c 100 "$f" | grep -q '^#!.*sh' || { echo "Open-Box: install.sh 头部不是 shell 脚本，拒绝执行" >> "$LOGFILE"; return 1; }

  if [ -s "$OPENBOX_SHA_TMP" ]; then
    exp=$(cat "$OPENBOX_SHA_TMP" | tr -d '[:space:]' | head -c 64)
    act=$(sha256sum "$f" | cut -d' ' -f1)
    if [ "$exp" = "$act" ]; then
      echo "Open-Box: SHA256 校验通过($act)" >> "$LOGFILE"; return 0
    fi
    echo "Open-Box: SHA256 校验失败(期望 $exp 实际 $act)，跳过该镜像" >> "$LOGFILE"; return 1
  fi
  if [ -n "$OPENBOX_EXPECTED_SHA256" ]; then
    act=$(sha256sum "$f" | cut -d' ' -f1)
    if [ "$OPENBOX_EXPECTED_SHA256" = "$act" ]; then
      echo "Open-Box: SHA256 校验通过($act)" >> "$LOGFILE"; return 0
    fi
    echo "Open-Box: SHA256 校验失败(期望 $OPENBOX_EXPECTED_SHA256 实际 $act)，跳过该镜像" >> "$LOGFILE"; return 1
  fi
  echo "Open-Box: ⚠️ 未配置任何 SHA256 校验源，仅做基础检查后执行（存在供应链风险，建议在 openbox-settings 中填入 OPENBOX_EXPECTED_SHA256）" >> "$LOGFILE"
  return 0
}

ob_try_install() {
  m="$1"
  echo "Open-Box: 尝试通过镜像 $m 下载安装..." >> "$LOGFILE"
  case "$m" in
    http://*|https://*) base="$m" ;;
    *) base="https://$m" ;;
  esac
  url="$base/raw.githubusercontent.com/$OPENBOX_REPO/$OPENBOX_INSTALL_SH"
  curl -fsSL --connect-timeout 8 --max-time 30 "$url" -o "$OPENBOX_TMP" 2>>"$LOGFILE" \
    || { echo "Open-Box: 镜像 $m 下载 install.sh 失败" >> "$LOGFILE"; return 1; }
  # 尽力下载官方校验和（可选）
  curl -fsSL --connect-timeout 8 --max-time 30 "$url.sha256" -o "$OPENBOX_SHA_TMP" 2>>"$LOGFILE" || rm -f "$OPENBOX_SHA_TMP"

  ob_verify "$OPENBOX_TMP" || { rm -f "$OPENBOX_TMP" "$OPENBOX_SHA_TMP"; return 1; }

  chmod +x "$OPENBOX_TMP"
  sh "$OPENBOX_TMP" --mirror "$m" >> "$LOGFILE" 2>&1
  rc=$?
  rm -f "$OPENBOX_TMP" "$OPENBOX_SHA_TMP"
  if [ $rc -ne 0 ]; then
    echo "Open-Box: 镜像 $m 安装失败 (rc=$rc)" >> "$LOGFILE"; return 1
  fi
  if [ -d "/opt/open-box" ]; then
    touch "$OPENBOX_INSTALLED"
    echo "Open-Box: 镜像 $m 安装完成" >> "$LOGFILE"; return 0
  fi
  echo "Open-Box: 镜像 $m 执行成功但 /opt/open-box 不存在，视为失败" >> "$LOGFILE"; return 1
}

case "$ENABLE_OPENBOX" in
  yes|true|1)
    if [ -f "$OPENBOX_INSTALLED" ]; then
      echo "Open-Box 已安装，跳过" >> "$LOGFILE"
    else
      echo "检测到 Open-Box 未安装，开始自动安装（多镜像容灾 + 校验）..." >> "$LOGFILE"
      ok=0
      for m in $OPENBOX_MIRRORS; do
        echo "Open-Box: 探测镜像 $m ..." >> "$LOGFILE"
        if ob_try_install "$m"; then ok=1; break; fi
      done
      if [ "$ok" -eq 0 ]; then
        echo "Open-Box: 所有内置镜像均不可用或校验/安装失败" >> "$LOGFILE"
        echo "Open-Box: 可手动下载 install.sh 安装，或把可用镜像前缀加入 OPENBOX_MIRRORS" >> "$LOGFILE"
      fi
    fi
    ;;
  *)
    echo "Open-Box 自动安装已关闭（ENABLE_OPENBOX=$ENABLE_OPENBOX）" >> "$LOGFILE"
    ;;
esac
exit 0
