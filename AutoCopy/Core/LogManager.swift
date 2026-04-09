//
//  LogManager.swift
//  AutoCopy
//
//  Created by Claude on 2024/4/8.
//

import Foundation

final class LogManager {
    static let shared = LogManager()

    private(set) var currentLogLevel: LogLevel = .debug
    private let logQueue = DispatchQueue(label: "com.autocopy.logManager", qos: .background)
    private var currentLogFileHandle: FileHandle?
    private var currentLogFileSize: UInt64 = 0
    private let dateFormatter: DateFormatter

    /// 日志缓冲区
    private var logBuffer: [String] = []
    private let bufferSize: Int = 50 // 缓存50条日志后批量写入
    private let flushInterval: TimeInterval = 5.0 // 最多5秒刷新一次
    private var flushTimer: DispatchSourceTimer?

    var logDirectory: String {
        Constants.Logging.logDirectory
    }

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.locale = Locale(identifier: "zh_CN")

        setupLogDirectory()
        rotateLogFilesIfNeeded()
        openCurrentLogFile()
        setupFlushTimer()
    }

    /// 设置日志目录
    private func setupLogDirectory() {
        let logDirURL = URL(fileURLWithPath: logDirectory)
        do {
            try FileManager.default.createDirectory(at: logDirURL, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o755
            ])
        } catch {
            print("创建日志目录失败: \(error.localizedDescription)")
        }
    }

    /// 打开当前日志文件
    private func openCurrentLogFile() {
        let logFilePath = currentLogFilePath()
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: logFilePath) {
            fileManager.createFile(atPath: logFilePath, contents: nil, attributes: [
                .posixPermissions: 0o644
            ])
        }

        do {
            currentLogFileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: logFilePath))
            try currentLogFileHandle?.seekToEnd()
            currentLogFileSize = try currentLogFileHandle?.offset() ?? 0
        } catch {
            print("打开日志文件失败: \(error.localizedDescription)")
        }
    }

    /// 获取当前日志文件路径
    private func currentLogFilePath() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        return "\(logDirectory)\(Constants.Logging.logFilePrefix)_\(dateString).log"
    }

    /// 检查并轮转日志文件
    private func rotateLogFilesIfNeeded() {
        let fileManager = FileManager.default
        let logDirURL = URL(fileURLWithPath: logDirectory)

        do {
            // 获取所有日志文件
            let logFiles = try fileManager.contentsOfDirectory(
                at: logDirURL,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
            .filter { $0.lastPathComponent.hasPrefix(Constants.Logging.logFilePrefix) }
            .sorted { file1, file2 in
                let date1 = try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
                let date2 = try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
                return date1 ?? .distantPast < date2 ?? .distantPast
            }

            // 删除超过最大数量的旧日志
            if logFiles.count >= Constants.Logging.maxFileCount {
                let filesToDelete = logFiles.prefix(logFiles.count - Constants.Logging.maxFileCount + 1)
                for file in filesToDelete {
                    try? fileManager.removeItem(at: file)
                    LogManager.shared.debug("LogManager", "删除旧日志文件: \(file.lastPathComponent)")
                }
            }

            // 检查当前日志文件大小
            let currentLogPath = currentLogFilePath()
            if fileManager.fileExists(atPath: currentLogPath) {
                let attributes = try fileManager.attributesOfItem(atPath: currentLogPath)
                if let fileSize = attributes[.size] as? UInt64, fileSize >= Constants.Logging.maxFileSize {
                    // 轮转当前日志文件
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                    let timestamp = dateFormatter.string(from: Date())
                    let rotatedPath = "\(logDirectory)\(Constants.Logging.logFilePrefix)_\(timestamp).log"
                    try fileManager.moveItem(atPath: currentLogPath, toPath: rotatedPath)
                    LogManager.shared.info("LogManager", "日志文件已轮转: \(rotatedPath)")
                }
            }
        } catch {
            print("日志轮转失败: \(error.localizedDescription)")
        }
    }

    /// 设置日志级别
    /// - Parameter level: 新的日志级别
    /// - 注意：只有当日志级别真正发生变化时才更新并打印日志，相同值直接返回
    func setLogLevel(_ level: LogLevel) {
        // 使用 async 确保不会死锁
        logQueue.async { [weak self] in
            guard let self = self else { return }

            // 添加大小写不敏感的比较，只有级别真正变化时才更新
            guard level.rawValue.lowercased() != self.currentLogLevel.rawValue.lowercased() else {
                return // 级别相同，直接返回，避免重复打印日志
            }

            self.currentLogLevel = level

            // 同步执行 info 日志，确保立即写入
            let timestamp = self.dateFormatter.string(from: Date())
            let logString = "[\(timestamp)] [INFO] [LogManager] 日志级别已设置为: \(level.rawValue)\n"

            #if DEBUG
            print(logString, terminator: "")
            #endif

            self.logBuffer.append(logString)
            if self.logBuffer.count >= self.bufferSize {
                self.flushBuffer()
            }
        }
    }

    /// 记录Debug级别日志
    /// - Parameters:
    ///   - module: 模块名称
    ///   - message: 日志内容
    func debug(_ module: String, _ message: String) {
        log(level: .debug, module: module, message: message)
    }

    /// 记录Info级别日志
    /// - Parameters:
    ///   - module: 模块名称
    ///   - message: 日志内容
    func info(_ module: String, _ message: String) {
        log(level: .info, module: module, message: message)
    }

    /// 记录Warn级别日志
    /// - Parameters:
    ///   - module: 模块名称
    ///   - message: 日志内容
    func warn(_ module: String, _ message: String) {
        log(level: .warn, module: module, message: message)
    }

    /// 记录Error级别日志
    /// - Parameters:
    ///   - module: 模块名称
    ///   - message: 日志内容
    func error(_ module: String, _ message: String) {
        log(level: .error, module: module, message: message)
    }

    /// 内部日志记录方法
    private func log(level: LogLevel, module: String, message: String) {
        // 检查日志级别
        guard level >= currentLogLevel else { return }

        logQueue.async { [weak self] in
            guard let self = self else { return }

            let timestamp = self.dateFormatter.string(from: Date())
            let logString = "[\(timestamp)] [\(level.rawValue.uppercased())] [\(module)] \(message)\n"

            // 输出到控制台（仅Debug模式）
            #if DEBUG
            print("\(level.icon) \(logString)", terminator: "")
            #endif

            // 添加到缓冲区
            self.logBuffer.append(logString)

            // 缓冲区满时刷新
            if self.logBuffer.count >= self.bufferSize {
                self.flushBuffer()
            }
        }
    }

    /// 设置定时刷新定时器
    private func setupFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: logQueue)
        timer.schedule(deadline: .now(), repeating: flushInterval)
        timer.setEventHandler { [weak self] in
            self?.flushBuffer()
        }
        timer.resume()
        flushTimer = timer
    }

    /// 刷新日志缓冲区到文件
    private func flushBuffer() {
        guard !logBuffer.isEmpty else { return }

        let logData = logBuffer.joined().data(using: .utf8)
        logBuffer.removeAll()

        guard let data = logData else { return }

        do {
            try currentLogFileHandle?.write(contentsOf: data)
            currentLogFileSize += UInt64(data.count)

            // 检查是否需要轮转日志
            if currentLogFileSize >= Constants.Logging.maxFileSize {
                currentLogFileHandle?.closeFile()
                rotateLogFilesIfNeeded()
                openCurrentLogFile()
            }
        } catch {
            print("写入日志文件失败: \(error.localizedDescription)")
        }
    }

    deinit {
        flushTimer?.cancel()
        flushBuffer()
        currentLogFileHandle?.closeFile()
    }
}
