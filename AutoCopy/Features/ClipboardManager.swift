//
//  ClipboardManager.swift
//  AutoCopy
//
//  Created by Claude on 2024/4/8.
//

import Foundation
import AppKit

/// 剪贴板内容快照，用于保存和恢复剪贴板的所有内容
private struct PasteboardSnapshot: Equatable {
    let items: [[NSPasteboard.PasteboardType: Any]]

    static func == (lhs: PasteboardSnapshot, rhs: PasteboardSnapshot) -> Bool {
        guard lhs.items.count == rhs.items.count else { return false }
        for (lhsItem, rhsItem) in zip(lhs.items, rhs.items) {
            guard lhsItem.count == rhsItem.count else { return false }
            for (type, lhsValue) in lhsItem {
                guard let rhsValue = rhsItem[type] else { return false }
                if let lhsData = lhsValue as? Data, let rhsData = rhsValue as? Data {
                    guard lhsData == rhsData else { return false }
                } else if let lhsString = lhsValue as? String, let rhsString = rhsValue as? String {
                    guard lhsString == rhsString else { return false }
                } else {
                    return false
                }
            }
        }
        return true
    }

    /// 从当前剪贴板创建快照
    static func fromCurrent(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        var items: [[NSPasteboard.PasteboardType: Any]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var itemData: [NSPasteboard.PasteboardType: Any] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData[type] = data
                } else if let string = item.string(forType: type) {
                    itemData[type] = string
                }
            }
            items.append(itemData)
        }
        return PasteboardSnapshot(items: items)
    }

    /// 将快照内容恢复到剪贴板
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        for (index, item) in items.enumerated() {
            let pasteboardItem = NSPasteboardItem()
            for (type, value) in item {
                if let data = value as? Data {
                    pasteboardItem.setData(data, forType: type)
                } else if let string = value as? String {
                    pasteboardItem.setString(string, forType: type)
                }
            }
            pasteboard.writeObjects([pasteboardItem])
        }
    }

    /// 获取快照中的字符串内容（用于判断复制是否成功）
    var stringContent: String? {
        for item in items {
            if let string = item[.string] as? String {
                return string
            } else if let data = item[.string] as? Data, let string = String(data: data, encoding: .utf8) {
                // 支持从Data类型解析UTF-8文本
                return string
            } else if let data = item[.string] as? Data, let string = String(data: data, encoding: .utf16) {
                // 兼容UTF-16编码的文本
                return string
            }
        }
        return nil
    }
}

final class ClipboardManager {
    static let shared = ClipboardManager()

    private let clipboardQueue = DispatchQueue(label: "com.autocopy.clipboardManager", qos: .userInitiated)
    private let pasteboard = NSPasteboard.general

    /// 模拟按键后等待剪贴板更新的初始延迟（秒）
    private let initialReadDelay: TimeInterval = 0.15
    /// 最大重试次数（从2次增加到3次，总共尝试4次）
    private let maxRetries: Int = 3
    /// 重试延迟基础值（指数退避）
    private let retryBaseDelay: TimeInterval = 0.05
    /// 按键按下间隔
    private let keyPressDelay: TimeInterval = 0.01
    /// 按键保持时长
    private let keyHoldDelay: TimeInterval = 0.02

    /// 复制成功回调
    var onCopySuccess: ((String) -> Void)?

    /// 复制失败回调
    var onCopyFailure: ((String) -> Void)?

    private init() {
        // 给队列设置特定标记，用于判断当前是否在该队列中
        clipboardQueue.setSpecific(key: Self.queueKey, value: ())
    }

    // MARK: - 公共接口

    /// 执行复制操作
    func performCopy() {
        clipboardQueue.async { [weak self] in
            guard let self = self else { return }
            self.performCopyWithSimulatedShortcut()
        }
    }

    /// 模拟Cmd+C按键
    private func simulateCopyShortcut(completion: @escaping (_ originalSnapshot: PasteboardSnapshot?) -> Void) {
        // 所有CGEvent操作必须在主线程执行
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                LogManager.shared.error("ClipboardManager", "模拟按键失败：self已释放")
                completion(nil)
                return
            }

            LogManager.shared.debug("ClipboardManager", "开始模拟Cmd+C按键")

