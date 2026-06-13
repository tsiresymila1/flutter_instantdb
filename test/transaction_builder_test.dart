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

  group('EntityBuilder.lookup chainable', () {
    final tx = TransactionBuilder();

    test('lookup().update() sets lookupRef target and data', () {
      final chunk = tx['profiles'].lookup('email', 'a@b.com')
          .update({'name': 'A'});
      final op = chunk.operations.single;
      expect(op.type, OperationType.update);
      expect(op.entityType, 'profiles');
      expect(op.lookupRef?.attribute, 'email');
      expect(op.lookupRef?.value, 'a@b.com');
      expect(op.data, {'name': 'A'});
    });

    test('lookup().delete() sets lookupRef target', () {
      final chunk = tx['profiles'].lookup('email', 'a@b.com').delete();
      final op = chunk.operations.single;
      expect(op.type, OperationType.delete);
      expect(op.lookupRef?.attribute, 'email');
    });
  });

  group('upsert option', () {
    final tx = TransactionBuilder();

    test('update with upsert:false records option', () {
      final chunk = tx['goals']['g1']
          .update({'title': 'x'}, opts: const TxOpts(upsert: false));
      expect(chunk.operations.single.options?['upsert'], isFalse);
    });

    test('update without opts has no upsert option (defaults upsert)', () {
      final chunk = tx['goals']['g1'].update({'title': 'x'});
      final opts = chunk.operations.single.options;
      expect(opts == null || opts['upsert'] != false, isTrue);
    });

    test('merge with upsert:false records option', () {
      final chunk = tx['games']['gm1']
          .merge({'state': {'a': 1}}, opts: const TxOpts(upsert: false));
      expect(chunk.operations.single.options?['upsert'], isFalse);
    });
  });
}
