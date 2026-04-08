//
//  ClickDetector.swift
//  AutoCopy
//
//  Created by Claude on 2024/4/8.
//

import Foundation
import AppKit

/// 检测到的点击类型
enum ClickDetectionType: String, Codable {
    case single
    case double
    case triple
    case drag
}

final class ClickDetector {
    static let shared = ClickDetector()

    /// 点击检测结果回调
    var onDetectionResult: ((ClickDetectionType, MouseClickEvent) -> Void)?

    private let detectionQueue = DispatchQueue(label: "com.autocopy.clickDetector", qos: .utility)

    // 点击状态
    private var clickCount: Int = 0
    private var lastClickLocation: NSPoint = .zero
    private var lastClickTimestamp: TimeInterval = 0
    private var mouseDownLocation: NSPoint = .zero
    private var mouseDownTimestamp: TimeInterval = 0
    private var isDragging: Bool = false
    private var dragThreshold: CGFloat = CGFloat(Constants.DefaultConfig.maxClickOffset)

    // 防抖定时器
    private var debounceTimer: DispatchWorkItem?
    // 重复内容防重
    private var lastCopiedText: String?
    private var lastCopyTime: TimeInterval = 0
    private let duplicateCopyInterval: TimeInterval = 1.0 // 1秒内相同内容不重复复制

    private init() {
        // 监听配置变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configDidChange),
            name: NSNotification.Name("ConfigDidChange"),
            object: nil
        )

        // 绑定事件监听器回调
        setupEventListeners()
    }

    /// 设置事件监听器回调
    private func setupEventListeners() {
        EventListener.shared.onClickDetected = { [weak self] event in
            guard let self = self else { return }
            self.handleClickEvent(event)
        }

        EventListener.shared.onDragDetected = { [weak self] startLocation, endLocation in
            guard let self = self else { return }
            self.handleDragEvent(start: startLocation, end: endLocation)
        }
    }

    // MARK: - 事件处理

    /// 处理点击事件
    private func handleClickEvent(_ event: MouseClickEvent) {
        detectionQueue.async { [weak self] in
            guard let self = self else { return }

            // 取消之前的防抖任务
            self.debounceTimer?.cancel()

            let maxOffset = CGFloat(ConfigManager.shared.get(\.maxClickOffset))
            let clickInterval = ConfigManager.shared.get(\.doubleClickInterval)

            // 检查是否是连续点击
            let timeSinceLastClick = event.timestamp - self.lastClickTimestamp
            let distance = self.distanceBetween(event.location, self.lastClickLocation)

            if timeSinceLastClick <= clickInterval && distance <= maxOffset {
                self.clickCount = min(self.clickCount + 1, 3)
            } else {
                self.clickCount = 1
            }

            self.lastClickLocation = event.location
            self.lastClickTimestamp = event.timestamp

            // 创建防抖任务，等待更多点击
            let detectionType: ClickDetectionType
            switch self.clickCount {
            case 1: detectionType = .single
            case 2: detectionType = .double
            case 3: detectionType = .triple
            default: detectionType = .single
            }

            // 只有双击、三击才触发复制，单击不触发
            guard detectionType != .single else { return }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.detectionQueue.async {
                    self.onDetectionResult?(detectionType, event)
                }
            }

            self.debounceTimer = workItem
            self.detectionQueue.asyncAfter(deadline: .now() + clickInterval, execute: workItem)
        }
    }

    /// 处理拖拽事件
    private func handleDragEvent(start: NSPoint, end: NSPoint) {
        detectionQueue.async { [weak self] in
            guard let self = self else { return }

            // 取消点击防抖
            self.debounceTimer?.cancel()
            self.debounceTimer = nil

            // 重置点击计数
            self.clickCount = 0

            let event = MouseClickEvent(
                location: end,
                timestamp: Date.timeIntervalSinceReferenceDate,
                clickType: .single,
                pressDuration: 0
            )

            self.onDetectionResult?(.drag, event)
            LogManager.shared.debug("ClickDetector", "检测到拖拽选择，从 \(start) 到 \(end)")
        }
    }

    // MARK: - Private Methods

    /// 计算两个点之间的距离
    private func distanceBetween(_ point1: NSPoint, _ point2: NSPoint) -> CGFloat {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }

    /// 配置变化时更新参数
    @objc private func configDidChange() {
        detectionQueue.async { [weak self] in
            guard let self = self else { return }
            self.dragThreshold = CGFloat(ConfigManager.shared.get(\.maxClickOffset))
            LogManager.shared.debug("ClickDetector", "配置已更新，拖拽阈值: \(self.dragThreshold)px")
        }
    }

    deinit {
        debounceTimer?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}

extension ClickDetectionType: CustomStringConvertible {
    var description: String {
        switch self {
        case .single: return "单"
        case .double: return "双"
        case .triple: return "三"
        case .drag: return "拖拽"
        }
    }
}
