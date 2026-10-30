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
        # 拨号失败后等待 holdoff 秒再重连，避免每 3 秒一次的疯狂重拨放大对局端 RADIUS 的冲击
        uci set network.wan.holdoff='10'
        echo "PPPoE config done." >>$LOGFILE
    else
        echo "PPPoE not enabled." >>$LOGFILE
    fi

    # ============ 固定 LAN 物理口 MAC（可选增强） ============
    # R4S 的 PCIe RTL8168/8111 网卡无 EEPROM，内核每次启动随机生成 MAC
    #（日志: r8169 ... can't read MAC address, setting random one）。
    # 从 WAN(eth0, 板载 GMAC 稳定 MAC) 派生一个 LAN MAC：
    #   置本地管理位(0x02) + 末字节+1，永久固定且不与本机其他口冲突。
    # 仅当 LAN 口当前 MAC 命中"随机生成"特征（本地管理位被置位）时才执行。
    # 不同 busybox 版本对 printf '%d' 的 0x 前缀支持不一致；若不支持，
    # 六个字节会全部解析成 0，所有设备都会写成 02:00:00:00:00:01（多台同网段会冲突）。
    # 这里先做能力探测，不支持就跳过 MAC 钉死（保持内核随机 MAC，至少不会撞车）。
    mac_hex_ok="no"
    if [ "$(printf '%d' 0x0a 2>/dev/null)" = "10" ]; then mac_hex_ok="yes"; fi
    lan_phy=""
    for _i in $lan_ifnames; do
        lan_phy="$_i"
        break
    done
    if [ -n "$lan_phy" ] && [ "$mac_hex_ok" = "yes" ]; then
        wan_mac=$(cat "/sys/class/net/$wan_ifname/address" 2>/dev/null)
        lan_mac=$(cat "/sys/class/net/$lan_phy/address" 2>/dev/null)
        lan_b1=$(printf '%d' "0x${lan_mac%%:*}" 2>/dev/null)
        if [ -n "$lan_b1" ] && [ $((lan_b1 & 0x02)) -ne 0 ] && [ $((lan_b1 & 0x01)) -eq 0 ] && \
           echo "$wan_mac" | grep -qE '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$' && \
           [ "$wan_mac" != "00:00:00:00:00:00" ] && [ "$wan_mac" != "ff:ff:ff:ff:ff:ff" ]; then
            # 本地管理位已置位 => 是内核随机生成的 MAC，需要钉死
            o1=$(printf '%d' "0x${wan_mac%%:*}")
            o2=$(printf '%d' "0x$(echo "$wan_mac" | cut -d: -f2)")
            o3=$(printf '%d' "0x$(echo "$wan_mac" | cut -d: -f3)")
            o4=$(printf '%d' "0x$(echo "$wan_mac" | cut -d: -f4)")
            o5=$(printf '%d' "0x$(echo "$wan_mac" | cut -d: -f5)")
            o6=$(printf '%d' "0x${wan_mac##*:}")
            o1=$(( (o1 | 0x02) & 0xfe ))
            o6=$(( (o6 + 1) & 0xff ))
            new_mac=$(printf '%02x:%02x:%02x:%02x:%02x:%02x' "$o1" "$o2" "$o3" "$o4" "$o5" "$o6")
            # 持久化：找到该物理设备已有的 device section 则改 macaddr，否则新建
            devsec=$(uci show network | grep -E "^network\.[^.=]+\.name='${lan_phy}'$" | head -n1 | cut -d. -f2)
            if [ -n "$devsec" ]; then
                uci set network.$devsec.macaddr="$new_mac"
            else
                uci set network.lan_phy=device
                uci set network.lan_phy.name="$lan_phy"
                uci set network.lan_phy.macaddr="$new_mac"
            fi
            echo "LAN MAC pinned: $lan_phy $lan_mac -> $new_mac (derived from $wan_ifname $wan_mac)" >>$LOGFILE
        fi
    fi

    uci commit network
fi

