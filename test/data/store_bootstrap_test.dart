import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/data/key_value_store.dart';
import 'package:uptimer/data/store_bootstrap.dart';
import 'package:uptimer/data/volatile_store.dart';

class MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> flush() async {}
}

class SilentFailureStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> flush() async {}
}

void main() {
  test('持久化探针成功时使用平台存储且无需提示', () async {
    final store = MemoryStore();
    final result = await initializeKeyValueStore(create: () async => store);
    expect(result.store, same(store));
    expect(result.notice, isNull);
  });

  test('创建抛错或静默写失败时降级内存并明确告知数据风险', () async {
    final thrown = await initializeKeyValueStore(
      create: () async => throw StateError('unavailable'),
    );
    final silent = await initializeKeyValueStore(
      create: () async => SilentFailureStore(),
    );

    for (final result in [thrown, silent]) {
      expect(result.store, isA<VolatileKeyValueStore>());
      expect(result.notice, contains('重 启 后 不 会 保 留'));
    }
  });
}
