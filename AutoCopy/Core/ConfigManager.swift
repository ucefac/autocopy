//
//  ConfigManager.swift
//  AutoCopy
//
//  Created by Claude on 2024/4/8.
//

import Foundation

final class ConfigManager {
    static let shared = ConfigManager()

    private(set) var config: Config = Config()
    private var fileMonitor: DispatchSourceFileSystemObject?
    private let configQueue = DispatchQueue(label: "com.autocopy.configManager", attributes: .concurrent)

    var configFilePath: String {
        Constants.configFilePath
    }

    private init() {
        loadConfig()
        setupFileMonitor()
    }

    /// 加载配置文件
    func loadConfig() {
        configQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            let fileManager = FileManager.default
            let configURL = URL(fileURLWithPath: self.configFilePath)

            // 如果配置文件不存在，创建默认配置
            guard fileManager.fileExists(atPath: self.configFilePath) else {
                LogManager.shared.info("ConfigManager", "配置文件不存在，创建默认配置")
                self.config = Config()
                self.saveConfigInternal()
                return
            }

            do {
                // 读取INI文件内容
                let content = try String(contentsOf: configURL, encoding: .utf8)
                let configDict = self.parseINI(content)

                var config = Config()

                // 解析General配置项
                let generalConfig = configDict["General"] ?? [:]
                if let doubleClickInterval = Double(generalConfig["doubleClickInterval"] ?? "") {
                    config.doubleClickInterval = doubleClickInterval
                }
                if let maxClickOffset = Int(generalConfig["maxClickOffset"] ?? "") {
                    config.maxClickOffset = maxClickOffset
                }
                if let minPressDuration = Double(generalConfig["minPressDuration"] ?? "") {
                    config.minPressDuration = minPressDuration
                }
                if let longPressThreshold = Double(generalConfig["longPressThreshold"] ?? "") {
                    config.longPressThreshold = longPressThreshold
                }
                if let autoCopyEnabled = Bool(generalConfig["autoCopyEnabled"] ?? "") {
                    config.autoCopyEnabled = autoCopyEnabled
                }
                if let showToast = Bool(generalConfig["showToast"] ?? "") {
                    config.showToast = showToast
                }
                if let logLevelString = generalConfig["logLevel"], let logLevel = LogLevel(rawValue: logLevelString.lowercased()) {
                    config.logLevel = logLevel
                }
                if let launchAtLogin = Bool(generalConfig["launchAtLogin"] ?? "") {
                    config.launchAtLogin = launchAtLogin
                }

                // 读取Advanced section
                let advancedConfig = configDict["Advanced"] ?? [:]
                if let excludedApps = advancedConfig["excludedApps"] {
                    let appIDs = excludedApps.components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    config.excludedApps = appIDs
                    EventListener.shared.updateExcludedAppIDs(Set(appIDs))
                }
                if let toastDisplayDuration = Double(advancedConfig["toastDisplayDuration"] ?? "") {
                    config.toastDisplayDuration = toastDisplayDuration
                }
                if let enableDragCopy = Bool(advancedConfig["enableDragCopy"] ?? "") {
                    config.enableDragCopy = enableDragCopy
                }

                self.config = config

                // 先同步日志级别，再输出日志
                LogManager.shared.setLogLevel(self.config.logLevel)
                LogManager.shared.debug("ConfigManager", "配置文件加载成功")

                // 发送配置变化通知
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("ConfigDidChange"), object: nil)
                }
            } catch {
                LogManager.shared.error("ConfigManager", "配置文件解析失败: \(error.localizedDescription)，使用默认配置")
                self.config = Config()

                // 先同步日志级别，再输出日志
                LogManager.shared.setLogLevel(self.config.logLevel)
                self.saveConfigInternal()

                // 发送配置变化通知
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("ConfigDidChange"), object: nil)
                }
            }
        }
    }

    /// 保存配置到文件
    func saveConfig() {
        configQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.saveConfigInternal()
        }
    }

    /// 内部保存配置方法，必须在configQueue中调用
    private func saveConfigInternal() {
        let configURL = URL(fileURLWithPath: configFilePath)

        do {
            // 构建INI格式内容
            var iniContent = """
            # AutoCopy 配置文件
            # 修改配置后重启应用生效\n\n
            [General]\n
            """

            // 添加General配置项
            iniContent += "# 是否启用自动复制功能\n"
            iniContent += "autoCopyEnabled = \(config.autoCopyEnabled ? "true" : "false")\n\n"

            iniContent += "# 双击/三击的时间间隔（秒）\n"
            iniContent += "doubleClickInterval = \(config.doubleClickInterval)\n\n"

            iniContent += "# 点击判定的最大像素偏移\n"
            iniContent += "maxClickOffset = \(config.maxClickOffset)\n\n"

            iniContent += "# 最小按压时长（秒）\n"
            iniContent += "minPressDuration = \(config.minPressDuration)\n\n"

            iniContent += "# 长按阈值（秒），超过此时长判定为长按，不触发复制\n"
            iniContent += "longPressThreshold = \(config.longPressThreshold)\n\n"

            iniContent += "# 是否显示复制成功的Toast提示\n"
            iniContent += "showToast = \(config.showToast ? "true" : "false")\n\n"

            iniContent += "# 日志输出级别: debug < info < warn < error\n"
            iniContent += "logLevel = \(config.logLevel.rawValue)\n\n"

            iniContent += "# 是否设置应用开机自动启动\n"
            iniContent += "launchAtLogin = \(config.launchAtLogin ? "true" : "false")\n\n"

            // 添加Advanced配置节
            iniContent += "[Advanced]\n"
            iniContent += "# 排除的应用Bundle ID列表，多个用逗号分隔\n"
            iniContent += "excludedApps = \(config.excludedApps.joined(separator: ", "))\n\n"
            iniContent += "# Toast提示显示时长（秒）\n"
            iniContent += "toastDisplayDuration = \(config.toastDisplayDuration)\n\n"
            iniContent += "# 是否启用拖拽选择自动复制\n"
            iniContent += "enableDragCopy = \(config.enableDragCopy ? "true" : "false")\n"

            // 创建目录（如果不存在）
            let configDir = configURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

            // 写入INI文件
            try iniContent.write(to: configURL, atomically: true, encoding: .utf8)
            LogManager.shared.debug("ConfigManager", "配置文件保存成功")
        } catch {
            LogManager.shared.error("ConfigManager", "保存配置文件失败: \(error.localizedDescription)")
        }
    }

    /// 更新配置项
    /// - Parameters:
    ///   - keyPath: 配置项的键路径
    ///   - value: 新值
    func update<T>(_ keyPath: WritableKeyPath<Config, T>, to value: T) {
        configQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.config[keyPath: keyPath] = value
            self.saveConfigInternal()

            // 如果是日志级别更新，同步到LogManager
            if keyPath == \Config.logLevel, let logLevel = value as? LogLevel {
                LogManager.shared.setLogLevel(logLevel)
            }

            // 发送配置变化通知
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: NSNotification.Name("ConfigDidChange"), object: nil)
            }
        }
    }

    /// 获取配置项
    /// - Parameter keyPath: 配置项的键路径
    /// - Returns: 配置值
    func get<T>(_ keyPath: KeyPath<Config, T>) -> T {
        configQueue.sync {
            config[keyPath: keyPath]
        }
    }

    /// 设置文件监听器，监控配置文件变化
    private func setupFileMonitor() {
        let configURL = URL(fileURLWithPath: configFilePath)
        let fileDescriptor = open(configURL.path, O_EVTONLY)

        guard fileDescriptor != -1 else {
            LogManager.shared.warn("ConfigManager", "无法打开配置文件进行监控")
            return
        }

        fileMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.global()
        )

        fileMonitor?.setEventHandler { [weak self] in
            guard let self = self else { return }
            LogManager.shared.debug("ConfigManager", "检测到配置文件变化，重新加载配置")
            self.loadConfig()
        }

        fileMonitor?.setCancelHandler {
            close(fileDescriptor)
        }

        fileMonitor?.resume()
        LogManager.shared.debug("ConfigManager", "配置文件监听器已启动")
    }

    /// 解析INI格式内容
    /// - Parameter content: INI格式的字符串
    /// - Returns: 解析后的字典，key为section名，value为该section的键值对
    private func parseINI(_ content: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        var currentSection: String?
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // 跳过空行和注释
            guard !trimmedLine.isEmpty, !trimmedLine.starts(with: "#"), !trimmedLine.starts(with: ";") else {
                continue
            }

            // 解析section
            if trimmedLine.starts(with: "[") && trimmedLine.hasSuffix("]") {
                let sectionName = String(trimmedLine.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                currentSection = sectionName
                if result[sectionName] == nil {
                    result[sectionName] = [:]
                }
                continue
            }

            // 解析键值对
            if let equalsIndex = trimmedLine.firstIndex(of: "=") {
                let key = String(trimmedLine[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmedLine[trimmedLine.index(after: equalsIndex)...]).trimmingCharacters(in: .whitespaces)

                // 移除值周围的引号（如果有的话）
                let cleanedValue: String
                if (value.starts(with: "\"") && value.hasSuffix("\"")) || (value.starts(with: "'") && value.hasSuffix("'")) {
                    cleanedValue = String(value.dropFirst().dropLast())
                } else {
                    cleanedValue = value
                }

                // 如果没有section，默认放到General
                let section = currentSection ?? "General"
                if result[section] == nil {
                    result[section] = [:]
                }
                result[section]?[key] = cleanedValue
            }
        }

        return result
    }

    deinit {
        fileMonitor?.cancel()
    }
}
