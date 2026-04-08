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
    private let toastSize = NSSize(width: 40, height: 40)
    private let animationDuration: TimeInterval = 0.15
    private let displayDuration: TimeInterval = 0.7
    private let margin: CGFloat = 20 // 距离鼠标的边距

    private init() {}

    /// 显示复制成功提示
    func showSuccess() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 如果已有toast在显示，先移除
            self.dismissToast(animated: false)

            // 创建toast面板
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: self.toastSize),
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

            // 创建视觉效果视图
            let visualEffectView = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
            visualEffectView.material = .hudWindow
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.wantsLayer = true
            visualEffectView.layer?.cornerRadius = 20
            visualEffectView.layer?.masksToBounds = true

            // 创建勾选图标
            let checkmarkLabel = NSTextField(frame: visualEffectView.bounds)
            checkmarkLabel.stringValue = "✓"
            checkmarkLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
            checkmarkLabel.textColor = .white
            checkmarkLabel.alignment = .center
            checkmarkLabel.isBezeled = false
            checkmarkLabel.isEditable = false
            checkmarkLabel.drawsBackground = false

            visualEffectView.addSubview(checkmarkLabel)
            panel.contentView?.addSubview(visualEffectView)

            // 获取鼠标位置和所在屏幕
            let mouseLocation = NSEvent.mouseLocation
            let targetScreen = self.screenForMouseLocation(mouseLocation) ?? NSScreen.main
            guard let screen = targetScreen else { return }

            // 转换坐标系统（从Quartz坐标到AppKit坐标）
            let adjustedMouseY = screen.frame.height - mouseLocation.y + screen.frame.origin.y

            // 计算toast位置：鼠标右上角
            var toastX = mouseLocation.x + self.margin
            var toastY = adjustedMouseY + self.margin

            // 确保toast不会超出屏幕边界
            let screenVisibleFrame = screen.visibleFrame
            if toastX + self.toastSize.width > screenVisibleFrame.maxX {
                toastX = mouseLocation.x - self.margin - self.toastSize.width
            }
            if toastY + self.toastSize.height > screenVisibleFrame.maxY {
                toastY = adjustedMouseY - self.margin - self.toastSize.height
            }

            // 确保不会低于屏幕底部
            if toastY < screenVisibleFrame.minY {
                toastY = screenVisibleFrame.minY + self.margin
            }
            // 确保不会超出屏幕左侧
            if toastX < screenVisibleFrame.minX {
                toastX = screenVisibleFrame.minX + self.margin
            }

            panel.setFrameOrigin(NSPoint(x: toastX, y: toastY))

            self.toastPanel = panel

            // 入场动画
            panel.alphaValue = 0
            panel.contentView?.layer?.transform = CATransform3DScale(CATransform3DIdentity, 0.8, 0.8, 1.0)
            panel.orderFrontRegardless() // 确保在最前面显示

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = self.animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 1
            }, completionHandler: { [weak self] in
                guard let self = self else { return }

                // 缩放动画
                let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
                scaleAnimation.fromValue = 0.8
                scaleAnimation.toValue = 1.0
                scaleAnimation.duration = self.animationDuration
                scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.contentView?.layer?.add(scaleAnimation, forKey: "scaleAnimation")
                panel.contentView?.layer?.transform = CATransform3DIdentity

                // 停留后退场
                DispatchQueue.main.asyncAfter(deadline: .now() + self.displayDuration) {
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

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = animationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                panel.close()
                self?.toastPanel = nil
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
            panel.close()
            toastPanel = nil
        }
    }
}
