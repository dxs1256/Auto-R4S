#!/bin/bash
# Auto-R4S 统一构建脚本
# 由 BUILD_SERIES 区分两套体系：
#   24.10 -> opkg 包管理，第三方仓库 wukongdaily/store，配置 imm.config
#   25.12 -> apk 包管理，第三方仓库 wukongdaily/apk，配置 imm25.config
: "${BUILD_SERIES:=24.10}"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting build.sh at $(date) (series=$BUILD_SERIES)" >> $LOGFILE

# 第三方包清单（由 workflow 在运行时追加过 CUSTOM_PACKAGES 行）
if [ "$BUILD_SERIES" = "25.12" ]; then
  source shell/apk-custom-packages.sh
else
  source shell/custom-packages.sh
fi
echo "第三方软件包: $CUSTOM_PACKAGES"

PKG_EXT="ipk"
[ "$BUILD_SERIES" = "25.12" ] && PKG_EXT="apk"

echo "Building for profile: $PROFILE"
echo "Building for ROOTFS_PARTSIZE: $ROOTFS_PARTSIZE"

mkdir -p /home/build/immortalwrt/files/etc/config

# pppoe 配置（供 99-custom.sh 读取）
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

# openbox 开关配置（供 99-custom.sh 读取）
cat << EOF > /home/build/immortalwrt/files/etc/config/openbox-settings
ENABLE_OPENBOX=${ENABLE_OPENBOX:-yes}
OPENBOX_REF=${OPENBOX_REF:-main}
OPENBOX_EXPECTED_SHA256=${OPENBOX_EXPECTED_SHA256:-}
EOF

if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择 任何第三方软件包"
else
  if [ "$BUILD_SERIES" = "25.12" ]; then
    git clone --depth=1 https://github.com/wukongdaily/apk.git /tmp/store-apk-repo
    mkdir -p /home/build/immortalwrt/extra-packages
    cp -r /tmp/store-apk-repo/run/arm64/* /home/build/immortalwrt/extra-packages/ 2>/dev/null || true
    sh shell/apk-prepare-packages.sh
  else
    git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo
    mkdir -p /home/build/immortalwrt/extra-packages
    cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/ 2>/dev/null || true
    sh shell/prepare-packages.sh
  fi

  ls -lah /home/build/immortalwrt/packages/ 2>/dev/null

  # 复制 shell/ 下自定义包（pushbot / openlist2 / accesscontrol）
  for d in pushbot openlist2 accesscontrol; do
    if [ -d /home/build/immortalwrt/shell/$d ]; then
      cp -v /home/build/immortalwrt/shell/$d/*.$PKG_EXT /home/build/immortalwrt/packages/ 2>/dev/null || true
    fi
  done

  echo "✅ packages 目录最终内容:"
  ls -lah /home/build/immortalwrt/packages/

  # opkg 体系需要显式声明架构优先级
  if [ "$BUILD_SERIES" != "25.12" ]; then
    sed -i '1i\
arch aarch64_generic 10\
arch aarch64_cortex-a53 15' repositories.conf
  fi
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."
if [ "$BUILD_SERIES" = "25.12" ]; then
  cat repositories
else
  cat repositories.conf
fi

# 基础包（可按需删减）
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"

# Docker：必须引擎本体 + 界面同时安装，否则只有界面没有 docker 服务
if [ "$INCLUDE_DOCKER" = "yes" ]; then
  if [ "$BUILD_SERIES" = "25.12" ]; then
    PACKAGES="$PACKAGES docker dockerd luci-i18n-dockerman-zh-cn"
  else
    PACKAGES="$PACKAGES docker luci-i18n-dockerman-zh-cn"
  fi
  echo "Adding docker packages"
fi

# 合并第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE

if [ $? -ne 0 ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
  exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."

echo "===== 实际安装的软件包清单 ====="
MANIFEST=$(find bin/targets -name "*.manifest" -type f 2>/dev/null | head -1)
if [ -n "$MANIFEST" ]; then
  echo "来源文件: $MANIFEST"
  cat "$MANIFEST"
else
  echo "未找到 .manifest 文件"
fi
