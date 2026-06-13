import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_instantdb/src/storage/instant_storage.dart';
import 'package:flutter_instantdb/src/auth/auth_manager.dart';

class _MockDio extends Mock implements Dio {}

class _FakeAuth extends AuthManager {
  _FakeAuth() : super(appId: 'app1', baseUrl: 'https://api.instantdb.com');
}

Response<dynamic> _resp(dynamic data, String path) => Response<dynamic>(
      data: data,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );

void main() {
  late _MockDio dio;
  late InstantStorage storage;

  setUpAll(() {
    registerFallbackValue(Options());
  });

  setUp(() {
    dio = _MockDio();
    storage = InstantStorage(
      appId: 'app1',
      baseUrl: 'https://api.instantdb.com',
      authManager: _FakeAuth(),
      dio: dio,
    );
  });

  group('InstantFile', () {
    test('fromJson parses core fields', () {
      final f = InstantFile.fromJson({
        'id': 'f1',
        'path': 'photos/x.png',
        'url': 'https://cdn/x.png',
        'size': 1234,
        'content-type': 'image/png',
      });
      expect(f.id, 'f1');
      expect(f.path, 'photos/x.png');
      expect(f.url, 'https://cdn/x.png');
      expect(f.size, 1234);
      expect(f.contentType, 'image/png');
    });
  });

  group('uploadFile', () {
    test('POSTs to /storage/upload and returns InstantFile', () async {
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _resp(
            {'data': {'id': 'f1', 'path': 'photos/x.png'}},
            '/storage/upload',
          ));

      final file = await storage.uploadFile(
        'photos/x.png',
        Uint8List.fromList([1, 2, 3]),
        contentType: 'image/png',
      );

      expect(file.id, 'f1');
      expect(file.path, 'photos/x.png');

      final captured = verify(() => dio.post(
            captureAny(),
            data: any(named: 'data'),
            options: captureAny(named: 'options'),
          )).captured;
      expect(captured[0], '/storage/upload');
      final opts = captured[1] as Options;
      expect(opts.headers?['app_id'], 'app1');
      expect(opts.headers?['path'], 'photos/x.png');
      expect(opts.headers?['content-type'], 'image/png');
    });
  });

  group('getDownloadUrl', () {
    test('GETs signed-download-url and returns the url', () async {
      when(() => dio.get(
            any(),
            queryParameters: any(named: 'queryParameters'),
          )).thenAnswer((_) async => _resp(
            {'data': 'https://cdn/x.png?sig=abc'},
            '/storage/signed-download-url',
          ));

      final url = await storage.getDownloadUrl('photos/x.png');
      expect(url, 'https://cdn/x.png?sig=abc');

      final captured = verify(() => dio.get(
            captureAny(),
            queryParameters: captureAny(named: 'queryParameters'),
          )).captured;
      expect(captured[0], '/storage/signed-download-url');
      final qp = captured[1] as Map;
      expect(qp['app_id'], 'app1');
      expect(qp['filename'], 'photos/x.png');
    });
  });

  group('delete', () {
    test('DELETEs /storage/files with filename', () async {
      when(() => dio.delete(
            any(),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _resp({'ok': true}, '/storage/files'));

      await storage.delete('photos/x.png');

      final captured = verify(() => dio.delete(
            captureAny(),
            queryParameters: captureAny(named: 'queryParameters'),
            options: any(named: 'options'),
          )).captured;
      expect(captured[0], '/storage/files');
      final qp = captured[1] as Map;
      expect(qp['app_id'], 'app1');
      expect(qp['filename'], 'photos/x.png');
    });
  });
}
