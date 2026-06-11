# 将 Imagebuilder 默认 repositories 切换到镜像源 避免下载失败
OFFICIAL="https://downloads.immortalwrt.org"
MIRROR="https://mirrors.cernet.edu.cn/immortalwrt"
echo ">>> official failed, switching to mirror"
BASE_URL="$MIRROR"
echo "Using BASE_URL = $BASE_URL"
echo "========================================"
echo "Updating repositories.conf"
echo "========================================"

# 查找 repositories.conf 文件位置
REPO_CONF=""
if [ -f "/home/build/immortalwrt/repositories.conf" ]; then
    REPO_CONF="/home/build/immortalwrt/repositories.conf"
elif [ -f "repositories.conf" ]; then
    REPO_CONF="repositories.conf"
elif [ -f "/home/build/immortalwrt/.config/repositories.conf" ]; then
    REPO_CONF="/home/build/immortalwrt/.config/repositories.conf"
fi

if [ -n "$REPO_CONF" ] && [ -f "$REPO_CONF" ]; then
    sed -i "s#${OFFICIAL}#${BASE_URL}#g" "$REPO_CONF"
    cat "$REPO_CONF"
else
    echo "⚠️ 未找到 repositories.conf 文件，跳过镜像源切换"
fi
