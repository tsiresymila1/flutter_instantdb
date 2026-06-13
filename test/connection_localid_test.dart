import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

void main() {
  group('ConnectionStatus enum', () {
    test('has the five upstream states', () {
      expect(ConnectionStatus.values, hasLength(5));
      expect(ConnectionStatus.values, containsAll(const [
        ConnectionStatus.connecting,
        ConnectionStatus.opened,
        ConnectionStatus.authenticated,
        ConnectionStatus.closed,
        ConnectionStatus.errored,
      ]));
    });
  });

  group('getLocalId', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    test('same name returns a stable id; different names differ', () async {
      final dir = 'test_localid_${DateTime.now().microsecondsSinceEpoch}';
      final db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(syncEnabled: false, persistenceDir: dir),
      );

      final a1 = await db.getLocalId('device');
      final a2 = await db.getLocalId('device');
      final b = await db.getLocalId('session');

      expect(a1, isNotEmpty);
      expect(a1, equals(a2));
      expect(a1, isNot(equals(b)));

      await db.dispose();
    });

    test('id persists across re-init with same persistenceDir', () async {
      final dir = 'test_localid_persist_${DateTime.now().microsecondsSinceEpoch}';

      final db1 = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(syncEnabled: false, persistenceDir: dir),
      );
      final first = await db1.getLocalId('device');
      await db1.dispose();

      final db2 = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(syncEnabled: false, persistenceDir: dir),
      );
      final second = await db2.getLocalId('device');
      await db2.dispose();

      expect(second, equals(first));
    });
  });

  group('InstantDB.connectionStatus', () {
    test('exposes the enum signal; closed when sync disabled', () async {
      final dir = 'test_connstatus_${DateTime.now().microsecondsSinceEpoch}';
      final db = await InstantDB.init(
        appId: 'test-app-id',
        config: InstantConfig(syncEnabled: false, persistenceDir: dir),
      );

      expect(db.connectionStatus.value, ConnectionStatus.closed);
      // Deprecated bool getter still works.
      // ignore: deprecated_member_use
      expect(db.isOnline.value, isFalse);

      await db.dispose();
    });
  });
}
