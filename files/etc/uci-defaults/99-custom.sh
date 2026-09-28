#!/bin/sh
# 99-custom.sh 就是immortalwrt固件首次启动时运行的脚本 位于固件内的/etc/uci-defaults/99-custom.sh
# Log file for debugging
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE
# 设置默认防火墙规则，方便单网口虚拟机首次访问 WebUI 
# 因为本项目中 单网口模式是dhcp模式 直接就能上网并且访问web界面 避免新手每次都要修改/etc/config/network中的静态ip
# 当你刷机运行后 都调整好了 你完全可以在web页面自行关闭 wan口防火墙的入站数据
# 具体操作方法：网络——防火墙 在wan的入站数据 下拉选项里选择 拒绝 保存并应用即可。
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 检查配置文件pppoe-settings是否存在 该文件由build.sh动态生成
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >>$LOGFILE
else
    # 读取pppoe信息($enable_pppoe、$pppoe_account、$pppoe_password)
    . "$SETTINGS_FILE"
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
    section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
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

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
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


# ============= Open-Box 自动安装（多镜像容灾） =============
# 设计：依次探测每个镜像前缀，选第一个能拿 install.sh 且 sha256 内容正确的；
# 全挂则 die，不动 /opt/open-box。装包失败（没写 /opt）再试下一个，直到成功或全用完。
OPENBOX_REPO="liandu2024/Open-Box"
OPENBOX_INSTALL_SH="main/scripts/install.sh"
OPENBOX_INSTALLED="/opt/open-box/.installed"
OPENBOX_TMP="/tmp/open-box-install.sh"
LOGFILE="/etc/config/uci-defaults-log.txt"
# 镜像前缀列表：第一个是 Open-Box 官方内置的（上游 BUILTIN_MIRRORS 第一个可用的），
# 后面是常见加速站。顺序代表优先级，靠前的优先被选中。
OPENBOX_MIRRORS="
gh-proxy.com
ghfast.top
gh.dpik.top
ghproxy.homeboyc.cn
"

ob_installed_check() { [ -d "/opt/open-box" ] && [ -f "$OPENBOX_INSTALLED" ] && echo ok; }

# 探测单个镜像：拿 install.sh 小文件，验证开头是 #!/bin/sh 且大小 > 1000 字节。
ob_probe_mirror() {
  m="$1"
  base="https://$m"
  out=$(curl -fsSL --connect-timeout 6 --max-time 15 \
        "$base/raw.githubusercontent.com/$OPENBOX_REPO/$OPENBOX_INSTALL_SH" 2>/dev/null) || return 1
  sz=${#out}
  [ "$sz" -lt 1000 ] && return 1
  case "$out" in
    "#!/bin/sh"*|"#!/bin/sh"*) : ;;
    *) return 1 ;;
  esac
  echo "$m"
  return 0
}

# 下载并执行 install.sh --mirror <m>，返回 0 成功 / 1 失败（可能网络或校验失败）。
ob_try_install() {
  m="$1"
  echo "Open-Box: 尝试通过镜像 $m 下载安装..." >> "$LOGFILE"
  # 把 install.sh 内容写到本地临时文件（避免 curl | sh 这种 stdin 读法对 umask 的影响）
  case "$m" in
    http://*|https://*) base="$m" ;;
    *) base="https://$m" ;;
  esac
  curl -fsSL --connect-timeout 8 --max-time 30 \
       "$base/raw.githubusercontent.com/$OPENBOX_REPO/$OPENBOX_INSTALL_SH" -o "$OPENBOX_TMP" 2>>"$LOGFILE" \
    || { echo "Open-Box: 镜像 $m 下载 install.sh 失败" >> "$LOGFILE"; return 1; }

  chmod +x "$OPENBOX_TMP"
  sh "$OPENBOX_TMP" --mirror "$m" >> "$LOGFILE" 2>&1
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "Open-Box: 镜像 $m 安装失败 (rc=$rc)" >> "$LOGFILE"
    return 1
  fi
  if [ -d "/opt/open-box" ]; then
    touch "$OPENBOX_INSTALLED"
    echo "Open-Box: 镜像 $m 安装完成" >> "$LOGFILE"
    return 0
  fi
  echo "Open-Box: 镜像 $m 执行成功但 /opt/open-box 不存在，视为失败" >> "$LOGFILE"
  return 1
}

if [ ! -f "$OPENBOX_INSTALLED" ]; then
  echo "检测到 Open-Box 未安装，开始自动安装（多镜像容灾）..." >> "$LOGFILE"

  ok=0
  for m in $OPENBOX_MIRRORS; do
    echo "Open-Box: 探测镜像 $m ..." >> "$LOGFILE"
    if ob_probe_mirror "$m"; then
      echo "Open-Box: 镜像 $m 可用，开始安装" >> "$LOGFILE"
      if ob_try_install "$m"; then
        ok=1
        break
      fi
    else
      echo "Open-Box: 镜像 $m 不可用，跳过" >> "$LOGFILE"
    fi
  done

  if [ "$ok" -eq 0 ]; then
    echo "Open-Box: 所有内置镜像全部不可用或安装失败" >> "$LOGFILE"
    echo "Open-Box: 请用 update.sh / 手动下载 install.sh 安装，或把可用镜像前缀加入 OPENBOX_MIRRORS" >> "$LOGFILE"
  fi
else
  echo "Open-Box 已安装，跳过" >> "$LOGFILE"
fi
exit 0
