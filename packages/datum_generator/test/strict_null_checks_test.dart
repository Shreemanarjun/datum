import 'package:test/test.dart';

import 'helpers/build_helper.dart';

const String _strictEntity = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

@DatumSerializable(strictNullChecks: true, generateMixin: false)
class Strict extends DatumEntity {
  final String name;
  final int age;
  final bool active;
  final double score;

  const Strict({
    required this.name,
    required this.age,
    required this.active,
    required this.score,
  });
}
''';

void main() {
  group('strictNullChecks: true', () {
    late String output;

    setUpAll(() async {
      final result = await generate(_strictEntity);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(result.output, isNotNull);
      output = result.output!;
    });

    test('String uses plain cast without default', () {
      expect(
        output,
        containsCode("name: (map['name'] ?? map['name']) as String,"),
      );
      expect(output, isNot(containsCode("?? '') as String")));
    });

    test('int uses plain cast without default', () {
      expect(output, containsCode("age: (map['age'] ?? map['age']) as int,"));
      expect(output, isNot(containsCode('?? 0) as int')));
    });

    test('bool uses plain cast without default', () {
      expect(
        output,
        containsCode("active: (map['active'] ?? map['active']) as bool,"),
      );
      expect(output, isNot(containsCode('?? false) as bool')));
    });

    test('double uses num cast without default', () {
      expect(
        output,
        containsCode(
          "score: ((map['score'] ?? map['score']) as num).toDouble(),",
        ),
      );
      expect(output, isNot(containsCode('?? 0.0)')));
    });
  });
}
