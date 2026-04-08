//
//  AutoStartManager.swift
//  AutoCopy
//
//  Created by AutoCopy Team on 2026/4/8.
//

import Foundation
import ServiceManagement

class AutoStartManager {
    static let shared = AutoStartManager()

    private let launchAgentPlistPath: String
    private let bundleIdentifier: String
    private let appPath: String

    private init() {
        let homeDirectory = NSHomeDirectory()
        self.bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.yourname.AutoCopy"
        self.launchAgentPlistPath = "\(homeDirectory)/Library/LaunchAgents/\(bundleIdentifier).plist"
        self.appPath = Bundle.main.bundlePath
    }

    /// 检查应用是否位于/Applications目录
    var isAppInApplicationsFolder: Bool {
        return appPath.hasPrefix("/Applications/")
    }

    /// 检查开机启动是否已启用
    var isAutoStartEnabled: Bool {
        guard isAppInApplicationsFolder else { return false }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: launchAgentPlistPath) else {
            return false
        }

        do {
            let plistData = try Data(contentsOf: URL(fileURLWithPath: launchAgentPlistPath))
            if let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
               let disabled = plist["Disabled"] as? Bool {
                return !disabled
            }
            return true
        } catch {
            print("读取启动项配置失败: \(error)")
            return false
        }
    }

    /// 启用开机启动
    func enableAutoStart() throws {
        guard isAppInApplicationsFolder else {
            throw NSError(domain: "AutoStartManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "应用必须位于/Applications目录才能设置开机启动"
            ])
        }

        let plistContent: [String: Any] = [
            "Label": bundleIdentifier,
            "ProgramArguments": [appPath + "/Contents/MacOS/AutoCopy"],
            "RunAtLoad": true,
            "KeepAlive": false,
            "Disabled": false,
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": "/dev/null"
        ]

        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plistContent,
            format: .xml,
            options: 0
        )

        try plistData.write(to: URL(fileURLWithPath: launchAgentPlistPath))

        // 加载启动项
        let process = Process()
        process.launchPath = "/bin/launchctl"
        process.arguments = ["load", launchAgentPlistPath]
        process.launch()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(domain: "AutoStartManager", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "加载启动项失败，错误码: \(process.terminationStatus)"
            ])
        }
    }

    /// 禁用开机启动
    func disableAutoStart() throws {
        guard FileManager.default.fileExists(atPath: launchAgentPlistPath) else {
            return
        }

        // 卸载启动项
        let process = Process()
        process.launchPath = "/bin/launchctl"
        process.arguments = ["unload", launchAgentPlistPath]
        process.launch()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            print("卸载启动项警告: \(process.terminationStatus)")
        }

        try FileManager.default.removeItem(atPath: launchAgentPlistPath)
    }

    /// 切换开机启动状态
    func toggleAutoStart() throws {
        if isAutoStartEnabled {
            try disableAutoStart()
        } else {
            try enableAutoStart()
        }
    }
}
