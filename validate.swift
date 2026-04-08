//
//  validate.swift
//  AutoCopy
//
//  Created by Claude on 2024/4/8.
//

import Foundation
import AppKit

// 导入所有核心类
import AutoCopy

print("✅ 所有类导入成功")

// 测试InstanceManager
let instanceManager = InstanceManager.shared
print("✅ InstanceManager 初始化成功")

// 测试ConfigManager
let configManager = ConfigManager.shared
print("✅ ConfigManager 初始化成功")
print("   当前配置 - 双击间隔: \(configManager.get(\.doubleClickInterval))s")
print("   当前配置 - 日志级别: \(configManager.get(\.logLevel))")

// 测试LogManager
let logManager = LogManager.shared
print("✅ LogManager 初始化成功")
logManager.info("Validation", "日志系统测试正常")

// 测试PermissionManager
let permissionManager = PermissionManager.shared
print("✅ PermissionManager 初始化成功")
print("   辅助功能权限: \(permissionManager.hasAccessibilityPermission ? "已授权" : "未授权")")

print("\n🎉 所有核心服务类验证通过！")
