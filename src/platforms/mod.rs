// src/platforms/mod.rs
#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "windows")]
mod windows;

#[cfg(target_os = "macos")]
pub use macos::*;
#[cfg(target_os = "windows")]
pub use windows::*;

use crate::config::Config;
use std::sync::Arc;

// 共享状态结构
#[derive(Debug, Clone)]
pub struct State {
    pub is_mouse_down: bool,
    pub has_selection: bool,
    pub last_copy_time: f64,
    pub mouse_down_time: f64,
    pub last_mouse_up_time: f64,
    pub last_click_x: f64,
    pub last_click_y: f64,
    pub click_count: u32,
}

impl Default for State {
    fn default() -> Self {
        Self {
            is_mouse_down: false,
            has_selection: false,
            last_copy_time: 0.0,
            mouse_down_time: 0.0,
            last_mouse_up_time: 0.0,
            last_click_x: 0.0,
            last_click_y: 0.0,
            click_count: 0,
        }
    }
}

// 平台通用 trait（由具体平台实现）
pub trait PlatformImpl {
    fn new(config: Arc<Config>, state: Arc<std::sync::Mutex<State>>) -> Self;
    fn start(&self) -> Result<(), Box<dyn std::error::Error>>;
}
