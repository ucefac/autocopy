//
//  AppCoordinator.swift
//  AutoCopy
//
//  Created by AutoCopy Team on 2026/4/8.
//

import Foundation
import AppKit
import Combine

final class AppCoordinator {
    static let shared = AppCoordinator()

    // MARK: - 状态管理
    private(set) var appState = AppState()
    private var cancellables = Set<AnyCancellable>()

    /// 上次配置同步的时间，用于防抖
    private var lastSyncTime: Date?
    /// 配置同步防抖间隔（200ms）
    private let syncDebounceInterval: TimeInterval = 0.2

    // 模块引用
    private let instanceManager = InstanceManager.shared
    private let logManager = LogManager.shared
    private let configManager = ConfigManager.shared
    private let statusBarManager = StatusBarManager.shared
    private let eventListener = EventListener.shared
    private let clickDetector = ClickDetector.shared // 初始化时会自动绑定EventListener回调
    private let clipboardManager = ClipboardManager.shared
    private let toastManager = ToastManager.shared
    private let autoStartManager = AutoStartManager.shared
    private let permissionManager = PermissionManager.shared

    private init() {
        // 观察者将在 start() 中设置，避免过早接收通知
    }

    // MARK: - 应用启动流程
    func start() {
        // 1. 先设置观察者，确保能正确拦截 ConfigManager 触发的通知
        setupObservers()
        setupPermissionObservers()

        logManager.info("AppCoordinator", "应用启动开始")

        // 2. 单实例检测
        guard instanceManager.acquireLock() else {
            logManager.info("AppCoordinator", "检测到已有实例运行，退出当前实例")
            NSApplication.shared.terminate(nil)
            return
        }

        // 3. 日志系统已初始化（静态初始化）
        logManager.info("AppCoordinator", "日志系统初始化完成")

        // 4. 加载配置（ConfigManager初始化时已自动加载，这里直接读取）
        appState.autoCopyEnabled = configManager.get(\.autoCopyEnabled)
        logManager.info("AppCoordinator", "配置加载完成")

        // 5. 初始化状态栏菜单（已在StatusBarManager初始化时创建）
        logManager.info("AppCoordinator", "状态栏菜单初始化完成")

        // 6. 检查辅助功能权限
        let permissionGranted = permissionManager.checkAccessibilityPermission()
        appState.accessibilityPermissionGranted = permissionGranted
        logManager.info("AppCoordinator", "辅助功能权限状态: \(permissionGranted ? "已授权" : "未授权")")

        // 7. 初始化功能模块
        initializeModules()
        logManager.info("AppCoordinator", "所有功能模块初始化完成")

        // 8. 注册事件监听，建立事件流
        setupEventFlow()
        logManager.info("AppCoordinator", "事件流注册完成")

        // 9. 根据权限和配置状态决定是否启动服务
        if permissionGranted && appState.autoCopyEnabled {
            startServices()
        } else if !permissionGranted {
            // 权限未授权时，引导用户开启权限
            logManager.warn("AppCoordinator", "辅助功能权限未授权，自动复制功能将无法使用")
            permissionManager.requestAccessibilityPermission()
        }

        appState.isRunning = true
        appState.launchTime = Date()
        logManager.info("AppCoordinator", "应用启动完成，运行状态: \(appState.isRunning), 自动复制启用: \(appState.autoCopyEnabled), 权限已授权: \(permissionGranted)")
    }

    // MARK: - 初始化模块
    private func initializeModules() {
        // 配置同步统一由 ConfigDidChange 通知触发，这里无需主动调用
        // ConfigManager 初始化时会发送通知，AppCoordinator 会通过 setupObservers() 中的监听器处理
    }

    // MARK: - 设置事件流
    private func setupEventFlow() {
        // 点击检测结果处理
        clickDetector.onDetectionResult = { [weak self] detectionType, event in
            guard let self = self else { return }
            self.handleDetectionResult(detectionType, event: event)
        }

        // 复制成功处理
        clipboardManager.onCopySuccess = { [weak self] content in
            guard let self = self else { return }
            self.handleCopySuccess(content)
        }

        // 复制失败处理
        clipboardManager.onCopyFailure = { [weak self] reason in
            guard let self = self else { return }
            self.logManager.debug("AppCoordinator", "复制失败: \(reason)")
        }

    }

    // MARK: - 设置观察者
    private func setupObservers() {
        // 监听应用状态变化
        AppUIState.shared.$isAutoCopyEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                guard let self = self else { return }
                self.handleAutoCopyToggle(isEnabled)
            }
            .store(in: &cancellables)

