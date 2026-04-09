//
//  EventListener.swift
//  AutoCopy
//
//  Created by Claude on 2024/4/8.
//

import Foundation
import AppKit

final class EventListener {
    static let shared = EventListener()

    private let eventQueue = DispatchQueue(label: "com.autocopy.eventListener", qos: .utility)
    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private var mouseDraggedMonitor: Any?

    private(set) var isListening: Bool = false
    private var lastClickLocation: NSPoint = .zero
    private var lastClickTime: TimeInterval = 0
    private var clickCount: Int = 0
    private var isDragging: Bool = false
    private var mouseDownTime: TimeInterval = 0
    private var mouseDownLocation: NSPoint = .zero

    /// 点击事件回调
    var onClickDetected: ((MouseClickEvent) -> Void)?

    /// 拖拽事件回调
    var onDragDetected: ((NSPoint, NSPoint) -> Void)?

    /// 排除的应用Bundle ID列表
    private var excludedAppIDs: Set<String> = []

    /// 前台应用缓存
    private var lastFrontAppID: String?
    private var lastFrontAppCheckTime: TimeInterval = 0
    private let frontAppCacheDuration: TimeInterval = 0.5 // 500ms缓存

    private init() {}

    // MARK: - 公共接口

    /// 启动事件监听
    func start() {
        guard !isListening else {
            LogManager.shared.debug("EventListener", "事件监听器已经在运行")
            return
        }

        // 检查是否有辅助功能权限
        guard PermissionManager.shared.isAccessibilityPermissionGranted else {
            LogManager.shared.error("EventListener", "无法启动事件监听器：辅助功能权限未授权")
            return
        }

        eventQueue.async { [weak self] in
            guard let self = self else { return }
            self.setupEventMonitors()
            self.isListening = true
            LogManager.shared.info("EventListener", "事件监听器已启动")
            // 注意：排除的应用列表由AppCoordinator的syncConfigToModules()统一处理
        }
    }

    /// 停止事件监听
    func stop() {
        guard isListening else { return }

        eventQueue.async { [weak self] in
            guard let self = self else { return }
            self.removeEventMonitors()
            self.isListening = false
            LogManager.shared.info("EventListener", "事件监听器已停止")
        }
    }

