import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../domain/backup.dart';
import '../../domain/models.dart';
import '../../services/backup_file_service.dart';
import '../../state/app_controller.dart';
import '../theme/zen_theme.dart';
import '../widgets/zen_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    this.files = const BackupFileService(),
  });

  final AppController controller;
  final BackupFileService files;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _confirmTemplateId;
  Timer? _confirmTimer;
  bool _confirmClearHistory = false;
  Timer? _historyTimer;
  late final Future<PackageInfo> _packageInfo;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _packageInfo = PackageInfo.fromPlatform();
    controller.addListener(_changed);
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    _confirmTimer?.cancel();
    _historyTimer?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _update(AppSettings settings) =>
      controller.updateSettings(settings);

  void _toast(String message) {
    final palette = ZenPalette.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: inkText(context, size: 12, color: palette.ink, spacing: 2.5),
          ),
          backgroundColor: palette.paperDeep,
          behavior: SnackBarBehavior.floating,
          elevation: 5,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _export() async {
    final now = DateTime.now();
    final filename =
        'inktimer-backup-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';
    final result = await widget.files.saveJson(
      filename,
      controller.exportBackup(),
    );
    if (!mounted) return;
    _toast(result.saved ? '已 封 存' : '未 保 存');
    if (result.saved && result.location != null && result.location != '浏览器下载') {
      await showDialog<void>(
        context: context,
        builder: (context) {
          final palette = ZenPalette.of(context);
          return AlertDialog(
            backgroundColor: palette.paper,
            title: Text('封 存 所 在', style: inkText(context, spacing: 4)),
            content: SelectableText(
              result.location!,
              style: TextStyle(fontSize: 12, color: palette.inkSoft),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('知 道', style: inkText(context, spacing: 3)),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _import() async {
    try {
      final content = await widget.files.pickJson();
      if (content == null) return;
      final report = await controller.importBackup(content);
      if (!mounted) return;
      if (report.changed == 0 && report.skipped > 0) {
        _toast('未 能 收 录 · 无 可 用 数 据');
        return;
      }
      _toast(
        '已 收 录 · 新增 笺${report.templatesAdded}/录${report.sessionsAdded}/事${report.todosAdded}'
        ' · 更新 笺${report.templatesUpdated}/录${report.sessionsUpdated}/事${report.todosUpdated}'
        '${report.settingsUpdated ? ' · 设置已更新' : ''}'
        '${report.skipped > 0 ? ' · 略 过 ${report.skipped}' : ''}',
      );
    } on BackupException catch (error) {
      if (mounted) _toast('未 能 收 录 · ${error.message}');
    } on Object {
      if (mounted) _toast('未 能 收 录');
    }
  }

  void _deleteTemplate(TimerTemplate template) {
    if (_confirmTemplateId == template.id) {
      _confirmTimer?.cancel();
      setState(() => _confirmTemplateId = null);
      unawaited(controller.deleteTemplate(template.id));
      return;
    }
    _confirmTimer?.cancel();
    setState(() => _confirmTemplateId = template.id);
    _confirmTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _confirmTemplateId = null);
    });
  }

  void _clearHistory() {
    if (_confirmClearHistory) {
      _historyTimer?.cancel();
      setState(() => _confirmClearHistory = false);
      unawaited(controller.clearHistory());
      _toast('功 课 簿 已 清');
      return;
    }
    setState(() => _confirmClearHistory = true);
    _historyTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _confirmClearHistory = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    final palette = ZenPalette.of(context);
    return ZenPage(
      title: '设 置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingRow(
            label: '音 量',
            child: Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: settings.volume,
                      divisions: 20,
                      onChanged: (value) =>
                          _update(settings.copyWith(volume: value)),
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text(
                      '${(settings.volume * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: palette.inkSoft),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _SettingRow(
            label: '音 效',
            child: _InkSwitch(
              value: settings.soundOn,
              onChanged: (value) => _update(settings.copyWith(soundOn: value)),
            ),
          ),
          if (!controller.audioAvailable)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 10),
              child: Text(
                '音 频 不 可 用 · 静 音 模 式',
                style: inkText(
                  context,
                  size: 11,
                  color: palette.work,
                  spacing: 2.5,
                ),
              ),
            ),
          _SettingRow(
            label: '触 感',
            child: _InkSwitch(
              value: settings.hapticsOn,
              onChanged: (value) =>
                  _update(settings.copyWith(hapticsOn: value)),
            ),
          ),
          _SettingRow(
            label: '保 持 亮 屏',
            child: _InkSwitch(
              value: settings.keepAwake,
              onChanged: (value) =>
                  _update(settings.copyWith(keepAwake: value)),
            ),
          ),
          _SettingRow(
            label: '主 题',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkChip(
                  label: '宣 纸',
                  selected: settings.theme == 'paper',
                  filled: true,
                  onTap: () => _update(settings.copyWith(theme: 'paper')),
                ),
                const SizedBox(width: 8),
                InkChip(
                  label: '墨 夜',
                  selected: settings.theme == 'ink',
                  filled: true,
                  onTap: () => _update(settings.copyWith(theme: 'ink')),
                ),
              ],
            ),
          ),
          const ZenSectionTitle('数 据'),
          _ActionRow(
            label: '封 存 备 份',
            detail: 'templates · sessions · todos · settings',
            onTap: _export,
          ),
          _ActionRow(label: '收 录 备 份', onTap: _import),
          _ActionRow(
            label: _confirmClearHistory ? '确 认 清 空 功 课 簿' : '清 空 功 课 簿',
            danger: _confirmClearHistory,
            detail: '${controller.sessions.length} 条记录',
            onTap: _clearHistory,
          ),
          const ZenSectionTitle('笺 匣'),
          if (controller.templates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '一 笺 不 剩 · 可 重 置 内 置',
                textAlign: TextAlign.center,
                style: inkText(
                  context,
                  size: 11,
                  color: palette.inkSoft,
                  spacing: 4,
                ),
              ),
            )
          else
            for (final template in controller.templates)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: palette.inkFaint)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        template.label,
                        overflow: TextOverflow.ellipsis,
                        style: inkText(context, size: 11, spacing: 2.5),
                      ),
                    ),
                    if (template.builtin == true)
                      Text(
                        '内 置',
                        style: inkText(
                          context,
                          size: 11,
                          color: palette.inkSoft,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Text(
                      _kindName(template.kind),
                      style: inkText(
                        context,
                        size: 11,
                        color: palette.inkSoft,
                        spacing: 2,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _deleteTemplate(template),
                      child: Text(
                        _confirmTemplateId == template.id ? '确 认' : '删',
                        style: inkText(
                          context,
                          size: _confirmTemplateId == template.id ? 9 : 11,
                          color: _confirmTemplateId == template.id
                              ? palette.work
                              : palette.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          _ActionRow(
            label: '重 置 内 置 笺',
            onTap: () async {
              await controller.resetBuiltinTemplates();
              if (mounted) _toast('已 重 置');
            },
          ),
          const SizedBox(height: 54),
          FutureBuilder<PackageInfo>(
            future: _packageInfo,
            builder: (context, snapshot) => Text(
              _versionFooter(snapshot.data),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: palette.inkFaint,
                letterSpacing: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _versionFooter(PackageInfo? info) {
  if (info == null) return '成 时 · FLUTTER';
  final build = info.buildNumber.isEmpty ? '' : '+${info.buildNumber}';
  return '成 时 · ${info.version}$build · FLUTTER';
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.inkFaint)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: inkText(context, size: 11, spacing: 3)),
          ),
          child,
        ],
      ),
    );
  }
}

class _InkSwitch extends StatelessWidget {
  const _InkSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Semantics(
      toggled: value,
      button: true,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          width: 42,
          height: 22,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: value ? palette.work : palette.inkFaint),
            color: value ? palette.work.withValues(alpha: 0.09) : null,
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 240),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? palette.work : palette.inkSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.onTap,
    this.detail,
    this.danger = false,
  });

  final String label;
  final String? detail;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.inkFaint)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: inkText(
                  context,
                  size: 11,
                  color: danger ? palette.work : palette.ink,
                  spacing: 3,
                ),
              ),
            ),
            if (detail != null)
              Flexible(
                child: Text(
                  detail!,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, color: palette.inkSoft),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _kindName(TemplateKind kind) => switch (kind) {
  TemplateKind.pomodoro => '番 茄',
  TemplateKind.interval => '间 歇',
  TemplateKind.accumulate => '积 累',
};
