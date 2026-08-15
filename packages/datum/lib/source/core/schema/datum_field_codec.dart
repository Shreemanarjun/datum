/// Bidirectional converters between Dart field values and their persisted
/// (map / wire) representation, used by [DatumFieldSpec] — the no-codegen
/// type-safety layer.
///
/// The built-in conversions mirror `datum_generator`'s table (DateTime as
/// ISO-8601 or epoch-milliseconds, `Duration` as microseconds, enums by
/// `.name`, `Uri`/`BigInt` as strings) so schema-described and generated
/// entities stay wire-compatible.
library;

/// Converts between a Dart value of type [V] and its persisted form.
abstract class DatumFieldCodec<V> {
  const DatumFieldCodec();

  /// Encodes [value] into a JSON/map-friendly representation.
  Object? encode(V value);

  /// Decodes a raw persisted value back into a [V].
  ///
  /// Implementations throw [FormatException] (or [ArgumentError]) on
  /// malformed input; [DatumFieldSpec.decode] wraps those into a
  /// `SchemaReadException` carrying the field name.
  V decode(Object? raw);

  /// Infers a codec for common types: `int`, `double`, `num`, `bool`,
  /// `String`, `DateTime` and their nullable variants.
  ///
  /// `int`/`double` decode leniently from any [num]; `DateTime` decodes from
  /// a `DateTime`, an epoch-milliseconds [int], or an ISO-8601 [String]
  /// (bridging stores that persist either form) and encodes as ISO-8601.
  /// Throws [ArgumentError] for any other [V] — pass an explicit `codec:`
  /// (e.g. [enumByName], [jsonObject]) for those.
  static DatumFieldCodec<V> infer<V>() {
    final inferred = _tryInfer<V>();
    if (inferred == null) {
      throw ArgumentError(
        'No built-in codec for $V. Pass an explicit codec: '
        '(DatumFieldCodec.enumByName / jsonObject / a custom DatumFieldCodec).',
      );
    }
    return inferred;
  }

  static DatumFieldCodec<V>? _tryInfer<V>() {
    if (V == int) return const _IntCodec() as DatumFieldCodec<V>;
    if (V == _typeOf<int?>()) return const _IntCodec().nullable as DatumFieldCodec<V>;
    if (V == double) return const _DoubleCodec() as DatumFieldCodec<V>;
    if (V == _typeOf<double?>()) return const _DoubleCodec().nullable as DatumFieldCodec<V>;
    if (V == num) return const _NumCodec() as DatumFieldCodec<V>;
    if (V == _typeOf<num?>()) return const _NumCodec().nullable as DatumFieldCodec<V>;
    if (V == bool) return const _BoolCodec() as DatumFieldCodec<V>;
    if (V == _typeOf<bool?>()) return const _BoolCodec().nullable as DatumFieldCodec<V>;
    if (V == String) return const _StringCodec() as DatumFieldCodec<V>;
    if (V == _typeOf<String?>()) return const _StringCodec().nullable as DatumFieldCodec<V>;
    if (V == DateTime) return dateTimeIso as DatumFieldCodec<V>;
    if (V == _typeOf<DateTime?>()) return dateTimeIso.nullable as DatumFieldCodec<V>;
    return null;
  }

  /// ISO-8601 strings on encode; lenient decode (DateTime, epoch-ms int,
  /// ISO-8601 string).
  static const DatumFieldCodec<DateTime> dateTimeIso = _DateTimeCodec(iso: true);

  /// Epoch milliseconds on encode; same lenient decode as [dateTimeIso].
  static const DatumFieldCodec<DateTime> dateTimeEpochMillis = _DateTimeCodec(iso: false);

  /// [Duration] as microseconds.
  static const DatumFieldCodec<Duration> durationMicros = _DurationCodec();

  /// [Uri] as its string form.
  static const DatumFieldCodec<Uri> uri = _UriCodec();

  /// [BigInt] as its decimal string form.
  static const DatumFieldCodec<BigInt> bigInt = _BigIntCodec();

  /// Enums persisted by `.name` (matching `datum_generator`).
  static DatumFieldCodec<T> enumByName<T extends Enum>(List<T> values) => _EnumCodec<T>(values);

  /// Nested objects persisted as JSON maps.
  static DatumFieldCodec<T> jsonObject<T>(
    T Function(Map<String, dynamic> json) fromJson,
    Map<String, dynamic> Function(T value) toJson,
  ) =>
      _JsonObjectCodec<T>(fromJson, toJson);

