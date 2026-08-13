import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uptimer/data/key_value_store.dart';
import 'package:uptimer/data/repository.dart';
import 'package:uptimer/services/backup_file_service.dart';
import 'package:uptimer/services/runtime_effects.dart';
import 'package:uptimer/state/app_controller.dart';
import 'package:uptimer/ui/settings/settings_page.dart';
import 'package:uptimer/ui/theme/zen_theme.dart';

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{StorageKeys.seenGuide: '1'};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> flush() async {}
}

/// 记录调用的假文件服务，避免测试触碰真实文件系统与选择器插件。
class _FakeFiles extends BackupFileService {
  _FakeFiles({
    this.supported = true,
    this.savedAt,
    this.pickedContent,
    this.pickSaved = true,
  });

  bool supported;
  DateTime? savedAt;
  String? path = '/tmp/docs/inktimer-backup.json';
  String? defaultContent;
  String? pickedContent;
  bool pickSaved;

  final saveToDefaultCalls = <String>[];
  final saveAsCalls = <String>[];
  int defaultInfoCalls = 0;
  int readFromDefaultCalls = 0;
  int pickJsonCalls = 0;

  @override
  bool get supportsDefaultLocation => supported;

  @override
  Future<BackupDefaultInfo> defaultInfo() async {
    defaultInfoCalls += 1;
    return BackupDefaultInfo(
      supported: supported,
      path: supported ? path : null,
      savedAt: supported ? savedAt : null,
    );
  }

  @override
  Future<BackupSaveResult> saveToDefault(String content) async {
    saveToDefaultCalls.add(content);
    defaultContent = content;
    savedAt = DateTime(2026, 8, 13, 21, 5);
    return BackupSaveResult(
      saved: true,
      location: supported ? path : backupDownloadLocation,
    );
  }

  @override
  Future<String?> readFromDefault() async {
    readFromDefaultCalls += 1;
    return defaultContent;
  }

  @override
  Future<BackupSaveResult> saveAs(String content) async {
    saveAsCalls.add(content);
    if (!pickSaved) return const BackupSaveResult(saved: false);
    return const BackupSaveResult(saved: true, location: '/chosen/backup.json');
  }

  @override
  Future<String?> pickJson() async {
    pickJsonCalls += 1;
    return pickedContent;
  }
}

Future<AppController> _controller(_MemoryStore store) async {
  final controller = AppController(
    repository: Repository(store),
    effects: const NoopRuntimeEffects(),
    driveTicker: false,
    observeLifecycle: false,
  );
  await controller.initialize();
  return controller;
}

Future<void> _pumpSettings(
  WidgetTester tester,
  AppController controller,
  BackupFileService files,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildZenTheme(ink: false),
      home: SettingsPage(controller: controller, files: files),
    ),
  );
  // initState 里查询默认位置是异步的，等它落地再断言。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _row(String key) => find.byKey(ValueKey(key));

/// 选项区的可见高度。收起时为 0，展开时为选项自身的高度。
double _optionsHeight(WidgetTester tester, String id) =>
    tester.getSize(_row('$id-options')).height;

Finder _inside(String id, Finder matching) =>
    find.descendant(of: _row('$id-options'), matching: matching);

