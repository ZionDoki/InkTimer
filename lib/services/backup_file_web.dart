import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

import 'backup_file_service.dart';

Future<String?> readPickedFile(PlatformFile file) async {
  final bytes = file.bytes;
  return bytes == null ? null : utf8.decode(bytes, allowMalformed: false);
}

Future<BackupSaveResult> saveJson(String filename, String content) async {
  try {
    final anchor = web.HTMLAnchorElement()
      ..href =
          'data:application/json;charset=utf-8,${Uri.encodeComponent(content)}'
      ..download = filename;
    anchor.click();
    return const BackupSaveResult(saved: true, location: '浏览器下载');
  } on Object {
    return const BackupSaveResult(saved: false);
  }
}
