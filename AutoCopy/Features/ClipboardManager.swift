//
//  ClipboardManager.swift
//  AutoCopy
//
//  Created by Claude on 2024/4/8.
//

import Foundation
import AppKit

/// 剪贴板内容快照，用于保存和恢复剪贴板的所有内容
private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Any]]

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
            }
        }
        return nil
    }
}

final class ClipboardManager {
    static let shared = ClipboardManager()

    private let clipboardQueue = DispatchQueue(label: "com.autocopy.clipboardManager", qos: .userInitiated)
    private let pasteboard = NSPasteboard.general

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
                completion(nil)
                return
            }

            // 发送按键前立刻保存原始剪贴板快照，最小化时间差，减少竞态条件
            let originalSnapshot = PasteboardSnapshot.fromCurrent(self.pasteboard)

            let source = CGEventSource(stateID: .hidSystemState)

            // 创建Cmd按下事件
            guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) else {
                completion(originalSnapshot)
                return
            }
            cmdDown.flags = .maskCommand

            // 创建C按下事件
            guard let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) else {
                completion(originalSnapshot)
                return
            }
        
            cDown.flags = .maskCommand

            // 创建C释放事件
            guard let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else {
                completion(originalSnapshot)
                return
            }
            cUp.flags = .maskCommand

            // 创建Cmd释放事件
            guard let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
                completion(originalSnapshot)
                return
            }

            // 发送事件
            cmdDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.005) // 小延迟确保按键顺序正确
            cDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.01)  // 按键按下保持时间
            cUp.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.005)
            cmdUp.post(tap: .cghidEventTap)

            // 延长延迟时间，确保系统有足够时间处理复制操作并更新剪贴板
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
        let maxRetries = 2 // 最多重试2次，总共尝试3次
        LogManager.shared.debug("ClipboardManager", "使用模拟快捷键模式复制，尝试次数: \(retryCount + 1)")

        self.simulateCopyShortcut { [weak self] originalSnapshot in
            guard let self = self else { return }

            // 延迟后读取剪贴板内容，避免阻塞队列
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }

                let originalContent = originalSnapshot?.stringContent
                guard let newContent = self.getClipboardContent() else {
                    // 读取失败，恢复原内容
                    self.restoreOriginalContent(originalSnapshot)

                    if retryCount < maxRetries {
                        LogManager.shared.debug("ClipboardManager", "读取剪贴板失败，准备重试")
                        // 短暂延迟后重试
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                            self.performCopyWithSimulatedShortcut(retryCount: retryCount + 1)
                        }
                    } else {
                        LogManager.shared.error("ClipboardManager", "读取剪贴板失败，已重试\(maxRetries)次")
                        DispatchQueue.main.async {
                            self.onCopyFailure?("读取剪贴板失败")
                        }
                    }
                    return
                }

                // 检查是否为空内容或者全是空白字符
                if newContent.isEmpty || self.isAllWhitespace(newContent) {
                    LogManager.shared.debug("ClipboardManager", "复制到空内容或全空白内容，判定为无效复制")
                    // 恢复原剪贴板内容
                    self.restoreOriginalContent(originalSnapshot)

                    DispatchQueue.main.async {
                        self.onCopyFailure?("没有选中文本")
                    }
                    return
                }

                if newContent == originalContent {
                    // 内容没有变化，恢复原内容
                    self.restoreOriginalContent(originalSnapshot)

                    if retryCount < maxRetries {
                        LogManager.shared.debug("ClipboardManager", "剪贴板内容未变化，准备重试")
                        // 短暂延迟后重试
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                            self.performCopyWithSimulatedShortcut(retryCount: retryCount + 1)
                        }
                    } else {
                        LogManager.shared.debug("ClipboardManager", "剪贴板内容未变化，可能没有选中文本，已重试\(maxRetries)次")
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
