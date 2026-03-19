// src/main.rs
mod clipboard;
mod config;
mod logger;
mod platforms;

use log::{error, info};
use platforms::{PlatformImpl, State};
use std::sync::{Arc, Mutex};

fn main() {
    // 加载配置
    let config = match config::Config::load() {
        Ok(c) => Arc::new(c),
        Err(e) => {
            eprintln!("无法加载配置：{}", e);
            Arc::new(config::Config::default())
        }
    };

    // 初始化日志
    if let Err(e) = logger::init(&config) {
        eprintln!("无法初始化日志：{}", e);
    }

    info!("AutoCopy 启动中...");

    // 初始化状态
    let state = Arc::new(Mutex::new(State::default()));

    // 创建平台实现
    #[cfg(target_os = "macos")]
    let platform = platforms::MacosImpl::new(Arc::clone(&config), Arc::clone(&state));

    #[cfg(target_os = "windows")]
    let platform = platforms::WindowsEventListener::new(Arc::clone(&config), Arc::clone(&state));

    info!("AutoCopy 已就绪");

    // 启动事件监听
    if let Err(e) = platform.start() {
        error!("事件监听失败：{}", e);
        std::process::exit(1);
    }
}
