#!/bin/sh
# 首启默认启用 pushbot（luci-app-pushbot，第三方包，可能未安装 —— 未装则直接跳过）
# 只执行一次：uci-defaults 脚本返回 0 会被删除，之后用户在 LuCI 改的开关不会再被覆盖。
[ -x /etc/init.d/pushbot ] || exit 0
[ -f /etc/config/pushbot ] || exit 0
uci -q get pushbot.pushbot >/dev/null 2>&1 || exit 0

cur=$(uci -q get pushbot.pushbot.pushbot_enable)
[ "$cur" = "1" ] && exit 0

uci set pushbot.pushbot.pushbot_enable='1'
uci commit pushbot
# 本脚本在 S10(boot) 阶段执行，S99pushbot 尚未运行，无需在此 restart
exit 0
