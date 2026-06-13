import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/instant_generator.dart';

Builder instantBuilder(BuilderOptions options) =>
    PartBuilder([const InstantGenerator()], '.instant.dart');
