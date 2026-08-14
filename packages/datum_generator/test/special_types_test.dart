import 'package:test/test.dart';

import 'helpers/build_helper.dart';

const String _entity = '''
import 'package:datum/datum.dart';
import 'package:datum_generator/annotations.dart';
import 'package:ui_stub/ui_stub.dart';

part 'example.g.dart';

enum Priority { low, medium, high }

@DatumSerializable(generateMixin: false)
class Advanced extends DatumEntity {
  final Color color;
  final List<Offset> points;
  final Priority priority;
  final Priority? maybePriority;
  final Duration elapsed;
  final Duration? maybeElapsed;
  final Uri website;
  final Uri? maybeWebsite;
  final BigInt bigNumber;
  final BigInt? maybeBigNumber;
  final double score;
  final double? maybeScore;
  final int? maybeCount;
  final String? maybeName;
  final bool? maybeFlag;
  final DateTime? maybeWhen;
  final List<String> tags;
  final Map<String, int> counts;
  final Set<int> ids;

  const Advanced({
    required this.color,
    required this.points,
    required this.priority,
    this.maybePriority,
    required this.elapsed,
    this.maybeElapsed,
    required this.website,
    this.maybeWebsite,
    required this.bigNumber,
    this.maybeBigNumber,
    required this.score,
    this.maybeScore,
    this.maybeCount,
    this.maybeName,
    this.maybeFlag,
    this.maybeWhen,
    required this.tags,
    required this.counts,
    required this.ids,
  });
}
''';

