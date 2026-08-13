import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:uptimer/services/backup_file_io.dart' as io;
import 'package:uptimer/services/backup_file_service.dart';

/// 把文档目录指向临时目录，用真实文件系统验证默认位置的读写语义。
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  late Directory root;
  late PathProviderPlatform original;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('inktimer-backup-test');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = original;
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('默认封存位置', () {
    test('默认文件名固定不含时间戳', () {
      expect(defaultBackupFilename, 'inktimer-backup.json');
      expect(RegExp(r'\d').hasMatch(defaultBackupFilename), isFalse);
    });

    test('尚未封存时报告位置可用但没有备份', () async {
      final info = await io.defaultInfo();

      expect(info.supported, isTrue);
      expect(info.path, endsWith(defaultBackupFilename));
      expect(info.exists, isFalse);
      expect(info.savedAt, isNull);
    });

    test('反复封存只保留最新一份，不再累加副本', () async {
      await io.saveToDefault('{"v":1}');
      await io.saveToDefault('{"v":2}');
      final result = await io.saveToDefault('{"v":3}');

      expect(result.saved, isTrue);
      final files = root
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .toList();
      expect(files, [defaultBackupFilename]);
      expect(await io.readFromDefault(), '{"v":3}');
    });

    test('封存后不留临时文件', () async {
      await io.saveToDefault('{"v":1}');

      final leftovers = root
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('导出与导入共用同一路径，可直接往返', () async {
      const content = '{"app":"uptimer","version":2}';

      final saved = await io.saveToDefault(content);
      final info = await io.defaultInfo();

      expect(saved.location, info.path);
      expect(info.exists, isTrue);
      expect(info.savedAt, isNotNull);
      expect(await io.readFromDefault(), content);
    });

    test('默认位置没有文件时读取返回空', () async {
      expect(await io.readFromDefault(), isNull);
    });
  });

  group('另选位置补写', () {
    test('系统未落盘时补写内容', () async {
      final target = File('${root.path}${Platform.pathSeparator}picked.json');

      await io.ensureWritten(target.path, '{"v":1}');

      expect(await target.readAsString(), '{"v":1}');
    });

    test('空文件会被补写', () async {
      final target = File('${root.path}${Platform.pathSeparator}empty.json');
      await target.writeAsString('');

      await io.ensureWritten(target.path, '{"v":2}');

      expect(await target.readAsString(), '{"v":2}');
    });

    test('系统已写入的内容不被覆盖', () async {
      final target = File('${root.path}${Platform.pathSeparator}done.json');
      await target.writeAsString('{"written":"by-os"}');

      await io.ensureWritten(target.path, '{"v":3}');

      expect(await target.readAsString(), '{"written":"by-os"}');
    });
  });
}
