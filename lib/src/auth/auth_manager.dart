import 'dart:async';

import 'package:dio/dio.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../core/types.dart';

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
