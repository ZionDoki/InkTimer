import 'models.dart';

const builtinTemplates = <TimerTemplate>[
  TimerTemplate(
    id: 'builtin.pomodoro',
    label: '番茄钟',
    kind: TemplateKind.pomodoro,
    builtin: true,
    createdAt: 0,
    focusSec: 25 * 60,
    breakSec: 5 * 60,
    rounds: 4,
    longBreakSec: 15 * 60,
    longBreakEvery: 4,
  ),
  TimerTemplate(
    id: 'builtin.deepwork',
    label: '深度工作',
    kind: TemplateKind.pomodoro,
    builtin: true,
    createdAt: 0,
    focusSec: 50 * 60,
    breakSec: 10 * 60,
    rounds: 2,
  ),
  TimerTemplate(
    id: 'builtin.tabata',
    label: 'Tabata',
    kind: TemplateKind.interval,
    builtin: true,
    createdAt: 0,
    workSec: 20,
    restSec: 10,
    rounds: 8,
  ),
  TimerTemplate(
    id: 'builtin.hiit',
    label: 'HIIT 初级',
    kind: TemplateKind.interval,
    builtin: true,
    createdAt: 0,
    workSec: 30,
    restSec: 15,
    rounds: 6,
  ),
  TimerTemplate(
    id: 'builtin.cardio',
    label: '有氧持续',
    kind: TemplateKind.accumulate,
    builtin: true,
    createdAt: 0,
  ),
  TimerTemplate(
    id: 'builtin.plank',
    label: '平板支撑',
    kind: TemplateKind.accumulate,
    builtin: true,
    createdAt: 0,
  ),
];

const defaultSettings = AppSettings(
  volume: 0.8,
  soundOn: true,
  hapticsOn: true,
  keepAwake: true,
  theme: 'paper',
);
