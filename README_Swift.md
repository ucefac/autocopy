# AutoCopy for macOS

自动复制工具，选中文本后无需手动按 Cmd+C，自动复制到剪贴板。

## 功能特性

- ✅ **智能检测**：双击、三击、拖拽选中文本自动复制
- ✅ **低资源消耗**：CPU 占用 < 0.1%，内存占用 < 20MB
- ✅ **多显示器支持**：Toast 提示自动适配当前显示器
- ✅ **全屏应用兼容**：全屏场景下正常工作
- ✅ **隐私保护**：密码框等敏感输入自动跳过
- ✅ **可配置性**：丰富的自定义选项
- ✅ **系统兼容**：支持 macOS 12.0+，原生支持 Apple Silicon

## 系统要求

- macOS 12.0 Monterey 或更高版本
- Apple Silicon (M1/M2/M3) 架构

## 安装方法

### 手动安装
1. 下载最新版本的 `AutoCopy.dmg`
2. 挂载 DMG 文件，将 `AutoCopy.app` 拖拽到应用程序文件夹
3. 打开 `AutoCopy.app`
4. 在系统偏好设置 > 隐私与安全性 > 辅助功能中，启用 AutoCopy 的权限
5. 重启应用即可使用

### 卸载
1. 退出 AutoCopy（点击状态栏图标 > 退出）
2. 将 `AutoCopy.app` 移动到废纸篓
3. 可选：删除配置文件 `~/.config/autocopy/`
4. 可选：删除日志文件 `~/Library/Logs/AutoCopy/`

## 使用方法

### 基础使用
1. 应用启动后会在状态栏显示图标
2. 选中文本：
   - 双击单词自动复制
   - 三击行自动复制
   - 拖拽选择文本自动复制
3. 复制成功后鼠标旁会显示 ✓ 提示
4. 直接 Cmd+V 即可粘贴

### 状态栏菜单
- **启用自动复制**：开关自动复制功能
- **开机自启**：设置是否随系统启动
- **偏好设置**：打开配置文件
- **查看日志**：打开日志文件夹
- **关于**：查看版本信息
- **退出**：退出应用

## 配置说明

配置文件位于 `~/.config/autocopy/autocopy.ini`，如果不存在会自动创建。

### 基础配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `autoCopyEnabled` | boolean | `true` | 是否启用自动复制功能 |
| `doubleClickInterval` | float | `0.4` | 双击/三击的最大时间间隔（秒） |
| `maxClickOffset` | integer | `5` | 连续点击的最大像素偏移 |
| `minPressDuration` | float | `0.5` | 长按判定阈值（秒） |
| `showToast` | boolean | `true` | 是否显示复制成功提示 |
| `logLevel` | string | `info` | 日志级别：debug/info/warn/error |

### 高级配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `excludedApps` | string | `""` | 排除的应用 Bundle ID，多个用逗号分隔 |
| `toastDisplayDuration` | float | `0.7` | Toast 提示显示时长（秒） |
| `enableDragCopy` | boolean | `true` | 是否启用拖拽选择自动复制 |

### 常用应用 Bundle ID
- Xcode: `com.apple.dt.Xcode`
- VS Code: `com.microsoft.VSCode`
- Chrome: `com.google.Chrome`
- Safari: `com.apple.Safari`
- Terminal: `com.apple.Terminal`
- iTerm2: `com.googlecode.iterm2`

## 常见问题

### Q: 应用无法启动？
A: 请确保在系统偏好设置 > 隐私与安全性 > 辅助功能中已经启用了 AutoCopy 的权限。

### Q: 选中了文本但没有自动复制？
A:
1. 检查状态栏图标是否显示为启用状态
2. 确认当前应用不在排除列表中
3. 检查是否在密码框等敏感输入场景
4. 尝试重新授予辅助功能权限

### Q: 如何关闭开机自启？
A: 点击状态栏图标，取消勾选"开机自启"即可。

### Q: 应用占用资源高吗？
A: AutoCopy 经过深度优化，后台运行时 CPU 占用通常 < 0.1%，内存占用 < 20MB，几乎不影响系统性能。

### Q: 会收集我的数据吗？
A: 不会。所有功能都在本地运行，不会上传任何数据。选中文本仅在本地处理，不会发送到任何服务器。

## 隐私说明

AutoCopy 非常重视用户隐私：
- 仅在选中文本时临时访问文本内容，完成复制后立即释放
- 密码框等敏感输入会自动跳过，不会读取敏感内容
- 所有数据处理都在本地完成，不会上传任何信息
- 不会记录或存储用户的剪贴板内容

## 故障排除

### 权限问题
如果遇到权限相关问题，可以尝试重置权限：
```bash
tccutil reset Accessibility com.yyyyyyh.AutoCopy
```
然后重启应用，重新授权。

### 日志查看
日志文件位于 `~/Library/Logs/AutoCopy/`，可以查看详细的运行日志帮助排查问题。

## 技术说明

### 实现原理
1. 使用事件监听 API 捕获全局鼠标事件
2. 通过 Accessibility API 获取选中的文本内容
3. 模拟 Cmd+C 快捷键执行复制操作
4. 显示 Toast 提示复制结果

### 性能优化
- 异步事件处理，避免阻塞主线程
- 批量日志写入，减少 IO 操作
- 系统调用缓存，减少不必要的 API 调用
- 智能防抖，避免重复触发复制

### 项目结构
```
AutoCopy/
├── AutoCopyApp.swift              # 程序入口，应用生命周期管理
├── Core/
│   ├── AppCoordinator.swift       # 应用协调器，模块调度
│   ├── ConfigManager.swift        # 配置文件管理
│   ├── Constants.swift            # 全局常量定义
│   ├── InstanceManager.swift      # 单实例管理
│   ├── LogManager.swift           # 日志系统
│   ├── PermissionManager.swift    # 权限管理
│   ├── StatusBarManager.swift     # 状态栏管理
│   └── Types.swift                # 通用类型定义
├── Features/
│   ├── AccessibilityManager.swift # Accessibility API 封装
│   ├── AutoStartManager.swift     # 开机自启管理
│   ├── ClickDetector.swift        # 点击类型检测
│   ├── ClipboardManager.swift     # 剪贴板操作
│   ├── EventListener.swift        # 全局事件监听
│   └── ToastManager.swift         # Toast 提示
├── UI/
│   └── PermissionAlert.swift      # 权限引导弹窗
└── Resources/
    ├── Assets.xcassets            # 图标资源
    └── Info.plist                 # 应用配置
```

## 编译说明

### 编译要求
- Xcode 14.0+
- Swift 5.0+

### 编译步骤
1. 打开项目：`open AutoCopy.xcodeproj`
2. 选择 Release 配置
3. 编译：Cmd+B
4. 导出：Product > Archive

### 打包配置
- 架构：仅 arm64 (Apple Silicon)
- 部署目标：macOS 12.0+
- 启用 Hardened Runtime
- 支持 Notarization 公证

## 版本历史

### v1.0.0
- 初始版本发布
- 支持双击、三击、拖拽选择自动复制
- 多显示器支持
- 全屏应用兼容
- 可配置的排除应用列表

## 许可证

MIT License

## 反馈与支持

如果遇到问题或有改进建议，欢迎在 GitHub 提交 Issue。
