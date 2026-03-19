// src/platforms/macos.rs
use super::{PlatformImpl, State};
use crate::clipboard::copy;
use crate::config::Config;
use core_foundation::runloop::{CFRunLoop, kCFRunLoopDefaultMode};
use core_graphics::event::{CGEvent, CGEventTap, CGEventTapLocation, CGEventTapPlacement, CGEventTapOptions, CGEventType};
use log::{debug, info, warn};
use objc2_app_kit::NSWorkspace;
use std::sync::{Arc, Mutex};

pub struct MacosImpl {
    config: Arc<Config>,
    state: Arc<Mutex<State>>,
}

impl PlatformImpl for MacosImpl {
    fn new(config: Arc<Config>, state: Arc<Mutex<State>>) -> Self {
        Self { config, state }
    }

    fn start(&self) -> Result<(), Box<dyn std::error::Error>> {
        let config = Arc::clone(&self.config);
        let state = Arc::clone(&self.state);

        info!("AutoCopy 启动中...");

        // 创建事件监听
        let event_tap = CGEventTap::new(
            CGEventTapLocation::HID,
            CGEventTapPlacement::HeadInsertEventTap,
            CGEventTapOptions::Default,
            vec![
                CGEventType::LeftMouseDown,
                CGEventType::LeftMouseUp,
                CGEventType::LeftMouseDragged,
            ],
            move |_proxy, event_type, event| {
                handle_event(event.clone(), event_type, &config, &state)
            },
        );

        match event_tap {
            Ok(tap) => {
                debug!("事件监听已启动");
                // 运行 RunLoop
                run_loop(tap);
                Ok(())
            }
            Err(e) => {
                warn!("无法创建事件监听：{:?}", e);
                Err(format!("CGEventTap error: {:?}", e).into())
            }
        }
    }
}

fn handle_event(
    event: CGEvent,
    event_type: CGEventType,
    config: &Config,
    state: &Arc<Mutex<State>>,
) -> Option<CGEvent> {
    // 使用 debug 级别记录所有事件（避免泄露隐私）
    debug!("事件：{:?}", event_type);

    let mut state_guard = state.lock().unwrap();
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs_f64();

    match event_type {
        CGEventType::LeftMouseDown => {
            let location = event.location();
            state_guard.is_mouse_down = true;
            state_guard.has_selection = false;
            state_guard.mouse_down_time = now;
            state_guard.last_click_x = location.x;
            state_guard.last_click_y = location.y;
            // 仅在启用坐标日志时记录
            if config.log_mouse_coords {
                debug!("mouse_down: x={}, y={}", location.x, location.y);
            } else {
                debug!("mouse_down");
            }
        }

        CGEventType::LeftMouseDragged => {
            if state_guard.is_mouse_down {
                state_guard.has_selection = true;
                debug!("mouse_dragged: selection in progress");
            }
        }

        CGEventType::LeftMouseUp => {
            let press_duration = now - state_guard.mouse_down_time;
            state_guard.is_mouse_down = false;

            let location = event.location();

            // 检测双击/三击
            let time_diff = now - state_guard.last_mouse_up_time;
            let dx = location.x - state_guard.last_click_x;
            let dy = location.y - state_guard.last_click_y;
            let distance = ((dx * dx + dy * dy) as f64).sqrt();

            let is_multi_click = time_diff < config.double_click_interval
                && distance < config.max_click_distance;

            if is_multi_click {
                state_guard.click_count = (state_guard.click_count + 1).min(3);
            } else {
                state_guard.click_count = 1;
            }

            state_guard.last_mouse_up_time = now;
            state_guard.last_click_x = location.x;
            state_guard.last_click_y = location.y;

            debug!(
                "mouse_up: press_duration={:.3}s, click_count={}, has_selection={}",
                press_duration, state_guard.click_count, state_guard.has_selection
            );

            // 检查应用排除
            if let Some(app_name) = get_frontmost_app_name() {
                // 仅在启用应用名称日志时记录
                if config.log_app_name {
                    debug!("当前应用：{}", app_name);
                } else {
                    debug!("当前应用：[已隐藏]");
                }
                if config.is_excluded(&app_name) {
                    info!("应用在排除列表中，跳过：{}", app_name);
                    state_guard.has_selection = false;
                    return Some(event);
                }
            }

            // 判断是否触发复制
            let should_copy = if state_guard.click_count >= 2 {
                debug!("双击/三击检测成功");
                true // 双击/三击直接触发
            } else {
                let result = press_duration >= config.min_press_duration;
                debug!("单击检测：press_duration={:.3}s, min_press_duration={:.3}s, result={}",
                      press_duration, config.min_press_duration, result);
                result // 单击检查按压时长
            };

            // 双击/三击直接触发复制，不检查 has_selection
            // 因为系统自动选词时不会触发 LeftMouseDragged 事件
            if state_guard.click_count >= 2 {
                debug!("双击/三击触发复制：click_count={}", state_guard.click_count);
                copy();
            } else if should_copy && state_guard.has_selection {
                debug!("触发复制：has_selection=true");
                copy();
            } else {
                debug!("不触发复制：should_copy={}, has_selection={}, click_count={}",
                      should_copy, state_guard.has_selection, state_guard.click_count);
            }

            state_guard.has_selection = false;
        }

        _ => {}
    }

    Some(event)
}

fn get_frontmost_app_name() -> Option<String> {
    unsafe {
        let workspace = NSWorkspace::sharedWorkspace();
        let frontmost_app = workspace.frontmostApplication();
        frontmost_app.and_then(|app| {
            app.localizedName().map(|name| name.to_string())
        })
    }
}

fn run_loop(tap: CGEventTap) {
    // 将事件监听器添加到 RunLoop
    let runloop = CFRunLoop::get_current();

    // 从 mach_port 创建 RunLoopSource
    let tap_source = tap.mach_port.create_runloop_source(0).unwrap();

    // 添加事件源到 RunLoop
    unsafe {
        runloop.add_source(&tap_source, kCFRunLoopDefaultMode);
    }

    // 激活事件监听
    tap.enable();

    debug!("RunLoop 已启动，等待事件...");

    // 运行当前线程的 RunLoop（阻塞直到被停止）
    CFRunLoop::run_current();
}
