#!/bin/bash
# AutoCopy 打包脚本
# 用法: ./scripts/package.sh

set -e

PROJECT_NAME="AutoCopy"
SCHEME="AutoCopy"
BUILD_DIR="./build"
RELEASE_DIR="./release"
DMG_NAME="${PROJECT_NAME}.dmg"
APP_PATH="${BUILD_DIR}/Build/Products/Release/${PROJECT_NAME}.app"

echo "=== AutoCopy 打包脚本 ==="

# 检查 Xcode 命令行工具
if ! command -v xcodebuild &> /dev/null; then
    echo "错误: Xcode 命令行工具未安装，请先安装 Xcode"
    exit 1
fi

# 清理旧的构建文件
echo "清理旧的构建文件..."
rm -rf "${BUILD_DIR}"
rm -rf "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"

# 编译 Release 版本
echo "编译 Release 版本..."
xcodebuild -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    build

# 检查编译结果
if [ ! -d "${APP_PATH}" ]; then
    echo "错误: 编译失败，未找到应用包"
    exit 1
fi

echo "编译成功，应用大小: $(du -sh "${APP_PATH}" | awk '{print $1}')"

# 复制到发布目录
echo "复制应用到发布目录..."
cp -R "${APP_PATH}" "${RELEASE_DIR}/"

# 创建 dmg 磁盘镜像
echo "创建 DMG 磁盘镜像..."
hdiutil create \
    -volname "${PROJECT_NAME}" \
    -srcfolder "${RELEASE_DIR}/${PROJECT_NAME}.app" \
    -format UDZO \
    -o "${RELEASE_DIR}/${DMG_NAME}"

# 清理临时文件
echo "清理临时文件..."
rm -rf "${BUILD_DIR}"

echo ""
echo "=== 打包完成 ==="
echo "应用包: ${RELEASE_DIR}/${PROJECT_NAME}.app"
echo "DMG 镜像: ${RELEASE_DIR}/${DMG_NAME}"
echo "文件大小: $(du -sh "${RELEASE_DIR}/${DMG_NAME}" | awk '{print $1}')"
echo ""
echo "下一步:"
echo "1. 对应用进行代码签名: codesign --deep --force --verbose --sign \"Developer ID Application:\" \"${RELEASE_DIR}/${PROJECT_NAME}.app\""
echo "2. 对 DMG 进行公证: xcrun notarytool submit \"${RELEASE_DIR}/${DMG_NAME}\" --keychain-profile \"Developer ID\""
echo "3. 验证公证: xcrun notarytool info <submission-id> --keychain-profile \"Developer ID\""
echo "4.  stapling: xcrun stapler staple \"${RELEASE_DIR}/${DMG_NAME}\""