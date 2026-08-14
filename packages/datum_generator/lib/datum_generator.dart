library;

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import 'src/datum_generator.dart';

export 'src/core/annotations.dart';
export 'src/utils/json_utils.dart';

Builder datumBuilder(BuilderOptions options) =>
    SharedPartBuilder([DatumGenerator()], 'datum');
