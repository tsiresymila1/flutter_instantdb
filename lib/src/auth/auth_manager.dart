import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../core/types.dart';

/// Result of [AuthManager.createAuthorizationUrl]: the provider URL to open and
/// the PKCE [codeVerifier] to pass back to [AuthManager.exchangeCodeForToken].
class OAuthFlow {
  final String url;
  final String? codeVerifier;
  final String? state;

  const OAuthFlow({required this.url, this.codeVerifier, this.state});
}

class AuthManager {
  final String appId;
  final String baseUrl;
  final Dio _dio;

  final Signal<AuthUser?> _currentUser = signal(null);
  String? _refreshToken;

  AuthManager({required this.appId, required this.baseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          headers: {'Content-Type': 'application/json'},
        ),
      );

  ReadonlySignal<AuthUser?> get currentUser => _currentUser.readonly();

  Stream<AuthUser?> get onAuthStateChange => _currentUser.toStream();

  bool get isAuthenticated => computed(() => _currentUser.value != null).value;

  String? get refreshToken => computed(() => _refreshToken).value;

  /// Send magic code
  Future<void> sendMagicCode({required String email}) async {
    try {
      await _dio.post(
        '/runtime/auth/send_magic_code',
        data: {'app-id': appId, 'email': email},
      );
    } on DioException catch (e) {
      _handleError(e, 'Failed to send magic code');
    }
  }

  /// Verify magic code
  Future<AuthUser> verifyMagicCode({
    required String email,
    required String code,
    String? refreshToken,
  }) async {
    try {
      final response = await _dio.post(
        '/runtime/auth/verify_magic_code',
        data: {
          'app-id': appId,
          'email': email,
          'code': code,
          if (refreshToken != null) 'refresh-token': refreshToken,
        },
      );
      final user = AuthUser.fromJson(response.data['user']);
      _currentUser.value = user;
      _refreshToken = user.refreshToken;
      return user;
    } on DioException catch (e) {
      _handleError(e, 'Failed to verify magic code');
      rethrow;
    }
  }

  /// Verify refresh token
  Future<AuthUser> verifyRefreshToken({required String refreshToken}) async {
    try {
      final response = await _dio.post(
        '/runtime/auth/verify_refresh_token',
        data: {'app-id': appId, 'refresh-token': refreshToken},
      );
      final user = AuthUser.fromJson(response.data['user']);
      _currentUser.value = user;
      _refreshToken = refreshToken;
      return user;
    } on DioException catch (e) {
      _handleError(e, 'Failed to verify refresh token');
      rethrow;
    }
  }

  /// Sign in as guest
  Future<AuthUser> signInAsGuest() async {
    try {
      final response = await _dio.post(
        '/runtime/auth/sign_in_guest',
        data: {'app-id': appId},
      );
      final user = AuthUser.fromJson(response.data['user']);
      _currentUser.value = user;
      _refreshToken = user.refreshToken;
      return user;
    } on DioException catch (e) {
      _handleError(e, 'Failed to sign in as guest');
      rethrow;
    }
  }

  /// Exchange OAuth code for token
  Future<AuthUser> exchangeCodeForToken({
    required String code,
    String? codeVerifier,
    String? refreshToken,
  }) async {
    try {
      final response = await _dio.post(
        '/runtime/oauth/token',
        data: {
          'app_id': appId,
          'code': code,
          'code_verifier': codeVerifier,
          'refresh_token': refreshToken,
        },
      );
      final user = AuthUser.fromJson(response.data['user']);
      _currentUser.value = user;
      _refreshToken = user.refreshToken;
      return user;
    } on DioException catch (e) {
      _handleError(e, 'Failed to exchange code for token');
      rethrow;
    }
  }

