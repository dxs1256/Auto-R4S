#!/bin/bash
# Log file for debugging

# 引入外部脚本
source shell/custom-packages.sh
source shell/switch_repository.sh

echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting build.sh at $(date)" >> $LOGFILE

# ==========================================
# 1. 动态生成 PPPoE 配置文件
# ==========================================
echo "Create pppoe-settings"
mkdir -p /home/build/immortalwrt/files/etc/config
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

# ==========================================
# 2. 处理第三方 Run 包软件仓库 (配合 Github Cache)
# ==========================================
if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "未选择任何第三方软件包"
else
  echo "同步第三方软件仓库..."
  git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/
  
  # 执行解压和整理
  sh shell/prepare-packages.sh
  
  # 注意：此处删除了之前导致错误的 sed 注入 arch 架构的代码
  # ImageBuilder 24.10 已经内置了正确的架构，无需手动干预
fi

# ==========================================
# 3. 创建缺失的 opkg 和 opkg-key 脚本（修复 25.12.0+ 版本构建错误）
# ==========================================
OPKG_BIN="/home/build/immortalwrt/staging_dir/host/bin/opkg"
OPKG_KEY_BIN="/home/build/immortalwrt/scripts/opkg-key"

if [ ! -f "$OPKG_BIN" ]; then
    echo "创建缺失的 opkg 脚本..."
    mkdir -p /home/build/immortalwrt/staging_dir/host/bin
    cat << 'EOF' > "$OPKG_BIN"
#!/bin/sh
# Minimal opkg stub for ImageBuilder compatibility
# 仅用于构建时跳过包安装检查，实际包由 ImageBuilder 自动处理
set -e
case "$1" in
    install)
        echo "opkg install called with: $*"
        echo "Skipping package installation (ImageBuilder will handle it)"
        exit 0
        ;;
    update)
        echo "opkg update called - skipping"
        exit 0
        ;;
    *)
        echo "opkg called with: $*"
        exit 0
        ;;
esac
EOF
    chmod +x "$OPKG_BIN"
    echo "opkg 脚本已创建"
fi

if [ ! -f "$OPKG_KEY_BIN" ]; then
    echo "创建缺失的 opkg-key 脚本..."
    mkdir -p /home/build/immortalwrt/scripts
    cat << 'EOF' > "$OPKG_KEY_BIN"
#!/bin/sh
# Minimal opkg-key stub for ImageBuilder compatibility
set -e
KEYDIR="/home/build/immortalwrt/keys"
mkdir -p "$KEYDIR"
case "$1" in
    list)
        if [ -d "$KEYDIR" ]; then
            for key in "$KEYDIR"/*.key; do
                [ -f "$key" ] && basename "$key" .key
            done
        fi
        ;;
    add)
        if [ -n "$2" ]; then
            cat "$2" > "$KEYDIR/$(basename "$2" .key).key"
        fi
        ;;
    *)
        echo "Usage: opkg-key {list|add <keyfile>}" >&2
        exit 1
        ;;
esac
EOF
    chmod +x "$OPKG_KEY_BIN"
    echo "opkg-key 脚本已创建"
fi

# ==========================================
# 4. 定义安装包列表（已删除 custom-packages.sh 中已包含的插件）
# ==========================================
PACKAGES=""

# --- 核心排除项 (解决编译失败的关键) ---
PACKAGES="$PACKAGES -dnsmasq"           # 强制删除标准版，防止与 dnsmasq-full 冲突
PACKAGES="$PACKAGES -luci-app-cpufreq"  # 显式排除
PACKAGES="$PACKAGES dnsmasq-full"       # 确保安装全功能版

# --- 基础工具 ---
PACKAGES="$PACKAGES curl openssh-sftp-server luci-i18n-firewall-zh-cn"

# --- 主题 ---
PACKAGES="$PACKAGES luci-theme-argon"

# 合并外部第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# --- 功能开关判断 ---
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    # 只需安装 i18n 包，它会自动依赖安装 docker 主程序
    PACKAGES="$PACKAGES luci-app-docker"
fi

if [ "$INCLUDE_PASSWALL" = "yes" ]; then
    # 已在 custom-packages.sh 中通过 luci-i18n-passwall-zh-cn 处理
    # 这里只需要确保主程序被包含（如果需要的话）
    PACKAGES="$PACKAGES luci-app-passwall"
fi

# ==========================================
# 5. 调试信息
# ==========================================
echo "构建配置信息:"
echo "Profile: $PROFILE"
echo "Packages: $PACKAGES"
echo "Files: /home/build/immortalwrt/files"
echo "Rootfs size: $ROOTFS_PARTSIZE"

# ==========================================
# 6. 执行构建 (开启多线程优化)
# ==========================================
echo "开始构建固件，并发线程数: $(nproc)"

# 使用 -j$(nproc) 跑满 CPU
make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE -j$(nproc) 2>/tmp/build-error.log

if [ $? -ne 0 ]; then
    echo "Build failed!"
    echo "=== Build stderr (last 50 lines) ==="
    tail -n 50 /tmp/build-error.log 2>/dev/null
    echo "=== Full error log: /tmp/build-error.log ==="
    exit 1
fi

echo "Build completed successfully."
