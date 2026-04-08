//
//  InstanceManager.swift
//  AutoCopy
//
//  Created by Claude on 2024/4/8.
//

import Foundation

final class InstanceManager {
    static let shared = InstanceManager()

    private let lockFilePath: String
    private var lockFileDescriptor: Int32 = -1

    private init() {
        let configDir = (Constants.configDirectory as NSString).expandingTildeInPath
        self.lockFilePath = configDir + "autocopy.lock"
    }

    /// 尝试获取实例锁
    /// - Returns: 是否成功获取锁
    func acquireLock() -> Bool {
        // 创建配置目录（如果不存在）
        let configDir = URL(fileURLWithPath: (Constants.configDirectory as NSString).expandingTildeInPath)
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        } catch {
            LogManager.shared.error("InstanceManager", "创建配置目录失败: \(error.localizedDescription)")
            return false
        }

        // 打开锁文件
        lockFileDescriptor = open(lockFilePath, O_RDWR | O_CREAT, 0o644)
        guard lockFileDescriptor != -1 else {
            LogManager.shared.error("InstanceManager", "打开锁文件失败: \(String(cString: strerror(errno)))")
            return false
        }

        // 尝试获取独占锁
        let lockResult = flock(lockFileDescriptor, LOCK_EX | LOCK_NB)
        guard lockResult == 0 else {
            if errno == EWOULDBLOCK {
                LogManager.shared.info("InstanceManager", "应用已在运行中")
            } else {
                LogManager.shared.error("InstanceManager", "获取锁失败: \(String(cString: strerror(errno)))")
            }
            close(lockFileDescriptor)
            lockFileDescriptor = -1
            return false
        }

        // 写入当前进程ID
        let pid = ProcessInfo.processInfo.processIdentifier
        let pidString = "\(pid)\n"
        if let pidData = pidString.data(using: .utf8) {
            ftruncate(lockFileDescriptor, 0)
            lseek(lockFileDescriptor, 0, SEEK_SET)
            _ = pidData.withUnsafeBytes { buffer in
                write(lockFileDescriptor, buffer.baseAddress, buffer.count)
            }
        }

        // 注册应用退出时释放锁
        atexit {
            InstanceManager.shared.releaseLock()
        }

        LogManager.shared.debug("InstanceManager", "成功获取实例锁，PID: \(pid)")
        return true
    }

    /// 释放实例锁
    func releaseLock() {
        guard lockFileDescriptor != -1 else { return }

        // 解锁
        flock(lockFileDescriptor, LOCK_UN)
        // 关闭文件
        close(lockFileDescriptor)
        // 删除锁文件
        unlink(lockFilePath)

        lockFileDescriptor = -1
        LogManager.shared.debug("InstanceManager", "已释放实例锁")
    }

    /// 检查是否已有实例在运行
    /// - Returns: 是否有其他实例运行
    func isAnotherInstanceRunning() -> Bool {
        // 先尝试获取锁，如果失败说明有其他实例在运行
        let tempFd = open(lockFilePath, O_RDWR | O_CREAT, 0o644)
        guard tempFd != -1 else {
            return false
        }

        let lockResult = flock(tempFd, LOCK_EX | LOCK_NB)
        if lockResult == 0 {
            // 成功获取锁，说明没有其他实例运行
            flock(tempFd, LOCK_UN)
            close(tempFd)
            return false
        } else if errno == EWOULDBLOCK {
            // 锁被占用，有其他实例运行
            close(tempFd)
            return true
        }

        close(tempFd)
        return false
    }
}
