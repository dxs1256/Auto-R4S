#!/bin/sh

BASE_DIR="extra-packages"
TEMP_DIR="$BASE_DIR/temp-unpack"
TARGET_DIR="packages"

echo "========================================"
echo "📦 开始处理第三方软件包..."

# 1. 清理旧的目录，并重新创建
rm -rf "$TEMP_DIR" "$TARGET_DIR"
mkdir -p "$TEMP_DIR" "$TARGET_DIR"

# 2. 安全地解压所有的 .run 文件
# 使用 find 寻找，防止当没有 .run 文件时脚本报错
find "$BASE_DIR" -maxdepth 1 -type f -name "*.run" | while read -r run_file; do
    echo "🧩 正在解压: $run_file"
    sh "$run_file" --target "$TEMP_DIR" --noexec >/dev/null 2>&1
done

# 3. 暴力且高效地收集所有 .ipk 文件
echo "🔍 正在全自动收集所有 .ipk 安装包..."

# 直接在 BASE_DIR 和 TEMP_DIR 中寻找所有 .ipk，统一拷贝到 TARGET_DIR
# 使用 -exec cp -t {} + 语法，把"单次搬砖"变成"一车拉走"，极大提升速度
find "$BASE_DIR" "$TEMP_DIR" -type f -name "*.ipk" -exec cp -t "$TARGET_DIR"/ {} + 2>/dev/null

# 如果系统不支持 -t 参数（部分极简环境），则回退到兼容模式
if [ $? -ne 0 ]; then
    find "$BASE_DIR" "$TEMP_DIR" -type f -name "*.ipk" -exec cp {} "$TARGET_DIR"/ \;
fi

# 统计数量
IPK_COUNT=$(ls -1 "$TARGET_DIR"/*.ipk 2>/dev/null | wc -l)
echo "✅ 整理完毕！共收集到 $IPK_COUNT 个 .ipk 插件文件，已存入 $TARGET_DIR/"
echo "========================================"