void main() {
  late String output;

  setUpAll(() async {
    final result = await generate(_entity);
    expect(result.succeeded, isTrue, reason: result.errors.join('\n'));
    expect(result.output, isNotNull);
    output = result.output!;
  });

  group('datumToMap special types', () {
    test('Color serializes via toARGB32', () {
      expect(output, containsCode("'color': color.toARGB32(),"));
    });

    test('List<Offset> serializes as x/y maps', () {
      expect(
        output,
        containsCode(
          "'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),",
        ),
      );
    });

    test('enum serializes by name (non-null and nullable)', () {
      expect(output, containsCode("'priority': priority.name,"));
      expect(output, containsCode("'maybe_priority': maybePriority?.name,"));
    });

    test('Duration serializes as microseconds', () {
      expect(output, containsCode("'elapsed': elapsed.inMicroseconds,"));
      expect(
        output,
        containsCode("'maybe_elapsed': maybeElapsed?.inMicroseconds,"),
      );
    });

    test('Uri serializes via toString', () {
      expect(output, containsCode("'website': website.toString(),"));
      expect(
        output,
        containsCode("'maybe_website': maybeWebsite?.toString(),"),
      );
    });

    test('BigInt serializes via toString', () {
      expect(output, containsCode("'big_number': bigNumber.toString(),"));
      expect(
        output,
        containsCode("'maybe_big_number': maybeBigNumber?.toString(),"),
      );
    });

    test('nullable DateTime serializes with null-aware target switch', () {
      expect(
        output,
        containsCode(
          "'maybe_when': target == MapTarget.remote ? maybeWhen?.toIso8601String() : maybeWhen?.millisecondsSinceEpoch,",
        ),
      );
    });

    test('collections pass through unchanged', () {
      expect(output, containsCode("'tags': tags,"));
      expect(output, containsCode("'counts': counts,"));
      expect(output, containsCode("'ids': ids,"));
    });
  });

  group('datumDiff special types', () {
    test('emits deep equality helper for collection fields', () {
      expect(output, containsCode('bool isEqual(dynamic a, dynamic b)'));
      expect(output, containsCode('if (a is Map && b is Map)'));
      expect(output, containsCode('if (a is List && b is List)'));
      expect(output, containsCode('if (a is Set && b is Set)'));
    });

    test('collections compare with isEqual, scalars with !=', () {
      expect(output, containsCode('if (!isEqual(tags, old.tags))'));
      expect(output, containsCode('if (!isEqual(counts, old.counts))'));
      expect(output, containsCode('if (!isEqual(ids, old.ids))'));
      expect(output, containsCode('if (score != old.score)'));
    });

    test('special types convert in diff output', () {
      expect(output, containsCode("changes['color'] = color.toARGB32();"));
      expect(
        output,
        containsCode(
          "changes['points'] = points.map((p) => {'x': p.dx, 'y': p.dy}).toList();",
        ),
      );
      expect(output, containsCode("changes['priority'] = priority.name;"));
      expect(
        output,
        containsCode("changes['maybe_priority'] = maybePriority?.name;"),
      );
      expect(
        output,
        containsCode("changes['elapsed'] = elapsed.inMicroseconds;"),
      );
      expect(output, containsCode("changes['website'] = website.toString();"));
      expect(
        output,
        containsCode("changes['big_number'] = bigNumber.toString();"),
      );
      expect(
        output,
        containsCode("changes['maybe_when'] = maybeWhen?.toIso8601String();"),
      );
    });

    test('no modified_at stamp when entity has no modifiedAt field', () {
      expect(output, isNot(containsCode("changes['modified_at']")));
    });
  });

  group('fromMap special types', () {
    test('Color deserializes from int with default', () {
      expect(
        output,
        containsCode(
          "color: Color((map['color'] ?? map['color'] ?? 0xFF000000) as int),",
        ),
      );
    });

    test('List<Offset> deserializes from x/y maps', () {
      expect(
        output,
        containsCode(
          "points: ((map['points'] ?? map['points'] ?? []) as List<dynamic>).map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble())).toList(),",
        ),
      );
    });

    test('enum deserializes via values.byName', () {
      expect(
        output,
        containsCode(
          "priority: Priority.values.byName((map['priority'] ?? map['priority']) as String),",
        ),
      );
      expect(
        output,
        containsCode(
          "maybePriority: map['maybe_priority'] != null || map['maybePriority'] != null ? Priority.values.byName((map['maybe_priority'] ?? map['maybePriority']) as String) : null,",
        ),
      );
    });

    test('Duration deserializes from microseconds', () {
      expect(
        output,
        containsCode(
          "elapsed: Duration(microseconds: (map['elapsed'] ?? map['elapsed'] ?? 0) as int),",
        ),
      );
      expect(
        output,
        containsCode(
          "maybeElapsed: map['maybe_elapsed'] != null || map['maybeElapsed'] != null ? Duration(microseconds: (map['maybe_elapsed'] ?? map['maybeElapsed']) as int) : null,",
        ),
      );
    });

    test('Uri deserializes via parse', () {
      expect(
        output,
        containsCode(
          "website: Uri.parse((map['website'] ?? map['website'] ?? '') as String),",
        ),
      );
      expect(
        output,
        containsCode(
          "maybeWebsite: map['maybe_website'] != null || map['maybeWebsite'] != null ? Uri.parse((map['maybe_website'] ?? map['maybeWebsite']) as String) : null,",
        ),
      );
    });

    test('BigInt deserializes via parse', () {
      expect(
        output,
        containsCode(
          "bigNumber: BigInt.parse((map['big_number'] ?? map['bigNumber'] ?? '0') as String),",
        ),
      );
      expect(
        output,
        containsCode(
          "maybeBigNumber: map['maybe_big_number'] != null || map['maybeBigNumber'] != null ? BigInt.parse((map['maybe_big_number'] ?? map['maybeBigNumber']) as String) : null,",
        ),
      );
    });

    test('double handles int coercion (non-strict)', () {
      expect(
        output,
        containsCode(
          "score: (map['score'] ?? map['score'] ?? 0.0) is int ? (map['score'] ?? map['score'] ?? 0.0).toDouble() : (map['score'] ?? map['score'] ?? 0.0) as double,",
        ),
      );
      expect(
        output,
        containsCode(
          "maybeScore: (map['maybe_score'] ?? map['maybeScore']) is int ? (map['maybe_score'] ?? map['maybeScore']).toDouble() : (map['maybe_score'] ?? map['maybeScore']) as double?,",
        ),
      );
    });

    test('nullable primitives cast without defaults', () {
      expect(
        output,
        containsCode(
          "maybeCount: (map['maybe_count'] ?? map['maybeCount']) as int?,",
        ),
      );
      expect(
        output,
        containsCode(
          "maybeName: (map['maybe_name'] ?? map['maybeName']) as String?,",
        ),
      );
      expect(
        output,
        containsCode(
          "maybeFlag: (map['maybe_flag'] ?? map['maybeFlag']) as bool?,",
        ),
      );
    });

    test('nullable DateTime uses parse helper conditionally', () {
      expect(
        output,
        containsCode(
          "maybeWhen: (map['maybe_when'] ?? map['maybeWhen']) != null ? _advancedParseDate(map['maybe_when'] ?? map['maybeWhen']) : null,",
        ),
      );
    });

    test('unknown types fall back to raw map access', () {
      expect(output, containsCode("tags: map['tags'] ?? map['tags'],"));
      expect(output, containsCode("counts: map['counts'] ?? map['counts'],"));
      expect(output, containsCode("ids: map['ids'] ?? map['ids'],"));
    });
  });

  group('equality with list fields', () {
    test('emits list equals helper and uses it', () {
      expect(
        output,
        containsCode('bool _advancedListEquals<T>(List<T>? a, List<T>? b)'),
      );
      expect(output, containsCode('_advancedListEquals(other.points, points)'));
      expect(output, containsCode('_advancedListEquals(other.tags, tags)'));
      // Non-list fields use plain equality.
      expect(output, containsCode('other.color == color'));
    });
  });

  group('query builder special types', () {
    test('Color is numeric with toARGB32 conversion', () {
      expect(output, containsCode('DatumQueryBuilder<Advanced> whereColor({'));
      expect(
        output,
        containsCode("where('color', isEqualTo: isEqualTo.toARGB32());"),
      );
      expect(
        output,
        containsCode(
          "where('color', between: between.map((e) => e.toARGB32()).toList());",
        ),
      );
    });

    test('Duration is numeric with inMicroseconds conversion', () {
      expect(
        output,
        containsCode("where('elapsed', isEqualTo: isEqualTo.inMicroseconds);"),
      );
      expect(
        output,
        containsCode(
          "where('elapsed', isLessThan: isLessThan.inMicroseconds);",
        ),
      );
    });

    test('Uri and BigInt are strings with toString conversion', () {
      expect(
        output,
        containsCode("where('website', isEqualTo: isEqualTo.toString());"),
      );
      expect(
        output,
        containsCode("where('big_number', isEqualTo: isEqualTo.toString());"),
      );
      // String-only text operators exist for Uri.
      expect(
        output,
        containsCode(
          "where('website', containsIgnoreCase: containsIgnoreCase.toString());",
        ),
      );
    });

    test('enum is string-like with .name conversion but no text operators', () {
      expect(
        output,
        containsCode('DatumQueryBuilder<Advanced> wherePriority({'),
      );
      expect(
        output,
        containsCode("where('priority', isEqualTo: isEqualTo.name);"),
      );
      expect(
        output,
        containsCode(
          "where('priority', isIn: isIn.map((e) => e.name).toList());",
        ),
      );
      expect(output, isNot(containsCode("where('priority', contains:")));
      expect(output, containsCode('orderByPriority'));
    });

    test('collection fields get no query methods', () {
      expect(output, isNot(containsCode('whereTags')));
      expect(output, isNot(containsCode('whereCounts')));
      expect(output, isNot(containsCode('whereIds')));
      expect(output, isNot(containsCode('wherePoints')));
    });

    test('double is numeric without conversion', () {
      expect(output, containsCode('DatumQueryBuilder<Advanced> whereScore({'));
      expect(
        output,
        containsCode("where('score', isGreaterThan: isGreaterThan);"),
      );
    });
  });
}
