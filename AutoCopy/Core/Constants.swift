//
//  Constants.swift
//  AutoCopy
//
//  Created by Claude on 2024/4/8.
//

import Foundation

enum Constants {
    // MARK: - 配置文件
    static let configDirectory: String = "~/.config/autocopy/"
    static let configFileName: String = "autocopy.ini"
    static var configFilePath: String {
        (configDirectory as NSString).expandingTildeInPath + configFileName
    }

    // MARK: - 默认配置
    enum DefaultConfig {
        /// 双击间隔时间（秒）
        static let doubleClickInterval: TimeInterval = 0.4
        /// 最大点击偏移像素
        static let maxClickOffset: Int = 5
        /// 最小按压时长（秒）
        static let minPressDuration: TimeInterval = 0.1
        /// 是否启用自动复制
        static let autoCopyEnabled: Bool = true
        /// 是否显示复制成功提示
        static let showToast: Bool = true
    }

    // MARK: - 日志配置
    enum Logging {
        /// 单日志文件最大大小（字节）
        static let maxFileSize: UInt64 = 10 * 1024 * 1024 // 10MB
        /// 最大日志文件保留份数
        static let maxFileCount: Int = 5
        /// 日志目录
        static var logDirectory: String {
            (NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first ?? "") + "/Logs/AutoCopy/"
        }
        /// 日志文件名前缀
        static let logFilePrefix: String = "autocopy"
    }

    // MARK: - Toast 提示配置
    enum Toast {
        /// 提示尺寸（像素）
        static let size: CGFloat = 20
        /// 入场动画时长（秒）
        static let animateInDuration: TimeInterval = 0.15
        /// 停留时长（秒）
        static let stayDuration: TimeInterval = 0.7
        /// 退场动画时长（秒）
        static let animateOutDuration: TimeInterval = 0.15
        /// 提示背景颜色
        static let backgroundColor: String = "#000000CC"
        /// 提示文字颜色
        static let textColor: String = "#FFFFFF"
        /// 圆角半径
        static let cornerRadius: CGFloat = 8
    }

    // MARK: - 全局常量
    enum Global {
        /// 应用名称
        static let appName: String = "AutoCopy"
        /// 版本号
        static let appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        /// 构建号
        static let buildNumber: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        /// 开发者官网
        static let websiteURL: String = "https://github.com/yyyyyyh/autocopy"
    }
}