Future<void> _tapRow(WidgetTester tester, String key) async {
  await tester.ensureVisible(_row(key));
  await tester.tap(_row(key));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: '成时',
      packageName: 'com.uptimer.app',
      version: '0.3.3',
      buildNumber: '4',
      buildSignature: '',
    );
  });

  testWidgets('封存与收录都点开后才出现两个位置选项', (tester) async {
    final controller = await _controller(_MemoryStore());
    addTearDown(controller.dispose);
    await _pumpSettings(tester, controller, _FakeFiles());

    expect(_optionsHeight(tester, 'export'), 0);
    expect(_optionsHeight(tester, 'import'), 0);

    await _tapRow(tester, 'export-action');

    expect(_optionsHeight(tester, 'export'), greaterThan(0));
    expect(_inside('export', _row('export-default')), findsOneWidget);
    expect(_inside('export', _row('export-pick')), findsOneWidget);
    expect(_inside('export', find.text('默 认 位 置')), findsOneWidget);
    expect(_inside('export', find.text('另 选 位 置')), findsOneWidget);

    await _tapRow(tester, 'import-action');

    expect(_optionsHeight(tester, 'import'), greaterThan(0));
    expect(_inside('import', find.text('默 认 位 置')), findsOneWidget);
    expect(_inside('import', find.text('另 选 文 件')), findsOneWidget);
  });

  testWidgets('收起状态下的选项不可点、不进无障碍树', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = await _controller(_MemoryStore());
    addTearDown(controller.dispose);
    final files = _FakeFiles();
    await _pumpSettings(tester, controller, files);

    // 选项行会把标签与说明合成一个语义节点，这里按模式匹配。
    final defaultOption = find.bySemanticsLabel(RegExp('默 认 位 置'));
    expect(defaultOption, findsNothing);
    await tester.tap(_row('export-default'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));

    expect(files.saveToDefaultCalls, isEmpty);

    await _tapRow(tester, 'export-action');
    expect(defaultOption, findsOneWidget);
    handle.dispose();
  });

  testWidgets('展开与收起是渐变过渡，且一次只展开一处', (tester) async {
    final controller = await _controller(_MemoryStore());
    addTearDown(controller.dispose);
    await _pumpSettings(tester, controller, _FakeFiles());

    await tester.ensureVisible(_row('export-action'));
    await tester.tap(_row('export-action'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final midway = _optionsHeight(tester, 'export');
    await tester.pump(const Duration(milliseconds: 300));
    final settled = _optionsHeight(tester, 'export');

    // 中途高度介于 0 与终态之间，说明高度是渐变而不是瞬间跳变。
    expect(midway, greaterThan(0));
    expect(midway, lessThan(settled));

    await _tapRow(tester, 'import-action');

    expect(_optionsHeight(tester, 'export'), 0);
    expect(_optionsHeight(tester, 'import'), greaterThan(0));

    await _tapRow(tester, 'import-action');

    expect(_optionsHeight(tester, 'import'), 0);
  });

  testWidgets('默认位置封存后能从同一位置收录', (tester) async {
    final controller = await _controller(_MemoryStore());
    addTearDown(controller.dispose);
    await controller.addTodo(text: '写字');
    final files = _FakeFiles();
    await _pumpSettings(tester, controller, files);

    await _tapRow(tester, 'export-action');
    await _tapRow(tester, 'export-default');

    expect(files.saveToDefaultCalls, hasLength(1));
    expect(files.saveToDefaultCalls.single, contains('写字'));
    expect(files.saveAsCalls, isEmpty);
    // 封存后选项自动收起，并提示存到了默认位置。
    expect(_optionsHeight(tester, 'export'), 0);
    expect(find.text('已 封 存 · 默 认 位 置'), findsOneWidget);

    await controller.deleteTodo(controller.todos.single.id);
    expect(controller.todos, isEmpty);

    await _tapRow(tester, 'import-action');
    await _tapRow(tester, 'import-default');

    expect(files.readFromDefaultCalls, 1);
    expect(files.pickJsonCalls, 0);
    expect(controller.todos.map((todo) => todo.text), contains('写字'));
  });

  testWidgets('默认位置没有备份时明确提示', (tester) async {
    final controller = await _controller(_MemoryStore());
    addTearDown(controller.dispose);
    final files = _FakeFiles();
    await _pumpSettings(tester, controller, files);

    await _tapRow(tester, 'import-action');
    expect(_inside('import', find.text('尚 无')), findsOneWidget);

    await _tapRow(tester, 'import-default');

    expect(files.readFromDefaultCalls, 1);
    expect(find.text('默 认 位 置 尚 无 备 份'), findsOneWidget);
    // 提示后仍留在展开态，方便改选另一份文件。
    expect(_optionsHeight(tester, 'import'), greaterThan(0));
  });

  testWidgets('默认位置已有备份时显示封存时间', (tester) async {
    final controller = await _controller(_MemoryStore());
    addTearDown(controller.dispose);
    final files = _FakeFiles(savedAt: DateTime(2026, 8, 13, 9, 7));
    await _pumpSettings(tester, controller, files);

    await _tapRow(tester, 'export-action');

    expect(_inside('export', find.text('已 有 · 08-13 09:07')), findsOneWidget);
    expect(_inside('import', find.text('已 有 · 08-13 09:07')), findsOneWidget);
  });

  testWidgets('另选位置封存后给出所在路径', (tester) async {
    final controller = await _controller(_MemoryStore());
    addTearDown(controller.dispose);
    final files = _FakeFiles();
    await _pumpSettings(tester, controller, files);

    await _tapRow(tester, 'export-action');
    await _tapRow(tester, 'export-pick');

    expect(files.saveAsCalls, hasLength(1));
    expect(files.saveToDefaultCalls, isEmpty);
    expect(find.text('/chosen/backup.json'), findsOneWidget);
  });

  testWidgets('取消另选位置不提示已封存', (tester) async {
    final controller = await _controller(_MemoryStore());
    addTearDown(controller.dispose);
    final files = _FakeFiles(pickSaved: false);
    await _pumpSettings(tester, controller, files);

    await _tapRow(tester, 'export-action');
    await _tapRow(tester, 'export-pick');

    expect(find.text('未 保 存'), findsOneWidget);
    expect(find.text('已 封 存'), findsNothing);
  });

  testWidgets('另选文件收录走选择器', (tester) async {
    final controller = await _controller(_MemoryStore());
    addTearDown(controller.dispose);
    await controller.addTodo(text: '读书');
    final payload = controller.exportBackup();
    await controller.deleteTodo(controller.todos.single.id);
    final files = _FakeFiles(pickedContent: payload);
    await _pumpSettings(tester, controller, files);

    await _tapRow(tester, 'import-action');
    await _tapRow(tester, 'import-pick');

    expect(files.pickJsonCalls, 1);
    expect(files.readFromDefaultCalls, 0);
    expect(controller.todos.map((todo) => todo.text), contains('读书'));
  });

  testWidgets('Web 封存直接下载、收录直接选文件，不展开位置菜单', (tester) async {
    final controller = await _controller(_MemoryStore());
    addTearDown(controller.dispose);
    final files = _FakeFiles(supported: false);
    await _pumpSettings(tester, controller, files);

    // Web 没有可回读的默认目录，不查询默认文件，也不构建二级选项。
    expect(files.defaultInfoCalls, 0);
    expect(_row('export-options'), findsNothing);
    expect(_row('import-options'), findsNothing);
    expect(_row('export-default'), findsNothing);
    expect(_row('export-pick'), findsNothing);
    expect(_row('import-default'), findsNothing);
    expect(_row('import-pick'), findsNothing);
    expect(find.text(backupDownloadLocation), findsOneWidget);
    expect(find.text('选择备份文件'), findsOneWidget);

    await _tapRow(tester, 'export-action');
    expect(files.saveToDefaultCalls, hasLength(1));
    expect(files.saveAsCalls, isEmpty);
    expect(find.text('已 封 存 · 浏 览 器 下 载'), findsOneWidget);
    expect(find.text('封 存 所 在'), findsNothing);

    await _tapRow(tester, 'import-action');
    expect(files.pickJsonCalls, 1);
    expect(files.readFromDefaultCalls, 0);
  });
}
