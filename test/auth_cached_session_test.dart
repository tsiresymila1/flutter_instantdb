import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';
import 'package:flutter_instantdb/src/auth/auth_manager.dart';

void main() {
  test('rejected refresh token clears the locally restored identity', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.statusCode = 401;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"message":"Invalid token"}');
      request.response.close();
    });
    final auth = AuthManager(
      appId: 'test',
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
    auth.restoreCachedSession(
      const AuthUser(id: 'user', refreshToken: 'revoked'),
    );
    await expectLater(
      auth.verifyRefreshToken(refreshToken: 'revoked'),
      throwsA(isA<InstantException>()),
    );
    expect(auth.currentUser.value, isNull);
    expect(auth.refreshToken, isNull);
    await server.close(force: true);
  });
  test(
    'cached session supplies both user and refresh token before sync starts',
    () {
      final auth = AuthManager(appId: 'test', baseUrl: 'http://127.0.0.1');
      const user = AuthUser(
        id: 'user',
        email: 'offline@example.com',
        refreshToken: 'saved-token',
      );
      auth.restoreCachedSession(user);
      expect(auth.currentUser.value, user);
      expect(auth.refreshToken, 'saved-token');
      expect(auth.isAuthenticated, isTrue);
    },
  );
  test('a user without a refresh token cannot be restored locally', () {
    final auth = AuthManager(appId: 'test', baseUrl: 'http://127.0.0.1');
    expect(
      () => auth.restoreCachedSession(const AuthUser(id: 'user')),
      throwsArgumentError,
    );
    expect(auth.isAuthenticated, isFalse);
  });
}
