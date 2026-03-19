// src/config.rs
use log::LevelFilter;
use std::fs;
use std::io::Write;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct Config {
    pub excluded_apps: Vec<String>,
    pub min_press_duration: f64,
    pub double_click_interval: f64,
    pub max_click_distance: f64,
    pub log_file: PathBuf,
    pub log_level: LevelFilter,
    pub enable_log: bool,
    pub log_app_name: bool,
    pub log_mouse_coords: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            excluded_apps: vec![],
            min_press_duration: 0.5,
            double_click_interval: 0.4,
            max_click_distance: 5.0,
            log_file: dirs::home_dir()
                .unwrap_or_default()
                .join(".config/autocopy/autocopy.log"),
            log_level: LevelFilter::Info,
            enable_log: false,
            log_app_name: false,
            log_mouse_coords: false,
        }
    }
}

impl Config {
    pub fn load() -> Result<Self, Box<dyn std::error::Error>> {
        // 使用 ~/.config/autocopy/autocopy.ini 路径
        let config_dir = dirs::home_dir()
            .ok_or("无法获取用户主目录")?
            .join(".config/autocopy");

        let config_path = config_dir.join("autocopy.ini");

        // 确保配置目录存在
        fs::create_dir_all(&config_dir)?;

        // 如果配置文件不存在，则创建一个新的并保存为INI格式
        if !config_path.exists() {
            let default_config = Self::default();
            default_config.save_to(&config_path)?;
            return Ok(default_config);
        }

        // 读取现有配置文件
        let mut parser = configparser::ini::Ini::new();
        parser.load(config_path.to_string_lossy().to_string())?;

        // 解析exclude apps
        let excluded_apps = parser
            .get("default", "excluded_apps")
            .unwrap_or_default()
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty()) // 过滤空字符串
            .collect();

        let log_level_str = parser
            .get("default", "log_level")
            .unwrap_or_else(|| "info".to_string());
        let log_level = match log_level_str.as_str() {
            "debug" => LevelFilter::Debug,
            "info" => LevelFilter::Info,
            "warn" => LevelFilter::Warn,
            "error" => LevelFilter::Error,
            _ => LevelFilter::Info,
        };

