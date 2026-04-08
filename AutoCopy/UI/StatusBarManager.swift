//
//  StatusBarManager.swift
//  AutoCopy
//
//  Created by AutoCopy Team on 2026/4/8.
//

import Cocoa

class AppUIState: ObservableObject {
    static let shared = AppUIState()
    @Published var isAutoCopyEnabled = true
    @Published var isAccessibilityPermissionGranted = false
}

class StatusBarManager: NSObject {
    static let shared = StatusBarManager()

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var autoCopyMenuItem: NSMenuItem?
    private var autoStartMenuItem: NSMenuItem?
    private var permissionStatusMenuItem: NSMenuItem?

    private override init() {
        super.init()
        setupStatusBar()
        setupMenu()
        updateUI()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }

        let iconName = AppUIState.shared.isAutoCopyEnabled ? "doc.on.clipboard" : "doc.on.clipboard.slash"
        if #available(macOS 11.0, *) {
            let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "AutoCopy")
            button.image = image
        } else {
            // 兼容旧版本，使用自定义图标
            button.image = NSImage(named: "StatusBarIcon")
        }
        button.image?.isTemplate = true
    }

    private func setupMenu() {
        menu = NSMenu()
        menu?.delegate = self

        // 自动复制开关
        autoCopyMenuItem = NSMenuItem(
            title: "启用自动复制",
            action: #selector(toggleAutoCopy(_:)),
            keyEquivalent: ""
        )
        autoCopyMenuItem?.target = self
        menu?.addItem(autoCopyMenuItem!)

        // 权限状态提示
        permissionStatusMenuItem = NSMenuItem(
            title: "⚠️ 需要辅助功能权限",
            action: #selector(openAccessibilitySettings(_:)),
            keyEquivalent: ""
        )
        permissionStatusMenuItem?.target = self
        menu?.addItem(permissionStatusMenuItem!)

        menu?.addItem(NSMenuItem.separator())

        // 编辑配置
        let editConfigMenuItem = NSMenuItem(
            title: "编辑配置",
            action: #selector(editConfig(_:)),
            keyEquivalent: ","
        )
        editConfigMenuItem.target = self
        menu?.addItem(editConfigMenuItem)

        // 开机启动开关
        autoStartMenuItem = NSMenuItem(
            title: "开机启动",
            action: #selector(toggleAutoStart(_:)),
            keyEquivalent: ""
        )
        autoStartMenuItem?.target = self
        menu?.addItem(autoStartMenuItem!)

        menu?.addItem(NSMenuItem.separator())

        // 关于
        let aboutMenuItem = NSMenuItem(
            title: "关于 AutoCopy",
            action: #selector(showAbout(_:)),
            keyEquivalent: ""
        )
        aboutMenuItem.target = self
        menu?.addItem(aboutMenuItem)

        // 退出
        let quitMenuItem = NSMenuItem(
            title: "退出 AutoCopy",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitMenuItem.target = self
        menu?.addItem(quitMenuItem)

        statusItem?.menu = menu
    }

    private func updateUI() {
        autoCopyMenuItem?.state = AppUIState.shared.isAutoCopyEnabled ? .on : .off
        autoStartMenuItem?.state = AutoStartManager.shared.isAutoStartEnabled ? .on : .off
        autoStartMenuItem?.isEnabled = AutoStartManager.shared.isAppInApplicationsFolder

        // 更新权限状态显示
        let isPermissionGranted = PermissionManager.shared.isAccessibilityPermissionGranted
        AppUIState.shared.isAccessibilityPermissionGranted = isPermissionGranted

        if isPermissionGranted {
            permissionStatusMenuItem?.isHidden = true
        } else {
            permissionStatusMenuItem?.isHidden = false
            permissionStatusMenuItem?.title = "⚠️ 需要辅助功能权限"
        }

        updateStatusIcon()
    }

    @objc private func toggleAutoCopy(_ sender: NSMenuItem) {
        AppUIState.shared.isAutoCopyEnabled.toggle()
        updateUI()
    }

    @objc private func editConfig(_ sender: NSMenuItem) {
        let configPath = "\(NSHomeDirectory())/.config/autocopy/autocopy.ini"
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: configPath) {
            // 如果配置文件不存在，创建默认配置
            let defaultConfig = """
                # AutoCopy 配置文件
                # 双击间隔时间（秒），用于判断鼠标点击是否属于双击事件
                doubleClickInterval = 0.4
                # 最大点击偏移像素，两次点击位置偏移不超过该值才会被判定为连续点击
                maxClickOffset = 5
                # 最小按压时长（秒），鼠标按下到释放的时长低于该值才会被判定为点击
                minPressDuration = 0.5
                # 是否启用自动复制功能
                autoCopyEnabled = true
                # 是否显示复制成功的Toast提示
                showToast = true
                # 日志输出级别，可选值：debug/info/warn/error，优先级debug < info < warn < error
                logLevel = debug
                # 是否设置应用开机自动启动
                launchAtLogin = false
                """
            do {
                try fileManager.createDirectory(atPath: "\(NSHomeDirectory())/.config/autocopy", withIntermediateDirectories: true)
                try defaultConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
            } catch {
                print("创建配置文件失败: \(error)")
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
    }

    @objc private func toggleAutoStart(_ sender: NSMenuItem) {
        do {
            try AutoStartManager.shared.toggleAutoStart()
            updateUI()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "设置开机启动失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "确定")
            alert.runModal()
        }
    }

    @objc private func showAbout(_ sender: NSMenuItem) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

        let alert = NSAlert()
        alert.messageText = "AutoCopy"
        alert.informativeText = "版本 \(version) (\(build))\n\n自动复制工具，选中文本后自动复制到剪贴板。"
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }

    @objc private func openAccessibilitySettings(_ sender: NSMenuItem) {
        PermissionManager.shared.openAccessibilitySettings()
    }
}

extension StatusBarManager: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateUI()
    }
}
