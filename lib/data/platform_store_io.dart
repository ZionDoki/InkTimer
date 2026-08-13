import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'key_value_store_base.dart';

Future<KeyValueStore> createStore() async {
  final preferences = await SharedPreferences.getInstance();
  return _NativeKeyValueStore(preferences, await _readLegacyTauriStore());
}

class _NativeKeyValueStore implements KeyValueStore {
  _NativeKeyValueStore(this._preferences, this._legacy);

  final SharedPreferences _preferences;
  final Map<String, String> _legacy;

  @override
  Future<String?> read(String key) async {
    final current = _preferences.getString(key);
    if (current != null) return current;
    final legacy = _legacy[key];
    if (legacy != null) {
      await _preferences.setString(key, legacy);
    }
    return legacy;
  }

  @override
  Future<void> write(String key, String value) async {
    await _preferences.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _preferences.remove(key);
  }

  @override
  Future<void> flush() async {
    await _preferences.reload();
  }
}

Future<Map<String, String>> _readLegacyTauriStore() async {
  final candidates = <File>[];
  try {
    final support = await getApplicationSupportDirectory();
    candidates.add(File('${support.path}${Platform.pathSeparator}uptimer.dat'));
  } on Object {
    // 某些测试或受限平台没有 application support 目录。
  }
  try {
    final documents = await getApplicationDocumentsDirectory();
    candidates.add(
      File('${documents.path}${Platform.pathSeparator}uptimer.dat'),
    );
  } on Object {
    // documents 目录不是所有桌面嵌入器都可用。
  }
  for (final file in candidates) {
    try {
      if (!await file.exists()) continue;
      final decoded = jsonDecode(await file.readAsString());
      final values = <String, String>{};
      _collectLegacyValues(decoded, values);
      if (values.isNotEmpty) return values;
    } on Object {
      // 旧文件损坏时留给用户通过备份导入，不阻塞新应用启动。
    }
  }
  return const {};
}

void _collectLegacyValues(Object? value, Map<String, String> output) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String && key.startsWith('uptimer.')) {
        final stored = entry.value;
        output[key] = stored is String ? stored : jsonEncode(stored);
      } else {
        _collectLegacyValues(entry.value, output);
      }
    }
  } else if (value is List) {
    for (final item in value) {
      _collectLegacyValues(item, output);
    }
  }
}