        Ok(Self {
            excluded_apps,
            min_press_duration: parser
                .get("default", "min_press_duration")
                .and_then(|s| s.parse().ok())
                .unwrap_or(0.5),
            double_click_interval: parser
                .get("default", "double_click_interval")
                .and_then(|s| s.parse().ok())
                .unwrap_or(0.4),
            max_click_distance: parser
                .get("default", "max_click_distance")
                .and_then(|s| s.parse().ok())
                .unwrap_or(5.0),
            log_file: parser
                .get("default", "log_file")
                .map(|s| expand_tilde(&s))
                .unwrap_or_else(|| {
                    dirs::home_dir()
                        .unwrap_or_default()
                        .join(".config/autocopy/autocopy.log")
                }),
            log_level,
            enable_log: parser
                .getbool("default", "enable_log")
                .unwrap_or(Some(false))
                .unwrap_or(false),
            log_app_name: parser
                .getbool("default", "log_app_name")
                .unwrap_or(Some(false))
                .unwrap_or(false),
            log_mouse_coords: parser
                .getbool("default", "log_mouse_coords")
                .unwrap_or(Some(false))
                .unwrap_or(false),
        })
    }

    /// 将配置保存到指定路径
    pub fn save_to(&self, path: &std::path::Path) -> Result<(), Box<dyn std::error::Error>> {
        // 确保配置目录存在
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }

        let mut config_content = String::new();
        config_content.push_str("# AutoCopy Configuration\n");
        config_content.push_str("# 此配置文件会在不存在时自动生成\n");
        config_content.push_str("[default]\n");

        // 写入exclude apps
        let excluded_apps_str = self.excluded_apps.join(",");
        config_content.push_str(&format!(
            "# 排除的应用列表（逗号分隔）\n\
              excluded_apps={}\n\n",
            excluded_apps_str
        ));

        // 写入基本配置
        config_content.push_str(&format!(
            "# 最小按压时间阈值（秒）\n\
              min_press_duration={}\n\n",
            self.min_press_duration
        ));

        config_content.push_str(&format!(
            "# 双击检测间隔（秒）\n\
              double_click_interval={}\n\n",
            self.double_click_interval
        ));

        config_content.push_str(&format!(
            "# 最大位置偏移（像素）\n\
              max_click_distance={}\n\n",
            self.max_click_distance
        ));

        // 写入日志相关配置
        let log_file_str = self.log_file.to_string_lossy().to_string();
        config_content.push_str(&format!(
            "# 日志文件路径\n\
              log_file={}\n\n",
            log_file_str
        ));

        let log_level_str = match self.log_level {
            LevelFilter::Debug => "debug",
            LevelFilter::Info => "info",
            LevelFilter::Warn => "warn",
            LevelFilter::Error => "error",
            _ => "info",
        };

        config_content.push_str(&format!(
            "# 日志级别 (debug, info, warn, error)\n\
              log_level={}\n\n",
            log_level_str
        ));

        config_content.push_str(&format!(
            "# 是否启用日志\n\
              enable_log={}\n\n",
            self.enable_log
        ));

        // 隐私保护相关配置
        config_content.push_str(&format!(
            "# 隐私保护选项\n\
              log_app_name={}\n\n",
            self.log_app_name
        ));

        config_content.push_str(&format!("log_mouse_coords={}\n", self.log_mouse_coords));

        let mut file = fs::File::create(path)?;
        file.write_all(config_content.as_bytes())?;
        file.flush()?;

        Ok(())
    }

    /// 保存当前配置到默认位置
    pub fn save(&self) -> Result<(), Box<dyn std::error::Error>> {
        let config_dir = dirs::home_dir()
            .ok_or("无法获取用户主目录")?
            .join(".config/autocopy");

        let config_path = config_dir.join("autocopy.ini");

        self.save_to(&config_path)
    }

    pub fn is_excluded(&self, app_name: &str) -> bool {
        self.excluded_apps.iter().any(|name| name == app_name)
    }
}

fn expand_tilde(path: &str) -> PathBuf {
    if path.starts_with('~') {
        let home = dirs::home_dir().unwrap_or_default();
        home.join(&path[2..])
    } else {
        PathBuf::from(path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert_eq!(config.min_press_duration, 0.5);
        assert_eq!(config.double_click_interval, 0.4);
        assert_eq!(config.max_click_distance, 5.0);
        assert!(!config.enable_log);
    }

    #[test]
    fn test_is_excluded() {
        let config = Config {
            excluded_apps: vec!["Terminal".to_string(), "iTerm2".to_string()],
            ..Default::default()
        };
        assert!(config.is_excluded("Terminal"));
        assert!(config.is_excluded("iTerm2"));
        assert!(!config.is_excluded("Safari"));
    }

    #[test]
    fn test_save_and_load() {
        // 创建临时目录模拟配置文件的测试
        let temp_dir = tempdir().unwrap();
        let config_path = temp_dir.path().join("config_test.ini");

        // 创建一个带有特定值的配置
        let original_config = Config {
            excluded_apps: vec!["TestApp".to_string()],
            min_press_duration: 1.5,
            double_click_interval: 0.35,
            max_click_distance: 7.0,
            log_file: PathBuf::from("/tmp/test.log"),
            log_level: LevelFilter::Debug,
            enable_log: true,
            log_app_name: true,
            log_mouse_coords: true,
        };

        // 保存配置
        original_config.save_to(&config_path).unwrap();

        // 验证保存的内容
        assert!(config_path.exists());

        // 创建一个临时的Ini解析器测试
        let mut parser = configparser::ini::Ini::new();
        parser
            .load(config_path.to_string_lossy().to_string())
            .unwrap();

        let saved_min_press_duration: f64 = parser
            .get("default", "min_press_duration")
            .unwrap()
            .parse()
            .unwrap();
        assert_eq!(saved_min_press_duration, 1.5);
    }
}
