#!/bin/bash
# AutoCopy 通用安装脚本
# 根据操作系统自动选择对应的安装脚本
# 用法：curl -fsSL https://raw.githubusercontent.com/ucefac/autocopy/main/install.sh | bash

set -e

echo "=== AutoCopy 安装程序 ==="

# 检测操作系统
OS=$(uname -s)
echo "检测到操作系统：$OS"

case "$OS" in
    Darwin)
        echo "macOS  detected，执行 macOS 安装脚本..."
        SCRIPT_URL="https://raw.githubusercontent.com/ucefac/autocopy/main/scripts/install-macos.sh"
        if command -v curl &>/dev/null; then
            curl -fsSL "$SCRIPT_URL" | bash
        else
            echo "错误：未找到 curl 命令"
            exit 1
        fi
        ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
        echo ""
        echo "Windows 版本开发中，敬请期待..."
        echo ""
        echo "如需手动安装，请："
        echo "1. 访问 https://github.com/ucefac/autocopy/releases"
        echo "2. 下载最新版本的 Windows 压缩包"
        echo "3. 解压到任意目录"
        echo "4. 运行 autocopy.exe"
        echo ""
        ;;
    Linux)
        echo ""
        echo "抱歉，Linux 版本暂不支持"
        echo ""
        echo "如需手动编译安装，请："
        echo "1. 克隆仓库：git clone https://github.com/ucefac/autocopy.git"
        echo "2. 安装 Rust: https://rustup.rs/"
        echo "3. 编译：cargo build --release"
        echo "4. 运行：./target/release/autocopy"
        echo ""
        ;;
    *)
        echo "错误：不支持的操作系统：$OS"
        echo "当前仅支持 macOS"
        exit 1
        ;;
esac