  /// Build an OAuth authorization URL for the redirect flow.
  ///
  /// [clientName] is the OAuth client configured in the InstantDB dashboard
  /// (e.g. for Google/GitHub/LinkedIn/Apple). [redirectUri] must match an
  /// allowed redirect for that client. Open [OAuthFlow.url] in a browser /
  /// in-app webview / `flutter_web_auth_2`; on return, hand the `code` query
  /// param and [OAuthFlow.codeVerifier] to [exchangeCodeForToken].
  ///
  /// PKCE (S256) is enabled by default; set [usePKCE] to false to omit it.
  ///
  /// ```dart
  /// final flow = db.auth.createAuthorizationUrl(
  ///   clientName: 'google',
  ///   redirectUri: 'myapp://oauth',
  /// );
  /// // launch flow.url, capture ?code=... on redirect
  /// await db.auth.exchangeCodeForToken(
  ///   code: code,
  ///   codeVerifier: flow.codeVerifier,
  /// );
  /// ```
  OAuthFlow createAuthorizationUrl({
    required String clientName,
    required String redirectUri,
    bool usePKCE = true,
    List<String>? scopes,
  }) {
    final state = _randomString(16);
    String? codeVerifier;
    String? codeChallenge;
    if (usePKCE) {
      codeVerifier = _randomString(64);
      codeChallenge = base64UrlEncode(
        sha256.convert(ascii.encode(codeVerifier)).bytes,
      ).replaceAll('=', '');
    }

    final params = <String, String>{
      'app_id': appId,
      'client_name': clientName,
      'redirect_uri': redirectUri,
      'state': state,
      if (scopes != null && scopes.isNotEmpty) 'scope': scopes.join(' '),
      if (codeChallenge != null) 'code_challenge': codeChallenge,
      if (codeChallenge != null) 'code_challenge_method': 'S256',
    };

    final uri = Uri.parse(
      '$baseUrl/runtime/oauth/start',
    ).replace(queryParameters: params);

    return OAuthFlow(
      url: uri.toString(),
      codeVerifier: codeVerifier,
      state: state,
    );
  }

  /// Sign in with a Google ID token (from `google_sign_in`). [clientName] is the
  /// Google OAuth client name configured in the InstantDB dashboard.
  Future<AuthUser> signInWithGoogle({
    required String idToken,
    String clientName = 'google',
    String? nonce,
  }) => signInWithIdToken(
    idToken: idToken,
    clientName: clientName,
    nonce: nonce,
  );

  /// Sign in with an Apple identity token (from `sign_in_with_apple`).
  Future<AuthUser> signInWithApple({
    required String idToken,
    String clientName = 'apple',
    String? nonce,
  }) => signInWithIdToken(
    idToken: idToken,
    clientName: clientName,
    nonce: nonce,
  );

  /// Sign in with a Clerk session token. [clientName] is the Clerk client name
  /// configured in the InstantDB dashboard.
  Future<AuthUser> signInWithClerk({
    required String idToken,
    required String clientName,
  }) => signInWithIdToken(idToken: idToken, clientName: clientName);

  /// Sign in with a Firebase Auth ID token. [clientName] is the Firebase client
  /// name configured in the InstantDB dashboard.
  Future<AuthUser> signInWithFirebase({
    required String idToken,
    required String clientName,
  }) => signInWithIdToken(idToken: idToken, clientName: clientName);

  /// Sign in with ID token (OIDC)
  Future<AuthUser> signInWithIdToken({
    required String idToken,
    required String clientName,
    String? nonce,
    String? refreshToken,
  }) async {
    try {
      final response = await _dio.post(
        '/runtime/oauth/id_token',
        data: {
          'app_id': appId,
          'id_token': idToken,
          'client_name': clientName,
          if (nonce != null) 'nonce': nonce,
          if (refreshToken != null) 'refresh_token': refreshToken,
        },
      );
      final user = AuthUser.fromJson(response.data['user']);
      _currentUser.value = user;
      _refreshToken = user.refreshToken;
      return user;
    } on DioException catch (e) {
      _handleError(e, 'Failed to sign in with ID token');
      rethrow;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    if (_refreshToken == null) {
      _currentUser.value = null;
      return;
    }
    try {
      await _dio.post(
        '/runtime/signout',
        data: {'app_id': appId, 'refresh_token': _refreshToken},
      );
      _refreshToken = null;
      _currentUser.value = null;
    } on DioException catch (e) {
      _handleError(e, 'Failed to sign out');
    }
  }

  // Helpers
  static const _pkceChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  String _randomString(int length) {
    final rand = Random.secure();
    return List.generate(
      length,
      (_) => _pkceChars[rand.nextInt(_pkceChars.length)],
    ).join();
  }

  void _handleError(DioException e, String fallbackMessage) {
    final message =
        e.response?.data?['message'] ?? e.message ?? fallbackMessage;
    throw InstantException(
      message: message,
      code: 'auth_error',
      originalError: e,
    );
  }
}