        // 监听配置变化通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configDidChange),
            name: NSNotification.Name("ConfigDidChange"),
            object: nil
        )
    }

    // MARK: - 设置权限观察者
    private func setupPermissionObservers() {
        // 监听权限状态变化
        permissionManager.$isAccessibilityPermissionGranted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isGranted in
                guard let self = self else { return }
                self.handlePermissionStatusChange(isGranted)
            }
            .store(in: &cancellables)
    }

    // MARK: - 权限状态变化处理
    private func handlePermissionStatusChange(_ isGranted: Bool) {
        appState.accessibilityPermissionGranted = isGranted
        logManager.info("AppCoordinator", "辅助功能权限状态变更: \(isGranted ? "已授权" : "未授权")")

        if isGranted {
            // 权限已授权，如果自动复制功能已启用，则启动服务
            if appState.autoCopyEnabled {
                logManager.info("AppCoordinator", "辅助功能权限已获得，启动自动复制服务")
                startServices()
            }
        } else {
            // 权限已撤销，停止服务
            if eventListener.isListening {
                logManager.warn("AppCoordinator", "辅助功能权限已被撤销，停止自动复制服务")
                stopServices()
            }
        }
    }

    // MARK: - 事件处理
    private func handleDetectionResult(_ type: ClickDetectionType, event: MouseClickEvent) {
        guard appState.autoCopyEnabled else {
            logManager.debug("AppCoordinator", "功能已禁用，跳过复制")
            return
        }

        // 只处理双击、三击和拖拽选择
        switch type {
        case .double, .triple, .drag:
            logManager.info("AppCoordinator", "检测到\(type.description)选择，开始复制流程")
            clipboardManager.performCopy()
        case .single:
            // 单击不处理
            break
        }
    }

    private func handleCopySuccess(_ content: String) {
        appState.copyCount += 1
        logManager.info("AppCoordinator", "复制成功，累计复制次数: \(appState.copyCount)")

        // 显示Toast提示
    }


    private func handleAutoCopyToggle(_ isEnabled: Bool) {
        appState.autoCopyEnabled = isEnabled
        configManager.update(\.autoCopyEnabled, to: isEnabled)
        logManager.info("AppCoordinator", "自动复制功能已\(isEnabled ? "启用" : "禁用")")

        if isEnabled {
            if appState.accessibilityPermissionGranted {
                startServices()
            } else {
                logManager.warn("AppCoordinator", "辅助功能权限未授权，无法启用自动复制功能")
                // 引导用户开启权限
                permissionManager.requestAccessibilityPermission()
            }
        } else {
            stopServices()
        }
    }

    // MARK: - 服务控制
    private func startServices() {
        guard !eventListener.isListening else { return }
        // 只有在权限已授权的情况下才启动服务
        guard appState.accessibilityPermissionGranted else {
            logManager.warn("AppCoordinator", "辅助功能权限未授权，无法启动事件监听服务")
            return
        }
        eventListener.start()
        logManager.info("AppCoordinator", "事件监听服务已启动")
    }

    private func stopServices() {
        guard eventListener.isListening else { return }
        eventListener.stop()
        logManager.info("AppCoordinator", "事件监听服务已停止")
    }

    // MARK: - 配置同步
    private func syncConfigToModules() {
        let config = configManager.config

        // 同步日志级别
        logManager.setLogLevel(config.logLevel)

        // 同步排除的应用列表
        EventListener.shared.updateExcludedAppIDs(Set(config.excludedApps))

        // 同步点击检测参数
        // ClickDetector会通过配置通知自动更新

        // 同步事件监听参数
        // EventListener会通过ConfigManager实时读取
    }

    @objc private func configDidChange() {
        // 防抖处理：如果最近刚同步过（200ms内），则跳过
        if let lastSync = lastSyncTime, Date().timeIntervalSince(lastSync) < syncDebounceInterval {
            logManager.debug("AppCoordinator", "配置同步防跳过，间隔小于\(syncDebounceInterval)s)")
            return
        }

        logManager.debug("AppCoordinator", "检测到配置变化，同步到所有模块")
        lastSyncTime = Date()
        syncConfigToModules()

        // 更新应用状态
        appState.autoCopyEnabled = configManager.get(\.autoCopyEnabled)

        // 根据新配置调整服务状态
        if appState.autoCopyEnabled {
            startServices()
        } else {
            stopServices()
        }
    }

    // MARK: - 应用退出处理
    func shutdown() {
        logManager.info("AppCoordinator", "应用开始关闭")

        // 停止服务
        stopServices()

        // 释放实例锁
        instanceManager.releaseLock()

        appState.isRunning = false
        logManager.info("AppCoordinator", "应用已正常关闭，运行时长: \(String(format: "%.1f", Date().timeIntervalSince(appState.launchTime)))s, 累计复制: \(appState.copyCount)次")
    }
}

