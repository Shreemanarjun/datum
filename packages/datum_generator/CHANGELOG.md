## Unreleased

- `@DatumField(diff: false)` keeps a serialized field out of the generated
  `diff` (it never triggers an update on its own); `diff: true` forces a
  bookkeeping field in. Default rule unchanged otherwise.


- **Fix:** generated `datumDiff` ignored `isDeleted`, so pushing
  `copyWith(isDeleted: true/false)` (soft delete, undo, restore) produced a
  null diff and the manager skipped the save. `isDeleted` is now diffed.


- **Behavior change:** remote-target and diff `DateTime` values serialize as
  UTC (`toUtc().toIso8601String()`). A bare local time was stored by Postgres
  as UTC, shifting every timestamp by the device's offset and breaking
  last-write-wins across time zones.
- Generator split into cohesive files (`field_info`, `serialization`,
  `members`, `query_builder`); every function at cognitive complexity <= 15.
  Output is otherwise byte-for-byte identical.

## 1.1.0

- **Mixin generation is now the default**: `generateMixin` defaults to `true`, so generated code produces a `_$<Entity>DatumMixin` you mix into your entity instead of requiring manual method wiring. Set `generateMixin: false` to opt out.
- Added `strictNullChecks` option to `@DatumEntityAnnotation` for stricter generated `fromMap` handling of missing/null values.
- Fixed: generated `copyWith`/constructor calls now only include fields that are actual constructor parameters, so computed/getter-backed fields no longer break generation (#26).
- Fixed: `fromMap` now round-trips snake_case timestamp keys (`created_at`/`modified_at`) with camelCase fallback, matching `toDatumMap(target: MapTarget.remote)` output (#28).
- Renamed generated equality helper to `isEqual` to avoid clashing with user-defined `operator ==` overrides.

## 1.0.1

- Refactored: Migrated from string-based type checking to `TypeChecker` for robust type handling.
- Added: `DatumConverter` support for custom field serialization/deserialization.
- Updated: `DatumField` annotation now accepts a `converter` parameter.
- Fixed: Improved handling of `Color`, `Offset`, `Duration`, `DateTime`, `Uri`, `BigInt` types.
- Enhanced `@DatumIgnore` annotation with optional flags:
  - `copyWith`: exclude from copyWith generation
  - `equality`: exclude from equality generation
  - `fromMap`: exclude from deserialization
  - `toMap`: exclude from serialization
- Updated: `ManyToMany` now supports passing `Type` for pivot entity instead of instance in generated code.


## 1.0.0

- Initial version.
