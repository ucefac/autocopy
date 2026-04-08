//
//  AutoCopyApp.swift
//  AutoCopy
//
//  Created by Claude on 2024/4/8.
//

import SwiftUI
import AppKit

@main
struct AutoCopyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private let appCoordinator = AppCoordinator.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置应用为代理应用（无Dock图标）
        NSApp.setActivationPolicy(.accessory)

        // 启动应用协调器
        appCoordinator.start()

        LogManager.shared.info("AutoCopyApp", "应用启动完成")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 执行应用关闭流程
        appCoordinator.shutdown()
    }
}