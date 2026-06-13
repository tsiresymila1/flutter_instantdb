import 'package:source_gen_test/source_gen_test.dart';
import 'package:flutter_instantdb_generator/src/instant_generator.dart';

Future<void> main() async {
  final reader = await initializeLibraryReaderForDirectory(
    'test/src',
    'model_fixtures.dart',
  );

  initializeBuildLogTracking();
  testAnnotatedElements<InstantModel>(
    reader,
    InstantGenerator(),
  );
}
