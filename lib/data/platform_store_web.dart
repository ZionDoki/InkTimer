import 'package:web/web.dart' as web;

import 'key_value_store_base.dart';

Future<KeyValueStore> createStore() async => _WebKeyValueStore();

class _WebKeyValueStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async {
    try {
      return web.window.localStorage.getItem(key);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      web.window.localStorage.setItem(key, value);
    } on Object {
      // 隐私模式或配额不足时静默降级，和旧 Web 实现一致。
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      web.window.localStorage.removeItem(key);
    } on Object {
      // 删除失败不影响主流程。
    }
  }

  @override
  Future<void> flush() async {}
}
