#!/bin/bash
# uninstall-macos.sh - AutoCopy 卸载脚本

set -e

echo "=== AutoCopy 卸载程序 ==="

# 停止并卸载 LaunchAgent
echo "停止服务..."
launchctl unload ~/Library/LaunchAgents/com.ucefac.autocopy.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.ucefac.autocopy.plist

# 删除文件
echo "删除文件..."
rm -rf ~/.config/autocopy

echo "=== 卸载完成 ==="
