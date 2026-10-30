#!/bin/sh
# ============================================================================
# Open-Box 自动安装脚本（独立于 99-custom.sh）
# 触发方式：每次开机由 /etc/init.d/openbox-auto 调用（START=90，网络就绪后）；
#           也可手动执行：sh /etc/openbox-install.sh
# 特性：
#   - 构建时生成的 /etc/config/openbox-settings 控制开关（ENABLE_OPENBOX），默认 yes
#   - 网络就绪等待：默认路由出现 + 公网可达（最长约 150 秒，失败则退出，下次开机重试）
#   - 多镜像容灾 + SHA256 校验（优先仓库同路径 .sha256，其次 openbox-settings 中的
#     OPENBOX_EXPECTED_SHA256，都没有则仅做基础检查并明确告警）
#   - 幂等：/opt/open-box/.installed 存在即秒退
#   - 日志：/etc/config/openbox-install.log（可随时查看上次失败原因）
# ============================================================================

LOGFILE="/etc/config/openbox-install.log"
LOCK="/var/lock/openbox-install.lock"

# ---------- 0) 单实例锁 ----------
# 首启的 uci-defaults 补装与 init 服务可能同时启动，两者共用
# /tmp/open-box-install.sh 会互相截断，且 install.sh 会被并发执行。
if [ -d "$LOCK" ]; then
    # 进程被 SIGKILL 时 trap 不会执行，会留下死锁；超过 30 分钟视为过期并清理
    [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ] && rmdir "$LOCK" 2>/dev/null
fi
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "Open-Box: 已有安装实例在运行，本次跳过" >> "$LOGFILE"
    exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' 0
trap 'rmdir "$LOCK" 2>/dev/null; exit 130' INT TERM

echo "=== Open-Box install start $(date) ===" >> "$LOGFILE"

# ---------- 1) 读取构建时生成的开关配置（sed 提取，不 source，防特殊字符注入） ----------
OPENBOX_SETTINGS="/etc/config/openbox-settings"
ENABLE_OPENBOX="yes"
OPENBOX_REF="main"
OPENBOX_EXPECTED_SHA256=""
if [ -f "$OPENBOX_SETTINGS" ]; then
    ENABLE_OPENBOX=$(sed -n 's/^ENABLE_OPENBOX=//p' "$OPENBOX_SETTINGS" | tail -n1)
    OPENBOX_REF=$(sed -n 's/^OPENBOX_REF=//p' "$OPENBOX_SETTINGS" | tail -n1)
    OPENBOX_EXPECTED_SHA256=$(sed -n 's/^OPENBOX_EXPECTED_SHA256=//p' "$OPENBOX_SETTINGS" | tail -n1)
fi
case "$ENABLE_OPENBOX" in
    yes|true|1) ;;
    *)
        echo "Open-Box: 自动安装已关闭 (ENABLE_OPENBOX=$ENABLE_OPENBOX)" >> "$LOGFILE"
        exit 0
        ;;
esac

OPENBOX_INSTALLED="/opt/open-box/.installed"
[ -f "$OPENBOX_INSTALLED" ] && { echo "Open-Box: 已安装，跳过" >> "$LOGFILE"; exit 0; }

# ---------- 2) 等待网络就绪：默认路由出现（最多 90s） ----------
i=0
while [ $i -lt 30 ]; do
    if ip route show default 2>/dev/null | grep -q '^default'; then
        echo "Open-Box: 默认路由已出现" >> "$LOGFILE"
        break
    fi
    sleep 3
    i=$((i + 1))
done

# ---------- 3) 等待公网可达（最多 60s） ----------
i=0
net_ok="no"
while [ $i -lt 20 ]; do
    if ping -c1 -W2 223.5.5.5 >/dev/null 2>&1 || \
       curl -fsSL --connect-timeout 3 --max-time 8 -o /dev/null https://www.baidu.com 2>/dev/null; then
        net_ok="yes"
        echo "Open-Box: 公网可达" >> "$LOGFILE"
        break
    fi
    sleep 3
    i=$((i + 1))
done
if [ "$net_ok" != "yes" ]; then
    echo "Open-Box: 150 秒内网络未就绪，本次跳过（下次开机自动重试）" >> "$LOGFILE"
    exit 1
fi

# ---------- 4) 常量与镜像列表 ----------
OPENBOX_REPO="liandu2024/Open-Box"
: "${OPENBOX_REF:=main}"
OPENBOX_INSTALL_SH="$OPENBOX_REF/scripts/install.sh"
OPENBOX_TMP="/tmp/open-box-install.sh"
OPENBOX_SHA_TMP="/tmp/open-box-install.sh.sha256"
OPENBOX_LOCAL_DIR="/usr/share/openbox-pkg"

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

# ---------- 4.5) 本地安装包模式（构建期内联，首启零下载）----------
# 构建时把安装包与 install.sh 打进 /usr/share/openbox-pkg；这里起一个临时 busybox httpd，
# 让上游安装器通过 --mirror http://127.0.0.1:18080 从本地取包。
# 失败（无内联、busybox 无 httpd、安装报错）则返回 1，由调用方回退在线安装。
ob_local_install() {
    [ -x "$OPENBOX_LOCAL_DIR/install.sh" ] || return 1
    [ -f "$OPENBOX_LOCAL_DIR/www/https:/github.com/liandu2024/Open-Box/releases/latest/download/open-box-linux-arm64.tar.gz" ] || return 1
    busybox httpd -h "$OPENBOX_LOCAL_DIR/www" -p 18080 >/dev/null 2>&1 &
    _httpd_pid=$!
    sleep 1
    echo "Open-Box: 使用本地安装包（http://127.0.0.1:18080），无需下载" >> "$LOGFILE"
    sh "$OPENBOX_LOCAL_DIR/install.sh" --mirror "http://127.0.0.1:18080" >> "$LOGFILE" 2>&1
    _rc=$?
    kill "$_httpd_pid" 2>/dev/null
    if [ "$_rc" -eq 0 ] && [ -d /opt/open-box ]; then
        touch "$OPENBOX_INSTALLED"
        echo "Open-Box: 本地安装包安装完成" >> "$LOGFILE"
        return 0
    fi
    echo "Open-Box: 本地安装包安装失败(rc=$_rc)，回退在线安装" >> "$LOGFILE"
    return 1
}

# ---------- 5) 主流程 ----------
echo "Open-Box: 未安装，开始自动安装..." >> "$LOGFILE"
ok=0
if ob_local_install; then
    ok=1
else
    echo "Open-Box: 进入在线安装（多镜像容灾 + 校验）..." >> "$LOGFILE"
    for m in $OPENBOX_MIRRORS; do
        echo "Open-Box: 探测镜像 $m ..." >> "$LOGFILE"
        if ob_try_install "$m"; then ok=1; break; fi
    done
fi
if [ "$ok" -eq 0 ]; then
    echo "Open-Box: 所有内置镜像均不可用或校验/安装失败，本次跳过（下次开机自动重试）" >> "$LOGFILE"
    echo "Open-Box: 可手动下载 install.sh 安装，或把可用镜像前缀加入 OPENBOX_MIRRORS" >> "$LOGFILE"
fi

echo "=== Open-Box install end $(date) ===" >> "$LOGFILE"
# 返回真实结果：全部镜像都失败时返回 1（便于后续接入重试/告警；锁由 trap 释放）
[ "$ok" -eq 1 ] && exit 0
exit 1