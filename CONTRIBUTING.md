# Contributing to InkTimer

[English](#english) | [中文](#中文)

---

## 中文

感谢你对成时的关注！

### 开发环境

- Flutter 3.24+
- Dart 3.5+
- Android Studio / VS Code
- Android SDK（构建 Android 版）
- Xcode（构建 iOS/macOS 版）

### 开发流程

```bash
# 1. Fork 并克隆仓库
git clone https://github.com/YOUR_USERNAME/InkTimer.git
cd InkTimer

# 2. 安装依赖
flutter pub get

# 3. 运行应用
flutter run

# 4. 运行测试
flutter test

# 5. 代码检查
flutter analyze
```

### 代码风格

- 遵循 Dart 官方风格指南
- 使用 `flutter format` 格式化代码
- 提交前运行 `flutter analyze` 确保无警告
- 测试覆盖新增功能

### 提交规范

使用语义化提交信息：

```
feat(timer): 添加新功能
fix(ui): 修复界面问题
docs: 更新文档
test: 添加测试
refactor: 重构代码
style: 代码格式调整
```

### 架构约定

- **领域逻辑** - 放在 `lib/domain/`，纯 Dart，不依赖 Flutter
- **UI 组件** - 订阅 `AppController`，不直接修改状态
- **测试优先** - 先写 `*_test.dart`，再实现功能
- **数据迁移** - 新字段必须向后兼容，更新 `lib/domain/migrate.dart`

### 目录结构

```
lib/
├── domain/      领域模型、业务逻辑、验证规则
│   ├── models.dart       数据模型
│   ├── timer_engine.dart 计时引擎
│   ├── sounds.dart       音频合成
│   ├── stats.dart        统计计算
│   └── migrate.dart      数据迁移
├── data/        存储层（Web/原生适配）
├── services/    平台服务（音频、振动、文件）
├── state/       AppController 状态管理
└── ui/          界面组件
    ├── home/          主屏（呼吸球）
    ├── templates/     时间笺
    ├── todos/         目标清单
    ├── stats/         统计页
    ├── settings/      设置
    ├── theme/         设计系统
    └── widgets/       共用组件
```

### 测试指南

```bash
# 运行所有测试
flutter test

# 运行特定测试
flutter test test/domain/timer_engine_test.dart

# 查看测试覆盖率
flutter test --coverage
```

### Pull Request

1. 从 `main` 分支创建功能分支
2. 实现功能并添加测试
3. 确保 `flutter test` 和 `flutter analyze` 通过
4. 提交 PR，描述清楚改动内容

---

## English

Thanks for your interest in InkTimer!

### Development Environment

- Flutter 3.24+
- Dart 3.5+
- Android Studio / VS Code
- Android SDK (for Android builds)
- Xcode (for iOS/macOS builds)

### Development Workflow

```bash
# 1. Fork and clone the repository
git clone https://github.com/YOUR_USERNAME/InkTimer.git
cd InkTimer

# 2. Install dependencies
flutter pub get

# 3. Run the app
flutter run

# 4. Run tests
flutter test

# 5. Code analysis
flutter analyze
```

### Code Style

- Follow Dart official style guide
- Format code with `flutter format`
- Run `flutter analyze` before committing
- Add tests for new features

### Commit Convention

Use semantic commit messages:

```
feat(timer): add new feature
fix(ui): fix UI issue
docs: update documentation
test: add tests
refactor: refactor code
style: code formatting
```

### Architecture Guidelines

- **Domain Logic** - Place in `lib/domain/`, pure Dart, no Flutter dependency
- **UI Components** - Subscribe to `AppController`, don't mutate state directly
- **Test First** - Write `*_test.dart` before implementation
- **Data Migration** - New fields must be backward compatible, update `lib/domain/migrate.dart`

### Directory Structure

```
lib/
├── domain/      Domain models, business logic, validation rules
│   ├── models.dart       Data models
│   ├── timer_engine.dart Timer engine
│   ├── sounds.dart       Audio synthesis
│   ├── stats.dart        Statistics calculation
│   └── migrate.dart      Data migration
├── data/        Storage layer (Web/native adapters)
├── services/    Platform services (audio, haptics, file I/O)
├── state/       AppController state management
└── ui/          UI components
    ├── home/          Home screen (breathing orb)
    ├── templates/     Templates
    ├── todos/         Goal list
    ├── stats/         Statistics
    ├── settings/      Settings
    ├── theme/         Design system
    └── widgets/       Shared widgets
```

### Testing Guide

```bash
# Run all tests
flutter test

# Run specific test
flutter test test/domain/timer_engine_test.dart

# View coverage
flutter test --coverage
```

### Pull Request

1. Create a feature branch from `main`
2. Implement feature with tests
3. Ensure `flutter test` and `flutter analyze` pass
4. Submit PR with clear description
