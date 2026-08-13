import 'package:file_picker/file_picker.dart';

import 'backup_file_service.dart';

Future<String?> readPickedFile(PlatformFile file) async => null;

const supportsDefaultLocation = false;

Future<BackupDefaultInfo> defaultInfo() async =>
    const BackupDefaultInfo(supported: false);

Future<BackupSaveResult> saveToDefault(String content) async =>
    const BackupSaveResult(saved: false);

Future<String?> readFromDefault() async => null;

Future<void> ensureWritten(String path, String content) async {}
