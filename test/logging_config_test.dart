import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:flutter_instantdb/src/core/logging_config.dart';

void main() {
  group('InstantDBLogging.configure', () {
    test('a later configure() re-applies the level (verboseLogging takes effect '
        'on a second init)', () {
      // First init — default (non-verbose) level.
      InstantDBLogging.configure(level: Level.INFO);
      expect(InstantDBLogging.root.level, Level.INFO);

      // Second init with verboseLogging: true (=> FINE). Before the fix the
      // _isConfigured guard made this a no-op and the level stayed INFO.
      InstantDBLogging.configure(level: Level.FINE);
      expect(InstantDBLogging.root.level, Level.FINE);
      expect(Logger.root.level, Level.FINE);
      expect(InstantDBLogging.syncEngine.level, Level.FINE);
      expect(InstantDBLogging.queryEngine.level, Level.FINE);
      // .debug() logs at FINE — now loggable.
      expect(InstantDBLogging.root.isLoggable(Level.FINE), isTrue);
    });

    test('the level can also be lowered again on a later configure()', () {
      InstantDBLogging.configure(level: Level.FINE);
      expect(InstantDBLogging.root.level, Level.FINE);
      InstantDBLogging.configure(level: Level.WARNING);
      expect(InstantDBLogging.root.level, Level.WARNING);
      expect(InstantDBLogging.root.isLoggable(Level.INFO), isFalse);
    });
  });
}
