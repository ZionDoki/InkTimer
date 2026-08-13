# Architecture

UpTimer follows a clean architecture pattern with clear separation between domain logic, data persistence, and UI.

## Directory Structure

```
lib/
├── domain/      Pure Dart business logic
├── data/        Storage adapters (Web/native)
├── services/    Platform services
├── state/       AppController state management
└── ui/          Flutter UI components
```

## Core Principles

### 1. Domain Independence

All business logic lives in `lib/domain/` as pure Dart code with no Flutter dependencies:

- **models.dart** - Data models (SessionRecord, TodoItem, TemplateConfig)
- **timer_engine.dart** - Timer state machine
- **sounds.dart** - Audio synthesis specifications
- **stats.dart** - Statistics calculation
- **growth.dart** - Hidden growth system
- **backup.dart** - Import/export logic
- **migrate.dart** - Data migration and validation

Domain code can be unit tested without Flutter test harness.

### 2. State Management

`AppController` (in `lib/state/`) is the single source of truth:

- Hydrates data from storage on startup
- Manages timer state via `TimerEngine`
- Exposes observables via `ChangeNotifier`
- Persists changes to storage
- Never exposes mutable state directly

UI widgets subscribe to `AppController` and rebuild on changes.

### 3. Storage Abstraction

`Repository` (in `lib/data/`) provides platform-agnostic persistence:

- **Web**: `localStorage` via `dart:html`
- **Native**: `shared_preferences` package
- Auto-migrates from legacy Tauri `.dat` files

All storage keys are versioned (`uptimer.*.v1`) to support schema evolution.

### 4. Platform Services

Platform-specific features in `lib/services/`:

- **audio_service.dart** - Real-time audio synthesis
- **haptic_service.dart** - Vibration feedback
- **file_service.dart** - Import/export file pickers

Services abstract platform differences and can be mocked for testing.

## Data Flow

```
User Interaction
    ↓
UI Widget (read-only)
    ↓
AppController (mutates state)
    ↓
Repository (persists)
    ↓
Storage (localStorage / shared_preferences)

AppController notifyListeners()
    ↓
UI Widget rebuilds
```

## Testing Strategy

- **Unit tests** - Domain logic (`test/domain/`)
- **Widget tests** - UI components (`test/widget_test.dart`)
- **Integration tests** - AppController + Repository (`test/state/`)

Domain logic has >90% coverage. UI tests focus on critical user flows.

## Migration and Validation

All persisted data goes through strict validation:

1. **Parse** - JSON → Dart objects
2. **Validate** - Type checks, bounds checks, business rules
3. **Migrate** - Fill missing fields with defaults
4. **Normalize** - Ensure consistency

Invalid data triggers backup and reset to defaults. Migration is backward-compatible: new versions can read old data, but not vice versa.

## Navigation

The app uses a four-corner navigation model:

- **Top-left**: Stats (功课簿)
- **Top-right**: Settings (···)
- **Bottom-left**: Templates (笺)
- **Bottom-right**: Todos (事)

The home screen centers the breathing orb with minimal chrome. Navigation uses Hero animations with liquid-glass transitions.

## Zen Theme

Visual tokens in `lib/ui/theme/zen_theme.dart`:

- **Colors**: `paper`, `paperDeep`, `ink`, `inkSoft`, `inkFaint`, `work`, `rest`, `gold`
- **Typography**: Noto Serif SC (body), Cormorant (numerals)
- **Spacing**: 4px base unit
- **Radius**: Generous curves (32px capsules)

All components use these tokens; no hardcoded colors or sizes.
