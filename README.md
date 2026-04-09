# AutoCopy

> main 分支已过时，macOS 用户请使用 macos 分支

> 选中文字后自动复制到剪贴板，无需手动按 Cmd（Ctrl）+C

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## 功能特点

- **自动复制** - 鼠标选中文字后松手自动复制
- **双击/三击支持** - 智能识别双击选词、三击选行
- **防误触** - 短按不触发，避免误操作
- **应用排除** - 可配置在特定应用中禁用
- **隐私保护** - 不记录任何敏感信息
- **跨平台** - 支持 macOS 和 Windows（Windows 开发中）

## 快速开始

### 快速安装（推荐）

```bash
# macOS (ARM64)
curl -fsSL https://raw.githubusercontent.com/ucefac/autocopy/main/install.sh | bash

# Windows
# Windows 版本开发中，敬请期待
```

### 手动安装

```bash
# 1. 克隆仓库
git clone https://github.com/ucefac/autocopy.git
cd autocopy
cargo run
```

### 配置

配置文件位于 `~/.config/autocopy/autocopy.ini`:

```ini
[default]
# 排除的应用（逗号分隔）
excluded_apps=Terminal,iTerm2,Alacritty

# 最小按压时间（秒）
min_press_duration=0.5

# 双击检测间隔（秒）
double_click_interval=0.3

# 最大位置偏移（像素）
max_click_distance=5

# 日志文件路径
log_file=~/.config/autocopy/autocopy.log

# 日志级别 (debug, info, warn, error)
log_level=info

# 是否启用日志
enable_log=false

# 隐私保护选项
log_app_name=false
log_mouse_coords=false
```

### 卸载

```bash
./scripts/uninstall-macos.sh
```

## 隐私说明

- ✅ 所有数据本地存储，不联网
- ✅ 不收集任何个人信息
- ✅ 不记录选中的文本内容
- ✅ 无遥测/分析
- ✅ 开源代码，可审查

## 开发

### 编译

```bash
cargo build --release
```

### 测试

```bash
cargo test
```

## License

MIT License
