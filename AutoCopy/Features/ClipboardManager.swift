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

    private init() {}

    // MARK: - 公共接口

    /// 执行复制操作
    /// - Parameter useAXAPI: 是否优先使用AXAPI获取选中文本
    func performCopy(useAXAPI: Bool = true) {
        clipboardQueue.async { [weak self] in
            guard let self = self else { return }

            if useAXAPI, PermissionManager.shared.hasAccessibilityPermission {
                self.performCopyWithAXAPI()
            } else {
                self.performCopyWithSimulatedShortcut()
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

            self.pasteboard.clearContents()
            let success = self.pasteboard.setString(text, forType: .string)

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
        clipboardQueue.sync {
            pasteboard.string(forType: .string)
        }
    }

    // MARK: - 私有方法

    /// 使用AXAPI执行复制
    private func performCopyWithAXAPI(retryCount: Int = 0) {
        let maxRetries = 1 // 最多重试1次
        LogManager.shared.debug("ClipboardManager", "使用AXAPI模式复制，尝试次数: \(retryCount + 1)")

        guard let selectedText = AccessibilityManager.shared.getSelectedText() else {
            if retryCount < maxRetries {
                LogManager.shared.debug("ClipboardManager", "AXAPI获取文本失败，准备重试")
                // 短暂延迟后重试
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self = self else { return }
                    self.performCopyWithAXAPI(retryCount: retryCount + 1)
                }
            } else {
                LogManager.shared.debug("ClipboardManager", "AXAPI获取文本失败，已重试\(maxRetries)次，降级到模拟快捷键模式")
                performCopyWithSimulatedShortcut()
            }
            return
        }

        guard !selectedText.isEmpty else {
            if retryCount < maxRetries {
                LogManager.shared.debug("ClipboardManager", "没有选中文本，准备重试")
                // 短暂延迟后重试
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard let self = self else { return }
                    self.performCopyWithAXAPI(retryCount: retryCount + 1)
                }
            } else {
                LogManager.shared.debug("ClipboardManager", "没有选中文本，已重试\(maxRetries)次，降级到模拟快捷键模式")
                performCopyWithSimulatedShortcut()
            }
            return
        }

        LogManager.shared.info("ClipboardManager", "通过AXAPI复制成功，长度: \(selectedText.count)，尝试次数: \(retryCount + 1)")
        writeToClipboard(selectedText)
    }

    /// 使用模拟快捷键执行复制
    private func performCopyWithSimulatedShortcut(retryCount: Int = 0) {
        let maxRetries = 2 // 最多重试2次，总共尝试3次
        LogManager.shared.debug("ClipboardManager", "使用模拟快捷键模式复制，尝试次数: \(retryCount + 1)")

        // 保存当前剪贴板内容
        let originalContent = getClipboardContent()

        AccessibilityManager.shared.simulateCopyShortcut { [weak self] in
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

        ToastManager.shared.showSuccess()
        LogManager.shared.debug("ClipboardManager", "已显示复制成功提示")
    }
}
