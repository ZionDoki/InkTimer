import 'package:file_picker/file_picker.dart';

import 'backup_file_service.dart';

Future<String?> readPickedFile(PlatformFile file) async => null;

Future<BackupSaveResult> saveJson(String filename, String content) async =>
    const BackupSaveResult(saved: false);
