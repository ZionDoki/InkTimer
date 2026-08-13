import 'key_value_store.dart';
import 'volatile_store.dart';

typedef KeyValueStoreFactory = Future<KeyValueStore> Function();

class StoreBootstrapResult {
  const StoreBootstrapResult({required this.store, this.notice});

  final KeyValueStore store;
  final String? notice;
}

Future<StoreBootstrapResult> initializeKeyValueStore({
  KeyValueStoreFactory? create,
}) async {
  try {
    final store = await (create ?? createPlatformKeyValueStore)();
    const probeKey = 'uptimer.storage.probe';
    final probeValue = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      await store.write(probeKey, probeValue);
      if (await store.read(probeKey) != probeValue) {
        throw StateError('persistent storage probe failed');
      }
    } finally {
      await store.remove(probeKey);
    }
    return StoreBootstrapResult(store: store);
  } on Object {
    return StoreBootstrapResult(
      store: VolatileKeyValueStore(),
      notice: '存 储 暂 不 可 用 · 本 次 数 据 在 重 启 后 不 会 保 留',
    );
  }
}
