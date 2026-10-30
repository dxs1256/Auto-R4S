#!/bin/sh
# 首启给 dockerd 配置国内 registry 镜像（按优先级依次尝试）
#
# 背景：registry-1.docker.io 在国内容器网络下通常不可达（实测 curl 8s 超时），
# 不配镜像时 docker pull 会一直卡在超时。
#
# 顺序说明：401 响应的是标准镜像站（/v2/ 要求鉴权，属正常），排在前面；
# 302 响应的是跳转型镜像，兼容性略差，排在后面。
#
# 安全提示：这些都是第三方代理，会看到你拉取的镜像名并转发镜像内容；
# 敏感镜像建议改用自建 registry，或从列表里删掉不信任的条目。
[ -x /etc/init.d/dockerd ] || exit 0
uci -q get dockerd.globals >/dev/null 2>&1 || exit 0

changed=0

add_mirror() {
    case "$(uci -q get dockerd.globals.registry_mirrors)" in
        *"$1"*) return 0 ;;
    esac
    uci add_list dockerd.globals.registry_mirrors="$1"
    changed=1
}

add_mirror 'https://docker.1ms.run'
add_mirror 'https://docker.sparkcr.cn'
add_mirror 'https://docker-registry.nmqu.com'
add_mirror 'https://docker.m.daocloud.io'
add_mirror 'https://hub.rat.dev'
add_mirror 'https://docker.hlmirror.com'

[ "$changed" = "1" ] && uci commit dockerd

exit 0
