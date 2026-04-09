//
//  Types.swift
//  AutoCopy
//
//  Created by Claude on 2024/4/8.
//

import Foundation

// MARK: - 点击类型枚举
enum ClickType: String, Codable, CaseIterable {
    case single
    case double
    case triple
}

// MARK: - 日志级别枚举
enum LogLevel: String, Codable, Comparable, CaseIterable {
    case debug
    case info
    case warn
    case error

    var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warn: return 2
        case .error: return 3
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.priority < rhs.priority
    }

    var icon: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warn: return "⚠️"
        case .error: return "❌"
        }
    }
}

// MARK: - 应用运行状态结构体
struct AppState: Codable {
    /// 是否正在运行
    var isRunning: Bool
    /// 是否启用自动复制功能
    var autoCopyEnabled: Bool
    /// 是否已获得辅助功能权限
    var accessibilityPermissionGranted: Bool
    /// 已复制次数统计
    var copyCount: Int
    /// 应用启动时间
    var launchTime: Date

    init() {
        self.isRunning = false
        self.autoCopyEnabled = true
        self.accessibilityPermissionGranted = false
        self.copyCount = 0
        self.launchTime = Date()
    }
}

// MARK: - 应用配置结构体
struct Config: Codable {
    /// 双击间隔时间（秒）
    var doubleClickInterval: TimeInterval
    /// 最大点击偏移像素
    var maxClickOffset: Int
    /// 最小按压时长（秒）
    var minPressDuration: TimeInterval
    /// 长按阈值（秒），超过此时长判定为长按，不触发复制
    var longPressThreshold: TimeInterval
    /// 是否启用自动复制
    var autoCopyEnabled: Bool
    /// 是否显示复制成功提示
    var showToast: Bool
    /// 日志级别
    var logLevel: LogLevel
    /// 是否启动时自动运行
    var launchAtLogin: Bool

    // MARK: - 高级配置
    /// 排除的应用Bundle ID列表
    var excludedApps: [String]
    /// Toast显示时长（秒）
    var toastDisplayDuration: TimeInterval
    /// 是否启用拖拽选择自动复制
    var enableDragCopy: Bool

    init() {
        self.doubleClickInterval = Constants.DefaultConfig.doubleClickInterval
        self.maxClickOffset = Constants.DefaultConfig.maxClickOffset
        self.minPressDuration = Constants.DefaultConfig.minPressDuration
        self.longPressThreshold = Constants.DefaultConfig.longPressThreshold
        self.autoCopyEnabled = Constants.DefaultConfig.autoCopyEnabled
        self.showToast = Constants.DefaultConfig.showToast
        self.logLevel = .debug
        self.launchAtLogin = false

        // 高级配置默认值
        self.excludedApps = ["com.apple.dt.Xcode", "com.microsoft.VSCode"]
        self.toastDisplayDuration = 0.7
        self.enableDragCopy = true
    }
}

// MARK: - 鼠标点击事件结构体
struct MouseClickEvent {
    /// 点击位置
    let location: NSPoint
    /// 点击时间
    let timestamp: TimeInterval
    /// 点击类型
    let clickType: ClickType
    /// 按下到释放的时长
    let pressDuration: TimeInterval
}

// MARK: - 复制结果枚举
enum CopyResult: Equatable {
    case success(content: String)
    case failure(reason: String)
    case noSelection
}