            // 发送按键前立刻保存原始剪贴板快照，最小化时间差，减少竞态条件
            let originalSnapshot = PasteboardSnapshot.fromCurrent(self.pasteboard)
            LogManager.shared.debug("ClipboardManager", "已保存原始剪贴板快照，item数量: \(originalSnapshot.items.count)")
            // 输出原始剪贴板详细信息
            for (index, item) in originalSnapshot.items.enumerated() {
                let typeNames = item.keys.map { $0.rawValue }.joined(separator: ", ")
                LogManager.shared.debug("ClipboardManager", "原始快照 Item \(index) 包含类型: \(typeNames)")
            }
            if let originalString = originalSnapshot.stringContent {
                let truncated = originalString.count > 100 ? "\(originalString.prefix(100))..." : originalString
                LogManager.shared.debug("ClipboardManager", "原始快照文本内容: \(truncated)")
            } else {
                LogManager.shared.debug("ClipboardManager", "原始快照无文本内容")
            }

            guard let source = CGEventSource(stateID: .hidSystemState) else {
                LogManager.shared.error("ClipboardManager", "模拟按键失败：无法创建CGEventSource")
                completion(originalSnapshot)
                return
            }

            // 创建Cmd按下事件
            guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) else {
                LogManager.shared.error("ClipboardManager", "模拟按键失败：无法创建Cmd按下事件")
                completion(originalSnapshot)
                return
            }
            cmdDown.flags = .maskCommand
            LogManager.shared.debug("ClipboardManager", "已创建Cmd按下事件")

            // 创建C按下事件
            guard let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) else {
                LogManager.shared.error("ClipboardManager", "模拟按键失败：无法创建C按下事件")
                completion(originalSnapshot)
                return
            }
            cDown.flags = .maskCommand
            LogManager.shared.debug("ClipboardManager", "已创建C按下事件")

            // 创建C释放事件
            guard let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else {
                LogManager.shared.error("ClipboardManager", "模拟按键失败：无法创建C释放事件")
                completion(originalSnapshot)
                return
            }
            cUp.flags = .maskCommand
            LogManager.shared.debug("ClipboardManager", "已创建C释放事件")

            // 创建Cmd释放事件
            guard let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
                LogManager.shared.error("ClipboardManager", "模拟按键失败：无法创建Cmd释放事件")
                completion(originalSnapshot)
                return
            }
            LogManager.shared.debug("ClipboardManager", "已创建Cmd释放事件")

            // 发送事件
            LogManager.shared.debug("ClipboardManager", "开始发送按键事件")
            cmdDown.post(tap: .cghidEventTap)
            LogManager.shared.debug("ClipboardManager", "已发送Cmd按下事件")
            Thread.sleep(forTimeInterval: keyPressDelay) // 按键按下间隔
            cDown.post(tap: .cghidEventTap)
            LogManager.shared.debug("ClipboardManager", "已发送C按下事件")
            Thread.sleep(forTimeInterval: keyHoldDelay)  // 按键按下保持时间
            cUp.post(tap: .cghidEventTap)
            LogManager.shared.debug("ClipboardManager", "已发送C释放事件")
            Thread.sleep(forTimeInterval: keyPressDelay)
            cmdUp.post(tap: .cghidEventTap)
            LogManager.shared.debug("ClipboardManager", "已发送Cmd释放事件，按键模拟完成")

            // 延长延迟时间，确保系统有足够时间处理复制操作并更新剪贴板
            LogManager.shared.debug("ClipboardManager", "等待 \(self.initialReadDelay)s 后读取剪贴板")
            DispatchQueue.main.asyncAfter(deadline: .now() + initialReadDelay) {
                completion(originalSnapshot)
            }
        }
    }

    /// 写入文本到剪贴板
    /// - Parameter text: 要写入的文本
    func writeToClipboard(_ text: String) {
        clipboardQueue.async { [weak self] in
            guard let self = self else { return }

            // 检查内容是否与当前剪贴板相同
            if self.getClipboardContent() == text {
                LogManager.shared.debug("ClipboardManager", "剪贴板内容相同，跳过更新")
                return
            }

            // NSPasteboard操作必须在主线程执行
            let success = DispatchQueue.main.sync { [weak self] () -> Bool in
                guard let self = self else { return false }

                self.pasteboard.clearContents()
                return self.pasteboard.setString(text, forType: .string)
            }

            if success {
                let truncatedText = text.count > 200 ? "\(text.prefix(200))..." : text
                LogManager.shared.info("ClipboardManager", "已复制到剪贴板，长度: \(text.count)，内容: \(truncatedText)")
                DispatchQueue.main.async {
                    self.onCopySuccess?(text)
                    self.showToastIfNeeded()
                }
            } else {
                LogManager.shared.error("ClipboardManager", "写入剪贴板失败")
                DispatchQueue.main.async {
                    self.onCopyFailure?("写入剪贴板失败")
                }
            }
        }
    }

    /// 获取当前剪贴板内容
    /// - Returns: 剪贴板中的文本内容
    func getClipboardContent() -> String? {
        // 内部直接访问方法，必须在主线程中调用
        func unsafeGetClipboardContent() -> String? {
            pasteboard.string(forType: .string)
        }

        // 判断当前是否已经在主线程
        if Thread.isMainThread {
            return unsafeGetClipboardContent()
        } else {
            return DispatchQueue.main.sync {
                unsafeGetClipboardContent()
            }
        }
    }

    // 用于标记clipboardQueue的特定key
    private static let queueKey = DispatchSpecificKey<Void>()

    // MARK: - 私有方法

    /// 判断字符串是否全部由空白字符组成
    private func isAllWhitespace(_ string: String) -> Bool {
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 恢复剪贴板内容到原始状态
    private func restoreOriginalContent(_ originalSnapshot: PasteboardSnapshot?) {
        guard let snapshot = originalSnapshot else {
            // 原始快照为空，清空剪贴板
            DispatchQueue.main.sync {
                self.pasteboard.clearContents()
            }
            LogManager.shared.debug("ClipboardManager", "原始快照为空，已清空剪贴板")
            return
        }

        // 恢复原始快照的所有内容
        DispatchQueue.main.sync {
            snapshot.restore(to: self.pasteboard)
        }
        LogManager.shared.debug("ClipboardManager", "已恢复原剪贴板所有内容")
    }

    /// 使用模拟快捷键执行复制
    private func performCopyWithSimulatedShortcut(retryCount: Int = 0) {
        LogManager.shared.debug("ClipboardManager", "使用模拟快捷键模式复制，尝试次数: \(retryCount + 1)")

        self.simulateCopyShortcut { [weak self] originalSnapshot in
            guard let self = self else { return }

            // 指数退避延迟：重试次数越多，等待时间越长
            let readDelay = self.initialReadDelay + (TimeInterval(retryCount) * self.retryBaseDelay * 2)
            DispatchQueue.global().asyncAfter(deadline: .now() + readDelay) { [weak self] in
                guard let self = self else { return }

                let originalContent = originalSnapshot?.stringContent
                let newSnapshot = PasteboardSnapshot.fromCurrent(self.pasteboard)

                // 输出剪贴板详细信息
                LogManager.shared.debug("ClipboardManager", "读取到新的剪贴板快照，item数量: \(newSnapshot.items.count)")
                for (index, item) in newSnapshot.items.enumerated() {
                    let typeNames = item.keys.map { $0.rawValue }.joined(separator: ", ")
                    LogManager.shared.debug("ClipboardManager", "Item \(index) 包含类型: \(typeNames)")
                }

                // 处理非文本内容场景
                guard let newContent = newSnapshot.stringContent else {
                    // 检查剪贴板是否有其他类型内容
                    let hasNonTextContent = !newSnapshot.items.isEmpty && newSnapshot.items.allSatisfy { item in
                        !item.keys.contains(.string)
                    }

                    if hasNonTextContent {
                        LogManager.shared.debug("ClipboardManager", "剪贴板包含非文本内容，判定为无效复制")
                        DispatchQueue.main.async {
                            self.onCopyFailure?("不支持非文本内容复制")
                        }
                        return
                    }

                    // 读取失败，重试逻辑

                    if retryCount < self.maxRetries {
                        let retryDelay = self.retryBaseDelay * pow(2, Double(retryCount)) // 指数退避：0.05s, 0.1s, 0.2s...
                        LogManager.shared.debug("ClipboardManager", "读取剪贴板失败，准备第\(retryCount + 1)次重试，等待 \(retryDelay)s 后重试")
                        // 检查当前权限状态
                        let currentPermission = PermissionManager.shared.isAccessibilityPermissionGranted
                        LogManager.shared.debug("ClipboardManager", "重试前权限状态: \(currentPermission ? "正常" : "异常")")
                        DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay) {
                            self.performCopyWithSimulatedShortcut(retryCount: retryCount + 1)
                        }
                    } else {
                        // 最终失败时检查权限状态
                        let permissionGranted = PermissionManager.shared.isAccessibilityPermissionGranted
                        let errorMessage = permissionGranted ? "读取剪贴板失败" : "辅助功能权限已失效，请重新授权"
                        LogManager.shared.error("ClipboardManager", "读取剪贴板最终失败，已重试\(self.maxRetries)次，最终权限状态: \(permissionGranted)")

                        // 如果是权限失效，主动引导用户授权
                        if !permissionGranted {
                            DispatchQueue.main.async {
                                PermissionManager.shared.requestAccessibilityPermission()
                            }
                        }

                        DispatchQueue.main.async {
                            self.onCopyFailure?(errorMessage)
                        }
                    }
                    return
                }

                // 检查是否为空内容或者全是空白字符
                if newContent.isEmpty || self.isAllWhitespace(newContent) {
                    LogManager.shared.debug("ClipboardManager", "复制到空内容或全空白内容，判定为无效复制")
                    // 恢复前检查剪贴板是否被其他操作修改
                    let currentSnapshot = PasteboardSnapshot.fromCurrent(self.pasteboard)
                    if currentSnapshot == newSnapshot {
                        self.restoreOriginalContent(originalSnapshot)
                    }
                    DispatchQueue.main.async {
                        self.onCopyFailure?("没有选中文本")
                    }
                    return
                }

                // 完整快照对比：内容没有变化
                if newSnapshot == originalSnapshot {
                    LogManager.shared.debug("ClipboardManager", "新快照与原始快照完全相同，内容没有变化")
                    LogManager.shared.debug("ClipboardManager", "原始内容: \(originalContent ?? "空")，新内容: \(newContent)")
                    LogManager.shared.debug("ClipboardManager", "内容和当前剪贴板相同，跳过重复复制")

                    if retryCount < self.maxRetries {
                        let retryDelay = self.retryBaseDelay * pow(2, Double(retryCount)) // 指数退避
                        LogManager.shared.debug("ClipboardManager", "剪贴板内容未变化，准备第\(retryCount + 1)次重试，等待 \(retryDelay)s 后重试")
                        // 检查当前权限状态
                        let currentPermission = PermissionManager.shared.isAccessibilityPermissionGranted
                        LogManager.shared.debug("ClipboardManager", "重试前权限状态: \(currentPermission ? "正常" : "异常")")
                        DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay) {
                            self.performCopyWithSimulatedShortcut(retryCount: retryCount + 1)
                        }
                    } else {
                        // 最终失败时检查权限状态
                        let permissionGranted = PermissionManager.shared.isAccessibilityPermissionGranted
                        LogManager.shared.debug("ClipboardManager", "剪贴板内容未变化，可能没有选中文本，已重试\(self.maxRetries)次，最终权限状态: \(permissionGranted)")
                        DispatchQueue.main.async {
                            self.onCopyFailure?("没有选中文本")
                        }
                    }
                    return
                }

                let truncatedContent = newContent.count > 200 ? "\(newContent.prefix(200))..." : newContent
                LogManager.shared.info("ClipboardManager", "通过快捷键复制成功，长度: \(newContent.count)，尝试次数: \(retryCount + 1)，内容: \(truncatedContent)")
                DispatchQueue.main.async {
                    self.onCopySuccess?(newContent)
                    self.showToastIfNeeded()
                }
            }
        }
    }

    /// 显示复制成功提示
    private func showToastIfNeeded() {
        guard ConfigManager.shared.get(\.showToast) else { return }

        // UI操作必须在主线程执行
        DispatchQueue.main.async {
            ToastManager.shared.showSuccess()
            LogManager.shared.debug("ClipboardManager", "已显示复制成功提示")
        }
    }
}
