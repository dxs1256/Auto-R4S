#!/bin/sh
# 首启给 dockerd 配置国内 registry 镜像
# 背景：registry-1.docker.io 在国内容器网络下通常不可达（实测 curl 8s 超时），
# 不配镜像时 docker pull 会一直超时。这里默认加一个可达的加速站。
[ -x /etc/init.d/dockerd ] || exit 0
uci -q get dockerd.globals >/dev/null 2>&1 || exit 0

case "$(uci -q get dockerd.globals.registry_mirrors)" in
    *daocloud*) exit 0 ;;
    *dockerproxy*) exit 0 ;;
esac

uci add_list dockerd.globals.registry_mirrors='https://docker.m.daocloud.io'
uci commit dockerd
exit 0
