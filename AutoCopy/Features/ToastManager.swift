//
//  ToastManager.swift
//  AutoCopy
//
//  Created by AutoCopy Team on 2026/4/8.
//

import Cocoa

class ToastManager {
    static let shared = ToastManager()

    private var toastPanel: NSPanel?
    private let defaultToastSize = NSSize(width: 40, height: 40)
    private let textToastSize = NSSize(width: 300, height: 60)
    private let animationDuration: TimeInterval = 0.15
    private let defaultDisplayDuration: TimeInterval = 0.7
    private let textDisplayDuration: TimeInterval = 2.0
    private let margin: CGFloat = 20 // 距离鼠标的边距

    // MARK: - 通用配置定义
    private enum ToastPosition {
        case followMouse
        case bottomCenter
    }

    private enum AnimationType {
        case scale
        case translate
    }

    private struct ToastConfiguration {
        let size: NSSize
        let cornerRadius: CGFloat
        let displayDuration: TimeInterval
        let position: ToastPosition
        let animationType: AnimationType
        let contentView: NSView
    }

    private init() {}

    /// 显示复制成功提示
    func showSuccess() {
        // 创建图标内容视图
        let iconLabel = NSTextField(frame: .zero)
        iconLabel.stringValue = "✓"
        iconLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        iconLabel.textColor = .white
        iconLabel.alignment = .center
        iconLabel.isBezeled = false
        iconLabel.isEditable = false
        iconLabel.drawsBackground = false

        // 构造配置
        let config = ToastConfiguration(
            size: defaultToastSize,
            cornerRadius: 20,
            displayDuration: defaultDisplayDuration,
            position: .followMouse,
            animationType: .scale,
            contentView: iconLabel
        )

        showToast(with: config)
    }

    /// 显示成功消息提示
    func showSuccess(message: String) {
        showTextToast(message: message, icon: "✓", iconColor: .systemGreen)
    }

    /// 显示错误消息提示
    func showError(message: String) {
        showTextToast(message: message, icon: "⚠️", iconColor: .systemYellow)
    }

    /// 显示警告消息提示
    func showWarning(message: String) {
        showTextToast(message: message, icon: "⚠️", iconColor: .systemOrange)
    }

    // MARK: - 辅助方法
    /// 创建文本类型Toast内容
    private func showTextToast(message: String, icon: String, iconColor: NSColor) {
        // 创建容器视图
        let containerView = NSView(frame: .zero)

        // 创建图标
        let iconLabel = NSTextField(frame: NSRect(x: 16, y: 15, width: 30, height: 30))
        iconLabel.stringValue = icon
        iconLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        iconLabel.textColor = iconColor
        iconLabel.alignment = .center
        iconLabel.isBezeled = false
        iconLabel.isEditable = false
        iconLabel.drawsBackground = false

        // 创建消息文本
        let messageLabel = NSTextField(frame: NSRect(x: 56, y: 10, width: textToastSize.width - 72, height: 40))
        messageLabel.stringValue = message
        messageLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        messageLabel.textColor = .white
        messageLabel.alignment = .left
        messageLabel.isBezeled = false
        messageLabel.isEditable = false
        messageLabel.drawsBackground = false
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 2

        containerView.addSubview(iconLabel)
        containerView.addSubview(messageLabel)

        // 构造配置
        let config = ToastConfiguration(
            size: textToastSize,
            cornerRadius: 12,
            displayDuration: textDisplayDuration,
            position: .bottomCenter,
            animationType: .translate,
            contentView: containerView
        )

        showToast(with: config)
    }

    // MARK: - 私有方法

    /// 统一显示Toast的公共方法
    private func showToast(with config: ToastConfiguration) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 如果已有toast在显示，先移除
            self.dismissToast(animated: false)

            // 创建toast面板（统一配置）
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: config.size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .popUpMenu // 更高的层级，确保在全屏应用上方显示
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

            // 创建视觉效果视图（统一配置，仅圆角不同）
            let visualEffectView = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
            visualEffectView.material = .hudWindow
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.wantsLayer = true
            visualEffectView.layer?.cornerRadius = config.cornerRadius
            visualEffectView.layer?.masksToBounds = true

            // 添加内容视图
            config.contentView.frame = visualEffectView.bounds
            config.contentView.autoresizingMask = [.width, .height]
            visualEffectView.addSubview(config.contentView)
            panel.contentView?.addSubview(visualEffectView)

            // 计算Toast位置
            var toastOrigin: NSPoint = .zero
            let targetScreen: NSScreen?

