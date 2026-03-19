#!/bin/bash
# install.sh - AutoCopy 安装脚本（从 GitHub Releases 下载预编译包）

set -e

echo "=== AutoCopy 安装程序 ==="

# 配置
REPO="ucefac/autocopy"
INSTALL_DIR="$HOME/.config/autocopy"
BIN_DIR="$INSTALL_DIR/bin"

# 1. 架构检查
echo "[1/7] 检查系统架构..."
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" && "$ARCH" != "aarch64" ]]; then
    echo "错误：仅支持 macOS ARM64 (aarch64) 架构"
    echo "当前架构：$ARCH"
    exit 1
fi
echo "架构检查通过：$ARCH"

# 2. 网络检查
echo "[2/7] 检查网络连接..."
if ! curl -s --head https://github.com &>/dev/null; then
    echo "错误：无法访问 github.com，请检查网络连接"
    exit 1
fi
echo "网络连接正常"

# 3. 获取最新版本
echo "[3/7] 获取最新版本..."
LATEST=$(curl -s https://api.github.com/repos/$REPO/releases/latest)
VERSION=$(echo "$LATEST" | grep '"tag_name"' | cut -d'"' -f4)
if [[ -z "$VERSION" ]]; then
    echo "错误：无法从 GitHub API 获取版本号"
    exit 1
fi
echo "最新版本：$VERSION"

# 4. 下载安装包
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$VERSION/autocopy-aarch64-apple-darwin.tar.gz"
TMP_FILE=$(mktemp /tmp/autocopy-XXXXXX.tar.gz)

echo "[4/7] 下载 $VERSION..."
if ! curl -L "$DOWNLOAD_URL" -o "$TMP_FILE" 2>/dev/null; then
    echo "错误：下载失败"
    exit 1
fi
echo "下载完成"

# 5. 安装
echo "[5/7] 安装到 $BIN_DIR..."
mkdir -p "$BIN_DIR"
tar -xzf "$TMP_FILE" -C "$BIN_DIR"
chmod +x "$BIN_DIR/autocopy"
echo "二进制文件已安装"

# 6. 复制配置文件
echo "[6/7] 配置..."
CONFIG_DIR="$HOME/.config/autocopy"
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/autocopy.ini" ]; then
    cp configs/default-config "$CONFIG_DIR/autocopy.ini" 2>/dev/null || true
    echo "创建默认配置文件"
fi

# 7. 创建 LaunchAgent
echo "[7/7] 配置开机自启..."
PLIST_FILE="$HOME/Library/LaunchAgents/com.ucefac.autocopy.plist"

cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ucefac.autocopy</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOME/.config/autocopy/bin/autocopy</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/.config/autocopy/autocopy.out.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.config/autocopy/autocopy.err.log</string>
</dict>
</plist>
EOF

# 加载 LaunchAgent
launchctl unload "$PLIST_FILE" 2>/dev/null || true
launchctl load "$PLIST_FILE"

# 清理临时文件
rm -f "$TMP_FILE"

echo ""
echo "=== 安装完成 ==="
echo ""
echo "请在 系统设置 > 隐私与安全性 > 辅助功能 中授权 AutoCopy"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
echo ""
echo "授权后请重新运行：launchctl load ~/Library/LaunchAgents/com.ucefac.autocopy.plist"
