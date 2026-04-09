//
//  PermissionManager.swift
//  AutoCopy
//
//  Created by AutoCopy Team on 2026/4/9.
//

import Foundation
import AppKit
import Combine

final class PermissionManager {
    static let shared = PermissionManager()

    // MARK: - 状态发布
    @Published private(set) var isAccessibilityPermissionGranted: Bool = false

    // 权限状态变化回调
    var onPermissionStatusChanged: ((Bool) -> Void)?

    private var permissionCheckTimer: Timer?
    private let permissionCheckInterval: TimeInterval = 1.0 // 每秒检查一次权限状态

    private init() {
        // 初始化时检查一次权限
        checkAccessibilityPermission()

        // 开始监听权限变化
        startPermissionMonitoring()
    }

    // MARK: - 公共接口

    /// 检查辅助功能权限
    /// - Parameter prompt: 如果没有权限，是否弹出系统提示
    /// - Returns: 是否已经获得权限
    @discardableResult
    func checkAccessibilityPermission(prompt: Bool = false) -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        let isTrusted = AXIsProcessTrustedWithOptions(options)

        // 如果权限状态变化，更新状态并通知
        if isTrusted != isAccessibilityPermissionGranted {
            isAccessibilityPermissionGranted = isTrusted
            onPermissionStatusChanged?(isTrusted)
            LogManager.shared.info("PermissionManager", "辅助功能权限状态变更: \(isTrusted ? "已授权" : "未授权")")
        }

        return isTrusted
    }

    /// 请求辅助功能权限
    func requestAccessibilityPermission() {
        guard !isAccessibilityPermissionGranted else {
            LogManager.shared.info("PermissionManager", "辅助功能权限已授权，无需重复请求")
            return
        }

        LogManager.shared.info("PermissionManager", "开始请求辅助功能权限")

        // 弹出系统权限提示
        checkAccessibilityPermission(prompt: true)
    }

    /// 打开系统辅助功能设置页面
    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            LogManager.shared.error("PermissionManager", "无法创建系统设置URL")
            return
        }

        NSWorkspace.shared.open(url)
        LogManager.shared.info("PermissionManager", "已打开系统辅助功能设置页面")
    }

    /// 停止权限状态监听
    func stopPermissionMonitoring() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        LogManager.shared.debug("PermissionManager", "已停止权限状态监听")
    }

    // MARK: - 私有方法

    /// 开始监听权限状态变化
    private func startPermissionMonitoring() {
        // 先停止已有的定时器
        stopPermissionMonitoring()

        // 创建新的定时器，在主线程运行
        permissionCheckTimer = Timer.scheduledTimer(
            withTimeInterval: permissionCheckInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self = self else { return }
            self.checkAccessibilityPermission()
        }

        LogManager.shared.debug("PermissionManager", "已启动权限状态监听，检查间隔: \(permissionCheckInterval)s")
    }

    /// 显示权限引导提示框
    private func showPermissionGuideAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = """
            AutoCopy 需要辅助功能权限才能监听全局鼠标事件，实现自动复制功能。

            请在弹出的系统设置窗口中，勾选 "AutoCopy" 以授予权限。
            授权完成后，请重启应用使设置生效。
            """
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后再说")

            let response = alert.runModal()

            if response == .alertFirstButtonReturn {
                self.openAccessibilitySettings()
            }
        }
    }

    deinit {
        stopPermissionMonitoring()
    }
}
