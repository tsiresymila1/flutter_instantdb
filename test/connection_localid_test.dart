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
}
