# 成时 UpTimer

[English](#english) | [中文](#中文)

---

## 中文

禅意水墨风格的专注计时器 —— 结合番茄钟与运动计时，帮助你在专注中成长。

### ✨ 特性

- **禅意美学** - 水墨纸笺、呼吸球动画、手绘印章
- **灵活计时** - 番茄钟、训练计时、积木累计三种模式
- **隐性成长** - 记录专注历程，解锁隐藏成就
- **目标关联** - 投入时间累积，见证深耕成果
- **跨平台** - Android、iOS、Web、macOS、Windows、Linux

### 📦 安装

**Android**  
从 [Releases](../../releases) 下载 APK，或自行构建：
```bash
flutter build apk --release
```

**其他平台**  
```bash
flutter pub get
flutter run  # 选择目标设备
```

### 🚀 快速开始

```bash
# 安装依赖
flutter pub get

# 运行（自动选择设备）
flutter run

# 构建 Android
flutter build apk --release

# 构建 Web
flutter build web --release

# 运行测试
flutter test
```

### 📱 截图

_(TODO: 添加应用截图)_

### 🏗️ 架构

```
lib/
├── domain/    核心逻辑（计时引擎、数据模型、音频合成）
├── data/      存储适配（Web localStorage / 原生 shared_preferences）
├── services/  平台服务（音频、振动、文件导入导出）
├── state/     状态管理（AppController）
└── ui/        界面组件（水墨风格组件库）
```

### 🤝 贡献

欢迎 Issue 和 Pull Request！

### 📄 许可

MIT License

---

## English

A Zen-inspired focus timer with ink-wash aesthetics — combining Pomodoro and workout timers to help you grow through focused practice.

### ✨ Features

- **Zen Aesthetics** - Ink-wash paper, breathing orb animation, hand-drawn seals
- **Flexible Timing** - Pomodoro, workout timer, and accumulative modes
- **Hidden Growth** - Track your journey and unlock hidden insights
- **Goal Linking** - Accumulate invested time and witness deep cultivation
- **Cross-platform** - Android, iOS, Web, macOS, Windows, Linux

### 📦 Installation

**Android**  
Download APK from [Releases](../../releases), or build yourself:
```bash
flutter build apk --release
```

**Other Platforms**  
```bash
flutter pub get
flutter run  # Choose target device
```

### 🚀 Quick Start

```bash
# Install dependencies
flutter pub get

# Run (auto-select device)
flutter run

# Build Android
flutter build apk --release

# Build Web
flutter build web --release

# Run tests
flutter test
```

### 📱 Screenshots

_(TODO: Add app screenshots)_

### 🏗️ Architecture

```
lib/
├── domain/    Core logic (timer engine, data models, audio synthesis)
├── data/      Storage adapters (Web localStorage / native shared_preferences)
├── services/  Platform services (audio, haptics, file I/O)
├── state/     State management (AppController)
└── ui/        UI components (ink-wash style component library)
```

### 🤝 Contributing

Issues and Pull Requests are welcome!

### 📄 License

MIT License
