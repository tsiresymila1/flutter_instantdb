import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_instantdb/flutter_instantdb.dart';

void main() {
  group('TxOpts', () {
    test('defaults to upsert true', () {
      expect(const TxOpts().upsert, isTrue);
      expect(const TxOpts(upsert: false).upsert, isFalse);
    });
  });

  group('TransactionChunk.ruleParams', () {
    test('attaches ruleParams to every operation options', () {
      final chunk = TransactionChunk([
        Operation(type: OperationType.update, entityType: 'docs',
            entityId: 'd1', data: {'title': 'x'}),
      ]).ruleParams({'token': 'abc'});

      expect(chunk.operations.single.options?['ruleParams'],
          equals({'token': 'abc'}));
    });

    test('preserves existing options and lookupRef', () {
      final chunk = TransactionChunk([
        Operation(type: OperationType.update, entityType: 'docs',
            entityId: 'd1', data: {'a': 1}, options: {'upsert': false},
            lookupRef: const LookupRef(
                entityType: 'docs', attribute: 'slug', value: 's')),
      ]).ruleParams({'token': 'abc'});

      final op = chunk.operations.single;
      expect(op.options?['upsert'], isFalse);
      expect(op.options?['ruleParams'], equals({'token': 'abc'}));
      expect(op.lookupRef?.attribute, equals('slug'));
    });
  });
}
