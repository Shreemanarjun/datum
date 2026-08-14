import 'package:test/test.dart';

import 'helpers/build_helper.dart';

const String _customEntity = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';

part 'example.g.dart';

class PhoneMeta {
  final String number;
  const PhoneMeta(this.number);
  Map<String, dynamic> toJson() => {'number': number};
  static PhoneMeta fromJson(Map<String, dynamic> json) =>
      PhoneMeta(json['number'] as String);
}

@DatumSerializable(generateMixin: false)
class Contact extends DatumEntity {
  final String id;

  @DatumField(
    name: 'phone_meta',
    fromGenerator: 'PhoneMeta.fromJson(%DATA_PROPERTY% as Map<String, dynamic>)',
    toGenerator: '%DATA_PROPERTY%.toJson()',
  )
  final PhoneMeta phone;

  const Contact({required this.id, required this.phone});
}
''';

void main() {
  group('custom to/from generators', () {
    late String output;

    setUpAll(() async {
      final result = await generate(_customEntity);
      expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
      expect(result.output, isNotNull);
      output = result.output!;
    });

    test('toGenerator drives datumToMap serialization', () {
      expect(output, containsCode("'phone_meta': phone.toJson(),"));
    });

    test('toGenerator drives datumDiff serialization', () {
      expect(
        output,
        containsCode(
          "if (phone != old.phone) { changes['phone_meta'] = phone.toJson(); }",
        ),
      );
    });

    test('fromGenerator drives fromMap deserialization with fallback access', () {
      expect(
        output,
        containsCode(
          "phone: PhoneMeta.fromJson((map['phone_meta'] ?? map['phone']) as Map<String, dynamic>),",
        ),
      );
    });
  });
}
