import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../auth/auth_manager.dart';
import '../core/types.dart';

/// A file record from the InstantDB `$files` namespace / storage API.
class InstantFile {
  final String id;
  final String path;
  final String? url;
  final int? size;
  final String? contentType;

  const InstantFile({
    required this.id,
    required this.path,
    this.url,
    this.size,
    this.contentType,
  });

  factory InstantFile.fromJson(Map<String, dynamic> json) => InstantFile(
        id: (json['id'] ?? '').toString(),
        path: (json['path'] ?? json['filename'] ?? '').toString(),
        url: json['url'] as String?,
        size: json['size'] is int ? json['size'] as int : null,
        contentType:
            (json['content-type'] ?? json['contentType'])?.toString(),
      );
}

/// Client for the InstantDB storage REST API. Mirrors @instantdb/core
/// StorageAPI (`uploadFile`, `getDownloadUrl`, `deleteFile`).
class InstantStorage {
  final String appId;
  final String baseUrl;
  final AuthManager _authManager;
  final Dio _dio;

  /// Runs an InstaQL query once. Injected by [InstantDB] so [list] can read the
  /// `$files` namespace through the same reactive/sync pipeline as data queries.
  final Future<QueryResult> Function(Map<String, dynamic> query)?
      _queryDelegate;

  InstantStorage({
    required this.appId,
    required this.baseUrl,
    required AuthManager authManager,
    Future<QueryResult> Function(Map<String, dynamic> query)? queryDelegate,
    Dio? dio,
  })  : _authManager = authManager,
        _queryDelegate = queryDelegate,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            ));

  String? get _token => _authManager.refreshToken;

  Map<String, dynamic> _authHeader() =>
      _token != null ? {'authorization': 'Bearer $_token'} : {};

  /// Upload [bytes] to [path]. Returns the created file record.
  Future<InstantFile> uploadFile(
    String path,
    Uint8List bytes, {
    String? contentType,
    String? contentDisposition,
  }) async {
    final type = contentType ?? 'application/octet-stream';
    try {
      final response = await _dio.post(
        '/storage/upload',
        data: Stream<List<int>>.fromIterable([bytes]),
        options: Options(
          headers: {
            'app_id': appId,
            'path': path,
            'content-type': type,
            if (contentDisposition != null)
              'content-disposition': contentDisposition,
            Headers.contentLengthHeader: bytes.length,
            ..._authHeader(),
          },
          contentType: type,
        ),
      );
      final data = response.data;
      final Map? record = (data is Map && data['data'] is Map)
          ? data['data'] as Map
          : (data is Map ? data : null);
      if (record == null) {
        throw InstantException(
          message: 'Unexpected upload response shape',
          code: 'storage_error',
        );
      }
      return InstantFile.fromJson(Map<String, dynamic>.from(record));
    } on DioException catch (e) {
      throw _error(e, 'Failed to upload file');
    }
  }

  /// Get a signed download URL for the file at [path].
  Future<String> getDownloadUrl(String path) async {
    try {
      final response = await _dio.get(
        '/storage/signed-download-url',
        queryParameters: {'app_id': appId, 'filename': path},
      );
      final data = response.data;
      final url = (data is Map)
          ? (data['data'] is Map
              ? (data['data'] as Map)['url']
              : data['data'] ?? data['url'])
          : data;
      if (url == null || url.toString().isEmpty) {
        throw InstantException(
          message: 'No download url in response',
          code: 'storage_error',
        );
      }
      return url.toString();
    } on DioException catch (e) {
      throw _error(e, 'Failed to get download url');
    }
  }

  /// List uploaded files by querying the `$files` namespace.
  ///
  /// Mirrors @instantdb/core, where files are entities you read with a normal
  /// query (`db.useQuery({ $files: {} })`). Pass [where] / [order] / [limit] /
  /// [offset] to filter and page. Requires sync to be enabled so the `$files`
  /// namespace is populated.
  ///
  /// ```dart
  /// final files = await db.storage.list(order: {'serverCreatedAt': 'desc'});
  /// ```
  Future<List<InstantFile>> list({
    Map<String, dynamic>? where,
    Map<String, dynamic>? order,
    int? limit,
    int? offset,
  }) async {
    if (_queryDelegate == null) {
      throw InstantException(
        message: 'Storage.list requires an initialized InstantDB query engine',
        code: 'storage_error',
      );
    }
    final result = await _queryDelegate(<String, dynamic>{
      r'$files': <String, dynamic>{
        if (where != null) 'where': where,
        if (order != null) 'order': order,
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      },
    });
    if (result.hasError) {
      throw InstantException(
        message: result.error ?? 'Failed to list files',
        code: 'storage_error',
      );
    }
    final rows = result.data?[r'$files'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((e) => InstantFile.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Delete the file at [path].
  Future<void> delete(String path) async {
    try {
      await _dio.delete(
        '/storage/files',
        queryParameters: {'app_id': appId, 'filename': path},
        options: Options(headers: {..._authHeader()}),
      );
    } on DioException catch (e) {
      throw _error(e, 'Failed to delete file');
    }
  }

  InstantException _error(DioException e, String fallback) {
    final message =
        e.response?.data?['message'] ?? e.message ?? fallback;
    return InstantException(
      message: message.toString(),
      code: 'storage_error',
      originalError: e,
    );
  }
}
