// src/logger.rs
use simplelog::{CombinedLogger, Config as SimpleLogConfig, WriteLogger};
use std::fs::OpenOptions;

use crate::config::Config;

pub fn init(config: &Config) -> Result<(), Box<dyn std::error::Error>> {
    if !config.enable_log {
        return Ok(());
    }

    // 确保日志目录存在
    if let Some(parent) = config.log_file.parent() {
        std::fs::create_dir_all(parent)?;
    }

    // 如果日志文件过大，进行轮转（保留最近 10MB）
    if let Ok(metadata) = std::fs::metadata(&config.log_file) {
        if metadata.len() > 10 * 1024 * 1024 {
            let rotated = config.log_file.with_extension("log.old");
            std::fs::rename(&config.log_file, &rotated)?;
        }
    }

    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&config.log_file)?;

    CombinedLogger::init(vec![WriteLogger::new(
        config.log_level,
        SimpleLogConfig::default(),
        file,
    )])?;

    Ok(())
}
