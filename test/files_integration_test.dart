import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

void main() {
  group('Files / \$files integration', () {
    late InstantDB db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      db = await InstantDB.init(
        appId: 'test-app-id',
        config:
            InstantConfig(syncEnabled: false, persistenceDir: 'test_files_$id'),
      );
    });

    tearDown(() async => db.dispose());

    test('db.storage exposes an InstantStorage', () {
      expect(db.storage, isA<InstantStorage>());
    });

    test(r'$files namespace is queryable without error', () async {
      final r = await db.queryOnce({r'$files': {}});
      expect(r.hasError, isFalse);
      // Offline: no files synced yet.
      expect(r.documents, isEmpty);
    });

    test(r'tx[$files][id].delete() produces a delete chunk', () async {
      // Should not throw; removes any local refs.
      await db.transact(db.tx[r'$files']['f1'].delete());
      final r = await db.queryOnce({r'$files': {}});
      expect(r.documents, isEmpty);
    });
  });
}
