import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import 'backup_file_stub.dart'
    if (dart.library.io) 'backup_file_io.dart'
    if (dart.library.html) 'backup_file_web.dart'
    as platform;

/// 默认封存文件名。固定不带时间戳，默认位置反复封存只保留最新一份。
const defaultBackupFilename = 'inktimer-backup.json';

/// Web 没有可读写的固定目录，只能交给浏览器下载，用这个字符串表示去处。
const backupDownloadLocation = '浏览器下载';

class BackupSaveResult {
  const BackupSaveResult({required this.saved, this.location});

  final bool saved;
  final String? location;
}

/// 默认位置的状态。用于在界面上说明「默认位置」当前有没有备份、在哪。
class BackupDefaultInfo {
  const BackupDefaultInfo({required this.supported, this.path, this.savedAt});

  /// 当前平台是否有可读写的默认位置。Web 没有。
  final bool supported;

  /// 默认封存文件的完整路径。
  final String? path;

  /// 默认封存文件的最后修改时间；为空表示尚未封存过。
  final DateTime? savedAt;

  bool get exists => savedAt != null;
}

class BackupFileService {
  const BackupFileService();

  /// 当前平台是否有可读写的默认位置。编译期就能确定，界面首帧即可据此布局。
  bool get supportsDefaultLocation => platform.supportsDefaultLocation;

  /// 默认位置的信息，导出与导入共用同一个路径。
  Future<BackupDefaultInfo> defaultInfo() => platform.defaultInfo();

  /// 封存到默认位置，覆盖同名文件。
  Future<BackupSaveResult> saveToDefault(String content) =>
      platform.saveToDefault(content);

  /// 从默认位置读取。返回 null 表示默认位置没有备份。
  Future<String?> readFromDefault() => platform.readFromDefault();

  /// 由用户另选位置封存。
  Future<BackupSaveResult> saveAs(String content) async {
    final bytes = utf8.encode(content);
    final path = await FilePicker.saveFile(
      dialogTitle: '封存备份',
      fileName: defaultBackupFilename,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: bytes,
    );
    if (path == null) return const BackupSaveResult(saved: false);
    // 部分桌面平台只返回路径而不落盘，这里补写一次保证内容存在。
    await platform.ensureWritten(path, content);
    return BackupSaveResult(saved: true, location: path);
  }

  /// 由用户另选文件收录。
  Future<String?> pickJson() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final bytes = result.files.single.bytes;
    if (bytes != null) return utf8.decode(bytes, allowMalformed: false);
    return platform.readPickedFile(result.files.single);
  }
}
