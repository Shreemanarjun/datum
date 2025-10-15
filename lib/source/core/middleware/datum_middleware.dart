import 'dart:async';

import 'package:datum/source/core/models/datum_entity.dart';

/// Middleware for intercepting and transforming data during CRUD operations.
///
/// Middleware components are executed in the order they are registered.
abstract class DatumMiddleware<T extends DatumEntity> {
  /// Transforms an entity before it is saved via a `create` or `update` operation.
  ///
  /// This can be used for validation, sanitization, or adding/modifying fields.
  FutureOr<T> transformBeforeSave(T item) => item;

  /// Transforms an entity after it has been fetched from a data source.
  ///
  /// This can be used to enrich the data, format fields, or perform other client-side transformations.
  FutureOr<T> transformAfterFetch(T item) => item;
}