            switch config.position {
            case .followMouse:
                // 获取鼠标位置和所在屏幕
                let mouseLocation = NSEvent.mouseLocation
                targetScreen = self.screenForMouseLocation(mouseLocation) ?? NSScreen.main
                guard let screen = targetScreen else {
                    // 鼠标位置获取失败，降级到屏幕右下角显示
                    guard let fallbackScreen = NSScreen.main else { return }
                    toastOrigin = NSPoint(
                        x: fallbackScreen.visibleFrame.maxX - config.size.width - self.margin,
                        y: fallbackScreen.visibleFrame.minY + self.margin
                    )
                    break
                }

                // 转换坐标系统（从Quartz坐标到AppKit坐标）
                let adjustedMouseY = screen.frame.height - mouseLocation.y + screen.frame.origin.y

                // 计算toast位置：鼠标右上角
                var toastX = mouseLocation.x + self.margin
                var toastY = adjustedMouseY + self.margin

                // 确保toast不会超出屏幕边界
                let screenVisibleFrame = screen.visibleFrame
                if toastX + config.size.width > screenVisibleFrame.maxX {
                    toastX = mouseLocation.x - self.margin - config.size.width
                }
                if toastY + config.size.height > screenVisibleFrame.maxY {
                    toastY = adjustedMouseY - self.margin - config.size.height
                }

                // 确保不会低于屏幕底部
                if toastY < screenVisibleFrame.minY {
                    toastY = screenVisibleFrame.minY + self.margin
                }
                // 确保不会超出屏幕左侧
                if toastX < screenVisibleFrame.minX {
                    toastX = screenVisibleFrame.minX + self.margin
                }

                toastOrigin = NSPoint(x: toastX, y: toastY)

            case .bottomCenter:
                // 获取主屏幕
                targetScreen = NSScreen.main
                guard let screen = targetScreen else { return }

                // 计算toast位置：屏幕底部居中
                let toastX = (screen.frame.width - config.size.width) / 2
                let toastY = screen.visibleFrame.minY + 60 // 距离底部60px
                toastOrigin = NSPoint(x: toastX, y: toastY)
            }

            panel.setFrameOrigin(toastOrigin)
            self.toastPanel = panel

            // 入场动画
            panel.alphaValue = 0
            panel.orderFrontRegardless() // 确保在最前面显示

            switch config.animationType {
            case .scale:
                panel.contentView?.layer?.transform = CATransform3DScale(CATransform3DIdentity, 0.8, 0.8, 1.0)
            case .translate:
                panel.contentView?.layer?.transform = CATransform3DTranslate(CATransform3DIdentity, 0, 20, 0)
            }

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = self.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 1
            }, completionHandler: { [weak self] in
                guard let self = self else { return }

                // 类型专属动画
                switch config.animationType {
                case .scale:
                    // 缩放动画
                    let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
                    scaleAnimation.fromValue = 0.8
                    scaleAnimation.toValue = 1.0
                    scaleAnimation.duration = self.animationDuration
                    scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.contentView?.layer?.add(scaleAnimation, forKey: "scaleAnimation")
                    panel.contentView?.layer?.transform = CATransform3DIdentity

                case .translate:
                    // 平移动画
                    let translateAnimation = CABasicAnimation(keyPath: "transform.translation.y")
                    translateAnimation.fromValue = 20
                    translateAnimation.toValue = 0
                    translateAnimation.duration = self.animationDuration
                    translateAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.contentView?.layer?.add(translateAnimation, forKey: "translateAnimation")
                    panel.contentView?.layer?.transform = CATransform3DIdentity
                }

                // 停留后退场
                DispatchQueue.main.asyncAfter(deadline: .now() + config.displayDuration) { [weak self, weak panel] in
                    guard let self = self, let panel = panel else { return }
                    // 4. 验证panel身份，避免关闭新创建的toast
                    guard self.toastPanel === panel else { return }
                    self.dismissToast(animated: true)
                }
            })
        }
    }


    /// 获取鼠标所在的屏幕
    private func screenForMouseLocation(_ location: NSPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if NSMouseInRect(location, screen.frame, false) {
                return screen
            }
        }
        return nil
    }

    /// 隐藏toast
    private func dismissToast(animated: Bool) {
        guard let panel = toastPanel else { return }

        // 1. 清理所有动画和pending任务
        panel.contentView?.layer?.removeAllAnimations()
        NSAnimationContext.current.duration = 0
        panel.animator().alphaValue = panel.alphaValue // 中断当前动画

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self, weak panel] in
                guard let self = self, let panel = panel else { return }
                // 2. 验证panel身份，确保关闭的是正确的toast
                guard self.toastPanel === panel else { return }
                panel.close()
                self.toastPanel = nil
            })

            // 缩放动画
            let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
            scaleAnimation.fromValue = 1.0
            scaleAnimation.toValue = 0.5
            scaleAnimation.duration = animationDuration
            scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.contentView?.layer?.add(scaleAnimation, forKey: "scaleAnimation")
            panel.contentView?.layer?.transform = CATransform3DScale(CATransform3DIdentity, 0.5, 0.5, 1.0)
        } else {
            // 3. 非动画路径也验证panel身份
            guard toastPanel === panel else { return }
            panel.close()
            toastPanel = nil
        }
    }
}
