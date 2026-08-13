import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import 'backup_file_stub.dart'
    if (dart.library.io) 'backup_file_io.dart'
    if (dart.library.html) 'backup_file_web.dart'
    as platform;

class BackupSaveResult {
  const BackupSaveResult({required this.saved, this.location});

  final bool saved;
  final String? location;
}

class BackupFileService {
  const BackupFileService();

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

  Future<BackupSaveResult> saveJson(String filename, String content) =>
      platform.saveJson(filename, content);
}
