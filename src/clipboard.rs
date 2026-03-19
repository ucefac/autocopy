// src/clipboard.rs
use core_graphics::event::{CGEvent, CGEventFlags, CGEventTapLocation};
use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};
use log::info;
use std::thread;
use std::time::Duration;

// Cmd 键的虚拟键码
const CMD_KEYCODE: u16 = 55;
const C_KEYCODE: u16 = 8;

// 按键事件之间的延时（毫秒）
const KEY_PRESS_DELAY_MS: u64 = 30;

pub fn copy() {
    info!("执行复制 (Cmd+C)");

    if let Ok(source) = CGEventSource::new(CGEventSourceStateID::Private) {
        // 按下 Cmd 键
        if let Ok(cmd_down) = CGEvent::new_keyboard_event(source.clone(), CMD_KEYCODE, true) {
            cmd_down.set_flags(CGEventFlags::CGEventFlagCommand);
            cmd_down.post(CGEventTapLocation::HID);
        }

        // 等待 Cmd 键生效
        thread::sleep(Duration::from_millis(KEY_PRESS_DELAY_MS));

        // 按下 C 键（此时 Cmd 键已按下）
        if let Ok(c_down) = CGEvent::new_keyboard_event(source.clone(), C_KEYCODE, true) {
            c_down.set_flags(CGEventFlags::CGEventFlagCommand);
            c_down.post(CGEventTapLocation::HID);
        }

        // 等待 C 键生效
        thread::sleep(Duration::from_millis(KEY_PRESS_DELAY_MS));

        // 释放 C 键
        if let Ok(c_up) = CGEvent::new_keyboard_event(source.clone(), C_KEYCODE, false) {
            c_up.set_flags(CGEventFlags::CGEventFlagCommand);
            c_up.post(CGEventTapLocation::HID);
        }

        // 等待 C 键释放
        thread::sleep(Duration::from_millis(KEY_PRESS_DELAY_MS));

        // 释放 Cmd 键
        if let Ok(cmd_up) = CGEvent::new_keyboard_event(source.clone(), CMD_KEYCODE, false) {
            cmd_up.set_flags(CGEventFlags::CGEventFlagCommand);
            cmd_up.post(CGEventTapLocation::HID);
        }
    }
}
