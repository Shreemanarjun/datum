/// Defines the type of a synchronization or data manipulation operation.
enum DatumOperationType {
  /// A new entity was created.
  create,

  /// An existing entity was updated.
  update,

  /// An entity was deleted.
  delete,
}
