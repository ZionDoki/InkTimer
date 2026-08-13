import 'key_value_store_base.dart';

Future<KeyValueStore> createStore() async => _MemoryKeyValueStore();

class _MemoryKeyValueStore implements KeyValueStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> flush() async {}
}
