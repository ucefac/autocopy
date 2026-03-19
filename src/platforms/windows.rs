// src/platforms/windows.rs
// TODO: Windows 实现

use super::{PlatformImpl, State};
use crate::config::Config;
use std::sync::{Arc, Mutex};

pub struct WindowsEventListener {
    config: Arc<Config>,
    state: Arc<Mutex<State>>,
}

impl PlatformImpl for WindowsEventListener {
    fn new(config: Arc<Config>, state: Arc<Mutex<State>>) -> Self {
        Self { config, state }
    }

    fn start(&self) -> Result<(), Box<dyn std::error::Error>> {
        // TODO: 使用 SetWindowsHookEx 实现鼠标事件监听
        // TODO: 使用 GetForegroundWindow 获取前台应用
        // TODO: 使用 SendInput 模拟 Ctrl+C 快捷键
        unimplemented!("Windows 实现待完成")
    }
}