  /// A null-passthrough wrapper for nullable field types
  /// (`DatumFieldCodec.dateTimeIso.nullable` for a `DateTime?` field).
  DatumFieldCodec<V?> get nullable => _NullableCodec<V>(this);
}

Type _typeOf<T>() => T;

Never _fail(Type expected, Object? raw) => throw FormatException('expected $expected, got ${raw == null ? 'null' : '${raw.runtimeType} ($raw)'}');

class _NullableCodec<V> extends DatumFieldCodec<V?> {
  const _NullableCodec(this._inner);
  final DatumFieldCodec<V> _inner;

  @override
  Object? encode(V? value) => value == null ? null : _inner.encode(value);

  @override
  V? decode(Object? raw) => raw == null ? null : _inner.decode(raw);
}

class _IntCodec extends DatumFieldCodec<int> {
  const _IntCodec();
  @override
  Object? encode(int value) => value;
  @override
  int decode(Object? raw) => switch (raw) { int v => v, num v => v.toInt(), _ => _fail(int, raw) };
}

class _DoubleCodec extends DatumFieldCodec<double> {
  const _DoubleCodec();
  @override
  Object? encode(double value) => value;
  @override
  double decode(Object? raw) => switch (raw) { double v => v, num v => v.toDouble(), _ => _fail(double, raw) };
}

class _NumCodec extends DatumFieldCodec<num> {
  const _NumCodec();
  @override
  Object? encode(num value) => value;
  @override
  num decode(Object? raw) => switch (raw) { num v => v, _ => _fail(num, raw) };
}

class _BoolCodec extends DatumFieldCodec<bool> {
  const _BoolCodec();
  @override
  Object? encode(bool value) => value;
  @override
  bool decode(Object? raw) => switch (raw) { bool v => v, _ => _fail(bool, raw) };
}

class _StringCodec extends DatumFieldCodec<String> {
  const _StringCodec();
  @override
  Object? encode(String value) => value;
  @override
  String decode(Object? raw) => switch (raw) { String v => v, _ => _fail(String, raw) };
}

class _DateTimeCodec extends DatumFieldCodec<DateTime> {
  const _DateTimeCodec({required this.iso});
  final bool iso;

  @override
  Object? encode(DateTime value) => iso ? value.toIso8601String() : value.millisecondsSinceEpoch;

  @override
  DateTime decode(Object? raw) => switch (raw) {
        DateTime v => v,
        int v => DateTime.fromMillisecondsSinceEpoch(v),
        String v => DateTime.tryParse(v) ?? _fail(DateTime, raw),
        _ => _fail(DateTime, raw),
      };
}

class _DurationCodec extends DatumFieldCodec<Duration> {
  const _DurationCodec();
  @override
  Object? encode(Duration value) => value.inMicroseconds;
  @override
  Duration decode(Object? raw) => switch (raw) {
        Duration v => v,
        int v => Duration(microseconds: v),
        num v => Duration(microseconds: v.toInt()),
        _ => _fail(Duration, raw),
      };
}

class _UriCodec extends DatumFieldCodec<Uri> {
  const _UriCodec();
  @override
  Object? encode(Uri value) => value.toString();
  @override
  Uri decode(Object? raw) => switch (raw) { Uri v => v, String v => Uri.parse(v), _ => _fail(Uri, raw) };
}

class _BigIntCodec extends DatumFieldCodec<BigInt> {
  const _BigIntCodec();
  @override
  Object? encode(BigInt value) => value.toString();
  @override
  BigInt decode(Object? raw) => switch (raw) {
        BigInt v => v,
        int v => BigInt.from(v),
        String v => BigInt.tryParse(v) ?? _fail(BigInt, raw),
        _ => _fail(BigInt, raw),
      };
}

class _EnumCodec<T extends Enum> extends DatumFieldCodec<T> {
  const _EnumCodec(this.values);
  final List<T> values;

  @override
  Object? encode(T value) => value.name;

  @override
  T decode(Object? raw) => switch (raw) {
        T v => v,
        String v => values.asNameMap()[v] ?? _fail(T, raw),
        _ => _fail(T, raw),
      };
}

class _JsonObjectCodec<T> extends DatumFieldCodec<T> {
  const _JsonObjectCodec(this.fromJson, this.toJson);
  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T value) toJson;

  @override
  Object? encode(T value) => toJson(value);

  @override
  T decode(Object? raw) => switch (raw) {
        T v when v is! Map => v,
        Map v => fromJson(Map<String, dynamic>.from(v)),
        _ => _fail(T, raw),
      };
}