# ============ 彻底关闭 IPv6 ============
# 为什么不能只改 wan6：PPPoE 的 IPv6 子接口 wan_6 是协议层在 wan.ipv6=1 时动态创建的，
# 把静态 wan6 设成 proto=none 并不能阻止它（实测 25.12.2 上仍有全球地址、/60 PD、
# wan_6 反复 up/down）。真正关掉需要把 wan 的 ipv6 开关置 0，并停掉 LAN 侧的
# RA / DHCPv6 / NDP，否则客户端仍会被通告 IPv6 前缀。
if uci -q get network.wan >/dev/null 2>&1; then
    uci set network.wan.ipv6='0'
fi
uci -q delete network.wan6
uci set dhcp.lan.ra='disabled'
uci set dhcp.lan.dhcpv6='disabled'
uci set dhcp.lan.ndp='disabled'
uci commit network
uci commit dhcp
echo "IPv6: disabled (wan.ipv6=0, ra/dhcpv6/ndp disabled)" >>$LOGFILE

# 仅允许从 LAN 访问 SSH，避免 WAN 无密码登录（如需外网 SSH，请改为 'wan' 并先设 root 密码）
# 24.10 的 dropbear：option Interface 会先解析接口 IP 再绑定，br-lan 未就绪时报
# 'Address not available'（日志实锤 16:04:04 首发失败）。改用 DirectInterface
#（dropbear 2.x -B / SO_BINDTODEVICE 直接绑网络设备，不依赖地址解析），仍保持仅 LAN 可达。
uci -q delete dropbear.@dropbear[0].Interface
uci -q delete dropbear.@dropbear[0].DirectInterface
uci set dropbear.@dropbear[0].DirectInterface='lan'
uci commit

# 修正 luci-app-dockerman 菜单显示名：immortalwrt 官方 JS 版 menu.d 的 title 原文就叫
# "Dockerman JS"（非装错包），此处改为用户熟悉的 "Docker"
if [ -f /usr/share/luci/menu.d/luci-app-dockerman.json ]; then
    sed -i 's/"title": "Dockerman JS"/"title": "Docker"/' /usr/share/luci/menu.d/luci-app-dockerman.json
    echo "dockerman menu title fixed" >>$LOGFILE
fi

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by Auto-R4S"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

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



# ============= Open-Box 自动安装（每次开机自动执行，替代原"仅首启尝试"方案） =============
# 背景：原方案在 uci-defaults 阶段执行，此时网络通常未就绪（wan 未拨号/未拿 IP），
# 且 uci-defaults 只跑一次、跑完即删，导致下载失败后永远不再自动尝试。
# 方案：独立 init 服务 openbox-auto（START=90，开机网络就绪后执行 /etc/openbox-install.sh；
# 脚本内含网络等待 + 多镜像容灾 + SHA256 校验；装好后 /opt/open-box/.installed 存在则秒退）。
if [ -f /etc/init.d/openbox-auto ]; then
    chmod +x /etc/init.d/openbox-auto
    /etc/rc.common /etc/init.d/openbox-auto enable
    echo "Open-Box: 开机自动安装服务 openbox-auto 已启用" >>$LOGFILE
fi
# ============= IPv6 兜底服务 =============
# 首启在本脚本里设过 wan.ipv6=0 与 dhcp.lan 的 ra/dhcpv6/ndp=disabled，但实测 24.10.6
# 首启后 dhcp.lan 会被后续环节改回 server。ipv6-off 在网络/odhcpd 起来之后（START=98）
# 每次开机再强制一次。
if [ -f /etc/init.d/ipv6-off ]; then
    chmod +x /etc/init.d/ipv6-off
    /etc/rc.common /etc/init.d/ipv6-off enable
    echo "IPv6: 兜底服务 ipv6-off 已启用" >>$LOGFILE
fi

# 首启若网络已就绪则立即补装一次（后台，不阻塞首启流程）
if [ -f /etc/openbox-install.sh ] && [ ! -f /opt/open-box/.installed ]; then
    sh /etc/openbox-install.sh >/dev/null 2>&1 &
    echo "Open-Box: 首启后台补装已触发" >>$LOGFILE
fi

exit 0
