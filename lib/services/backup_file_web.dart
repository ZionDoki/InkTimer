import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

import 'backup_file_service.dart';

Future<String?> readPickedFile(PlatformFile file) async {
  final bytes = file.bytes;
  return bytes == null ? null : utf8.decode(bytes, allowMalformed: false);
}

/// 浏览器没有应用可读写的固定目录，默认位置不可用。
const supportsDefaultLocation = false;

Future<BackupDefaultInfo> defaultInfo() async =>
    const BackupDefaultInfo(supported: false);

Future<BackupSaveResult> saveToDefault(String content) async {
  try {
    final anchor = web.HTMLAnchorElement()
      ..href =
          'data:application/json;charset=utf-8,${Uri.encodeComponent(content)}'
      ..download = defaultBackupFilename;
    anchor.click();
    return const BackupSaveResult(
      saved: true,
      location: backupDownloadLocation,
    );
  } on Object {
    return const BackupSaveResult(saved: false);
  }
}

Future<String?> readFromDefault() async => null;

Future<void> ensureWritten(String path, String content) async {}
