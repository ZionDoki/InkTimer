import 'key_value_store_base.dart';
import 'platform_store_stub.dart'
    if (dart.library.io) 'platform_store_io.dart'
    if (dart.library.html) 'platform_store_web.dart'
    as platform;

export 'key_value_store_base.dart';

Future<KeyValueStore> createPlatformKeyValueStore() => platform.createStore();
