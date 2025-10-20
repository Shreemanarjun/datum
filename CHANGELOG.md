## 0.0.1

### Added
- **Metrics & Health System**:
  - Introduced `DatumMetrics`, an immutable snapshot of synchronization statistics.
  - Added `Datum.instance.metrics` stream to observe real-time metrics.
  - Added `Datum.instance.currentMetrics` getter for immediate access to the latest metrics.
  - Added `DatumHealth` and `DatumSyncHealth` for observing the operational status of the sync engine.
- **Relational Data Support**: Added `fetchRelated` and `watchRelated` to handle `BelongsTo`, `HasMany`, and `ManyToMany` relationships.
- **Improved API**: Refined the core API for better type safety and developer experience.
