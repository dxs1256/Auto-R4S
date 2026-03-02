#!/bin/sh
# 99-custom.sh - 适用于 NanoPi R4S 的首次开机初始化脚本

LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE
echo "Detected Device: FriendlyARM NanoPi R4S" >> $LOGFILE

# 1. 设置主机名映射，解决部分安卓原生 TV 无法联网/时间不同步的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 2. 检查由 build24.sh 动态生成的 pppoe-settings 配置文件
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ -f "$SETTINGS_FILE" ]; then
    . "$SETTINGS_FILE"
else
    echo "PPPoE settings file not found. Skipping." >> $LOGFILE
fi

# 3. 自动获取 R4S 的物理网口列表
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        ifnames="$ifnames $iface_name"
    fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')

echo "Detected physical interfaces: $ifnames" >> $LOGFILE

# 第一个网口为 WAN，第二个网口为 LAN
wan_ifname=$(echo "$ifnames" | awk '{print $1}')
lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)
echo "Using mapping: WAN=$wan_ifname LAN=$lan_ifnames" >> $LOGFILE

# 4. 写入网络配置
# ================= WAN 口配置 =================
uci set network.wan=interface
uci set network.wan.device="$wan_ifname"
uci set network.wan.proto='dhcp'

uci set network.wan6=interface
uci set network.wan6.device="$wan_ifname"
uci set network.wan6.proto='dhcpv6'

# 判断 Github Actions 传进来的 PPPoE 设置
echo "enable_pppoe value: $enable_pppoe" >> $LOGFILE
if [ "$enable_pppoe" = "yes" ]; then
    echo "PPPoE enabled, configuring..." >> $LOGFILE
    uci set network.wan.proto='pppoe'
    uci set network.wan.username="$pppoe_account"
    uci set network.wan.password="$pppoe_password"
    uci set network.wan.peerdns='1'
    uci set network.wan.auto='1'
    uci set network.wan6.proto='none' # PPPoE下关闭独立的 DHCPv6
    echo "PPPoE config done." >> $LOGFILE
fi

# ================= LAN 口配置 =================
# 查找 br-lan 设备并绑定正确的 LAN 物理网口
section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
if [ -z "$section" ]; then
    echo "error：cannot find device 'br-lan'." >> $LOGFILE
else
    uci -q delete "network.$section.ports"
    for port in $lan_ifnames; do
        uci add_list "network.$section.ports"="$port"
    done
    echo "Updated br-lan ports: $lan_ifnames" >> $LOGFILE
fi

uci set network.lan.proto='static'
uci set network.lan.netmask='255.255.255.0'

# 读取 Github Actions 填写的管理后台 IP
IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
if [ -f "$IP_VALUE_FILE" ]; then
    CUSTOM_IP=$(cat "$IP_VALUE_FILE")
    uci set network.lan.ipaddr="$CUSTOM_IP"
    echo "Custom router IP applied: $CUSTOM_IP" >> $LOGFILE
else
    uci set network.lan.ipaddr='192.168.10.1'
    echo "Default router IP applied: 192.168.10.1" >> $LOGFILE
fi

uci commit network

# 5. Docker 专属防火墙规则 (若安装了 Docker 则自动执行，扩大子网范围防止容器断网)
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..." >> $LOGFILE
    FW_FILE="/etc/config/firewall"

    uci -q delete firewall.docker
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci -q get firewall.@forwarding[$idx].src)
        dest=$(uci -q get firewall.@forwarding[$idx].dest)
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            uci delete firewall.@forwarding[$idx]
        fi
    done
    uci commit firewall

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
fi

# 6. 自定义固件作者信息 (展示在系统概览页)
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by Github Actions"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

echo "99-custom.sh execution completed." >> $LOGFILE
exit 0
