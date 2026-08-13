import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'backup_file_service.dart';

Future<String?> readPickedFile(PlatformFile file) async {
  final path = file.path;
  if (path == null) return null;
  return File(path).readAsString();
}

Future<BackupSaveResult> saveJson(String filename, String content) async {
  try {
    Directory? directory;
    try {
      directory = await getDownloadsDirectory();
    } on Object {
      directory = null;
    }
    directory ??= await getApplicationDocumentsDirectory();
    await directory.create(recursive: true);
    final separator = Platform.pathSeparator;
    var path = '${directory.path}$separator$filename';
    var suffix = 2;
    while (await File(path).exists()) {
      final dot = filename.lastIndexOf('.');
      final stem = dot < 0 ? filename : filename.substring(0, dot);
      final extension = dot < 0 ? '' : filename.substring(dot);
      path = '${directory.path}$separator$stem-$suffix$extension';
      suffix += 1;
    }
    await File(path).writeAsString(content, flush: true);
    return BackupSaveResult(saved: true, location: path);
  } on Object {
    return const BackupSaveResult(saved: false);
  }
}
