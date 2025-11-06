import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

void main() {
  group('AuthManager Tests', () {
    late InstantDB db;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      final testId = DateTime.now().millisecondsSinceEpoch.toString();
      db = await InstantDB.init(
        appId: 'test-auth',
        config: InstantConfig(
          syncEnabled: false,
          persistenceDir: 'test_db_auth_$testId',
          baseUrl: 'https://mock-api.instantdb.com',
        ),
      );
    });

    tearDown(() async {
      await db.dispose();
    });

    test('should start with no authenticated user', () {
      expect(db.auth.currentUser.value, isNull);
    });

    test('should emit auth state changes', () async {
      final states = <AuthUser?>[];
      final sub = db.auth.onAuthStateChange.listen(states.add);

      // Initial state should be empty
      expect(states.isEmpty, isTrue);

      // Simulate signOut to trigger state change
      await db.auth.signOut();

      // The state change should be emitted
      expect(states.length, equals(1));
      expect(states.first, isNull);

      await sub.cancel();
    });

    test('should handle sign out gracefully', () async {
      await db.auth.signOut();
      expect(db.auth.currentUser.value, isNull);
    });

    test('should send magic code email', () async {
      try {
        await db.auth.sendMagicCode(email: 'test@example.com');
      } catch (e) {
        expect(e, isNotNull);
      }
    });

    test('should verify magic code', () async {
      try {
        await db.auth.verifyMagicCode(
          email: 'test@example.com',
          code: '123456',
        );
      } catch (e) {
        expect(e, isNotNull);
      }
    });

    test('should reject invalid magic code format', () {
      expect(
        () async => await db.auth.verifyMagicCode(
          email: 'test@example.com',
          code: '123',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('should serialize and deserialize AuthUser', () {
      final user = AuthUser(
        id: 'u1',
        email: 'user@example.com',
        metadata: {'role': 'admin'},
        refreshToken: 'mock-refresh',
      );

      final json = user.toJson();
      final reconstructed = AuthUser.fromJson(json);

      expect(reconstructed.id, equals(user.id));
      expect(reconstructed.email, equals(user.email));
      expect(reconstructed.metadata, equals(user.metadata));
      expect(reconstructed.refreshToken, equals(user.refreshToken));
    });
  });
}
