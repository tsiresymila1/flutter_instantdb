import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_instantdb/src/typed/annotations.dart';

void main() {
  group('InstantField unique/indexed flags', () {
    test('defaults are false', () {
      const f = InstantField('x');
      expect(f.name, 'x');
      expect(f.unique, false);
      expect(f.indexed, false);
    });

    test('named params set flags', () {
      const f = InstantField('email', unique: true, indexed: true);
      expect(f.name, 'email');
      expect(f.unique, true);
      expect(f.indexed, true);
    });
  });
}