    /// 更新排除应用列表
    /// - Parameter appIDs: 要排除的应用Bundle ID集合
    /// - 注意：只有当列表真正发生变化时才更新并打印日志，相同列表直接返回
    func updateExcludedAppIDs(_ appIDs: Set<String>) {
        eventQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            // 比较集合是否真正变化，只有变化时才更新
            guard appIDs != self.excludedAppIDs else {
                return // 列表相同，直接返回，避免重复打印日志
            }
            self.excludedAppIDs = appIDs
            LogManager.shared.debug("EventListener", "已更新排除应用列表，共\(appIDs.count)个应用")
        }
    }

    // MARK: - 私有方法

    /// 设置事件监听器
    private func setupEventMonitors() {
        // 监听鼠标按下事件
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self else { return }
            self.handleMouseDown(event)
        }

        // 监听鼠标释放事件
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self = self else { return }
            self.handleMouseUp(event)
        }

        // 监听鼠标拖拽事件
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self = self else { return }
            self.handleMouseDragged(event)
        }
    }

    /// 移除事件监听器
    private func removeEventMonitors() {
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }

        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }

        if let monitor = mouseDraggedMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDraggedMonitor = nil
        }
    }

    /// 处理鼠标按下事件
    private func handleMouseDown(_ event: NSEvent) {
        eventQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            // 检查当前应用是否在排除列表中
            guard !self.isCurrentAppExcluded() else { return }

            self.mouseDownTime = Date.timeIntervalSinceReferenceDate
            self.mouseDownLocation = event.locationInWindow
            self.isDragging = false
        }
    }

    /// 处理鼠标释放事件
    private func handleMouseUp(_ event: NSEvent) {
        eventQueue.async { [weak self] in
            guard let self = self else { return }

            // 检查当前应用是否在排除列表中
            guard !self.isCurrentAppExcluded() else { return }

            let mouseUpTime = Date.timeIntervalSinceReferenceDate
            let mouseUpLocation = event.locationInWindow
            let pressDuration = mouseUpTime - self.mouseDownTime

            if self.isDragging {
                // 处理拖拽结束，只有启用拖拽复制时才触发
                if ConfigManager.shared.get(\.enableDragCopy) {
                    self.onDragDetected?(self.mouseDownLocation, mouseUpLocation)
                }
            } else {
                // 处理点击
                let clickType = self.calculateClickType(location: mouseUpLocation, timestamp: mouseUpTime)
                let clickEvent = MouseClickEvent(
                    location: mouseUpLocation,
                    timestamp: mouseUpTime,
                    clickType: clickType,
                    pressDuration: pressDuration
                )

                self.onClickDetected?(clickEvent)
            }

            // 重置状态
            self.isDragging = false
        }
    }

    /// 处理鼠标拖拽事件
    private func handleMouseDragged(_ event: NSEvent) {
        eventQueue.async { [weak self] in
            guard let self = self else { return }

            // 已经判定为拖拽时，不需要重复处理
            guard !self.isDragging else { return }

            // 检查当前应用是否在排除列表中
            guard !self.isCurrentAppExcluded() else { return }

            let currentTime = Date.timeIntervalSinceReferenceDate
            let dragDuration = currentTime - self.mouseDownTime
            let dragOffset = self.calculateOffset(from: self.mouseDownLocation, to: event.locationInWindow)
            let maxOffset = ConfigManager.shared.get(\.maxClickOffset)

            // 如果拖拽时长超过最小按压时长或者偏移超过最大点击偏移，判定为拖拽
            if dragDuration > ConfigManager.shared.get(\.minPressDuration) || dragOffset > maxOffset {
                self.isDragging = true
                LogManager.shared.debug("EventListener", "检测到拖拽开始，偏移: \(dragOffset)px，时长: \(String(format: "%.2f", dragDuration))s")
            }
        }
    }

    /// 计算点击类型
    private func calculateClickType(location: NSPoint, timestamp: TimeInterval) -> ClickType {
        let maxOffset = ConfigManager.shared.get(\.maxClickOffset)
        let maxInterval = ConfigManager.shared.get(\.doubleClickInterval)

        // 计算与上一次点击的偏移和时间差
        let offset = calculateOffset(from: lastClickLocation, to: location)
        let timeInterval = timestamp - lastClickTime

        if offset <= maxOffset && timeInterval <= maxInterval {
            // 连续点击，计数加1
            clickCount = min(clickCount + 1, 3)
        } else {
            // 新的点击序列
            clickCount = 1
        }

        // 更新最后一次点击信息
        lastClickLocation = location
        lastClickTime = timestamp

        switch clickCount {
        case 1: return .single
        case 2: return .double
        case 3: return .triple
        default: return .single
        }
    }

    /// 计算两个点之间的像素偏移
    private func calculateOffset(from point1: NSPoint, to point2: NSPoint) -> Int {
        let dx = abs(point1.x - point2.x)
        let dy = abs(point1.y - point2.y)
        return Int(max(dx, dy))
    }

    /// 检查当前前台应用是否在排除列表中
    /// - Returns: 是否排除
    private func isCurrentAppExcluded() -> Bool {
        let currentTime = Date.timeIntervalSinceReferenceDate

        // 使用缓存，避免频繁调用 NSWorkspace API
        if let cachedID = lastFrontAppID, currentTime - lastFrontAppCheckTime < frontAppCacheDuration {
            return excludedAppIDs.contains(cachedID)
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else {
            lastFrontAppID = nil
            lastFrontAppCheckTime = currentTime
            return false
        }

        // 更新缓存
        lastFrontAppID = bundleID
        lastFrontAppCheckTime = currentTime

        return excludedAppIDs.contains(bundleID)
    }

    deinit {
        stop()
    }
}
