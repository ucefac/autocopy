//
//  ClipboardManager.swift
//  AutoCopy
//
//  Created by Claude on 2024/4/8.
//

import Foundation
import AppKit

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
    private func simulateCopyShortcut(completion: @escaping () -> Void) {
        // 所有CGEvent操作必须在主线程执行
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion()
                return
            }

            let source = CGEventSource(stateID: .hidSystemState)

            // 创建Cmd按下事件
            guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true) else {
                completion()
                return
            }
            cmdDown.flags = .maskCommand

            // 创建C按下事件
            guard let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) else {
                completion()
                return
            }
            cDown.flags = .maskCommand

            // 创建C释放事件
            guard let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) else {
                completion()
                return
            }
            cUp.flags = .maskCommand

            // 创建Cmd释放事件
            guard let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
                completion()
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: completion)
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
                LogManager.shared.info("ClipboardManager", "已复制到剪贴板，长度: \(text.count)")
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


    /// 使用模拟快捷键执行复制
    private func performCopyWithSimulatedShortcut(retryCount: Int = 0) {
        let maxRetries = 2 // 最多重试2次，总共尝试3次
        LogManager.shared.debug("ClipboardManager", "使用模拟快捷键模式复制，尝试次数: \(retryCount + 1)")

        // 保存当前剪贴板内容
        let originalContent = getClipboardContent()

        self.simulateCopyShortcut { [weak self] in
            guard let self = self else { return }

            // 延迟后读取剪贴板内容，避免阻塞队列
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }

                guard let newContent = self.getClipboardContent() else {
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

                if newContent == originalContent {
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

                LogManager.shared.info("ClipboardManager", "通过快捷键复制成功，长度: \(newContent.count)，尝试次数: \(retryCount + 1)")
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
