import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'backup_file_service.dart';

Future<String?> readPickedFile(PlatformFile file) async {
  final path = file.path;
  if (path == null) return null;
  return File(path).readAsString();
}

/// 默认位置统一取应用文档目录：各平台都可读写，macOS 沙箱下也在容器内合法。
/// 导出与导入共用这一个路径，保证「默认位置」两端一致。
const supportsDefaultLocation = true;

Future<File?> _defaultFile() async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    await directory.create(recursive: true);
    return File(
      '${directory.path}${Platform.pathSeparator}$defaultBackupFilename',
    );
  } on Object {
    return null;
  }
}

Future<BackupDefaultInfo> defaultInfo() async {
  final file = await _defaultFile();
  if (file == null) return const BackupDefaultInfo(supported: false);
  try {
    if (await file.exists()) {
      final stat = await file.stat();
      return BackupDefaultInfo(
        supported: true,
        path: file.path,
        savedAt: stat.modified,
      );
    }
  } on Object {
    // 读不到状态时按「尚未封存」处理，仍然允许封存。
  }
  return BackupDefaultInfo(supported: true, path: file.path);
}

Future<BackupSaveResult> saveToDefault(String content) async {
  final file = await _defaultFile();
  if (file == null) return const BackupSaveResult(saved: false);
  try {
    // 先写临时文件再原子替换，写入中断不会毁掉已有的那一份备份。
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(content, flush: true);
    await temporary.rename(file.path);
    return BackupSaveResult(saved: true, location: file.path);
  } on Object {
    return const BackupSaveResult(saved: false);
  }
}

Future<String?> readFromDefault() async {
  final file = await _defaultFile();
  if (file == null) return null;
  try {
    if (!await file.exists()) return null;
    return await file.readAsString();
  } on Object {
    return null;
  }
}

Future<void> ensureWritten(String path, String content) async {
  try {
    final file = File(path);
    if (await file.exists() && await file.length() > 0) return;
    await file.writeAsString(content, flush: true);
  } on Object {
    // 选定位置由系统写入时这里无需接管。
  }
}
