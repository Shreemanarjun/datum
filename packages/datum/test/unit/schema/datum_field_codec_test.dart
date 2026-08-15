import 'package:datum/datum.dart';
import 'package:test/test.dart';

import 'schema_test_entity.dart';

void main() {
  group('DatumFieldCodec.infer', () {
    test('covers primitives and their nullable variants', () {
      expect(DatumFieldCodec.infer<int>().decode(3), 3);
      expect(DatumFieldCodec.infer<int?>().decode(null), isNull);
      expect(DatumFieldCodec.infer<double>().decode(1.5), 1.5);
      expect(DatumFieldCodec.infer<double?>().decode(2), 2.0);
      expect(DatumFieldCodec.infer<num>().decode(7), 7);
      expect(DatumFieldCodec.infer<num?>().decode(null), isNull);
      expect(DatumFieldCodec.infer<bool>().decode(true), isTrue);
      expect(DatumFieldCodec.infer<bool?>().decode(false), isFalse);
      expect(DatumFieldCodec.infer<String>().decode('x'), 'x');
      expect(DatumFieldCodec.infer<String?>().decode(null), isNull);
      expect(DatumFieldCodec.infer<DateTime>().decode('2026-01-01T00:00:00.000Z'), DateTime.utc(2026));
      expect(DatumFieldCodec.infer<DateTime?>().decode(null), isNull);
    });

    test('int and double decode leniently from num', () {
      expect(DatumFieldCodec.infer<int>().decode(3.0), 3);
      expect(DatumFieldCodec.infer<double>().decode(3), 3.0);
    });

    test('rejects unsupported types with guidance', () {
      expect(
        () => DatumFieldCodec.infer<Duration>(),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('No built-in codec'))),
      );
    });

    test('encode passes primitives through', () {
      expect(DatumFieldCodec.infer<int>().encode(3), 3);
      expect(DatumFieldCodec.infer<num>().encode(2.5), 2.5);
      expect(DatumFieldCodec.infer<bool>().encode(true), true);
      expect(DatumFieldCodec.infer<String>().encode('x'), 'x');
      expect(DatumFieldCodec.infer<double>().encode(1.5), 1.5);
    });

    test('type mismatches throw FormatException', () {
      expect(() => DatumFieldCodec.infer<int>().decode('x'), throwsFormatException);
      expect(() => DatumFieldCodec.infer<double>().decode('x'), throwsFormatException);
      expect(() => DatumFieldCodec.infer<num>().decode('x'), throwsFormatException);
      expect(() => DatumFieldCodec.infer<bool>().decode(1), throwsFormatException);
      expect(() => DatumFieldCodec.infer<String>().decode(1), throwsFormatException);
    });
  });

  group('DateTime codecs', () {
    final instant = DateTime.utc(2026, 3, 14, 1, 59);

    test('ISO round-trip and lenient decode', () {
      const codec = DatumFieldCodec.dateTimeIso;
      expect(codec.decode(codec.encode(instant)), instant);
      expect(codec.decode(instant.millisecondsSinceEpoch), instant.toLocal());
      expect(codec.decode(instant), same(instant));
      expect(() => codec.decode('not-a-date'), throwsFormatException);
      expect(() => codec.decode(true), throwsFormatException);
    });

    test('epoch-ms round-trip', () {
      const codec = DatumFieldCodec.dateTimeEpochMillis;
      expect(codec.encode(instant), instant.millisecondsSinceEpoch);
      expect(codec.decode(codec.encode(instant)), instant.toLocal());
    });
  });

  group('special codecs', () {
    test('durationMicros round-trips and accepts num/Duration', () {
      const codec = DatumFieldCodec.durationMicros;
      const d = Duration(seconds: 90);
      expect(codec.encode(d), d.inMicroseconds);
      expect(codec.decode(d.inMicroseconds), d);
      expect(codec.decode(d.inMicroseconds.toDouble()), d);
      expect(codec.decode(d), d);
      expect(() => codec.decode('x'), throwsFormatException);
    });

    test('uri round-trips and accepts Uri', () {
      const codec = DatumFieldCodec.uri;
      final u = Uri.parse('https://example.com/a?b=1');
      expect(codec.encode(u), u.toString());
      expect(codec.decode(u.toString()), u);
      expect(codec.decode(u), u);
      expect(() => codec.decode(3), throwsFormatException);
    });

    test('bigInt round-trips and accepts int/BigInt', () {
      const codec = DatumFieldCodec.bigInt;
      final big = BigInt.parse('123456789012345678901234567890');
      expect(codec.decode(codec.encode(big)), big);
      expect(codec.decode(42), BigInt.from(42));
      expect(codec.decode(big), big);
      expect(() => codec.decode('nope'), throwsFormatException);
      expect(() => codec.decode(true), throwsFormatException);
    });

    test('enumByName round-trips, accepts enum values, rejects unknowns', () {
      final codec = DatumFieldCodec.enumByName(SchemaPriority.values);
      expect(codec.encode(SchemaPriority.high), 'high');
      expect(codec.decode('low'), SchemaPriority.low);
      expect(codec.decode(SchemaPriority.high), SchemaPriority.high);
      expect(() => codec.decode('urgent'), throwsFormatException);
      expect(() => codec.decode(1), throwsFormatException);
    });

    test('jsonObject round-trips nested maps', () {
      final codec = DatumFieldCodec.jsonObject<SchemaPriority>(
        (json) => SchemaPriority.values.byName(json['p'] as String),
        (value) => {'p': value.name},
      );
      expect(codec.encode(SchemaPriority.high), {'p': 'high'});
      expect(codec.decode({'p': 'low'}), SchemaPriority.low);
      expect(codec.decode(SchemaPriority.low), SchemaPriority.low);
      expect(() => codec.decode(3), throwsFormatException);
    });

    test('nullable wraps any codec with null passthrough', () {
      final codec = DatumFieldCodec.durationMicros.nullable;
      expect(codec.encode(null), isNull);
      expect(codec.decode(null), isNull);
      expect(codec.decode(1000), const Duration(milliseconds: 1));
      expect(codec.encode(const Duration(milliseconds: 1)), 1000);
    });
  });
}
