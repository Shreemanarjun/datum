## Cost and Licensing

Datum is **free and open-source**, released under the generous **MIT License**. You can use it in any personal or commercial project without any fees.

While the `datum` library itself is free, it is designed to connect to a backend service of your choice. Please be aware that you are responsible for any costs associated with the backend infrastructure you choose to use (e.g., Supabase, Firebase, self-hosted server costs).

If you find Datum useful and wish to support its continued development, you can do so through the [funding link](https://buymeacoffee.com/shreemanarjun) in the `pubspec.yaml`.

## Architectural Considerations

Using Datum requires adhering to a specific data model structure, which is a necessary trade-off for the powerful synchronization features it provides.

### 1. Mandatory Entity Fields

Any data model you want to synchronize with Datum must extend `DatumEntity`. This requires you to add several fields to your table schema:

-   `id (String)`: A unique identifier for each record.
-   `userId (String)`: The ID of the user who owns the data.
-   `createdAt (DateTime)`: Timestamp of when the record was created.
-   `modifiedAt (DateTime)`: Timestamp of the last modification, crucial for conflict resolution.
-   `version (int)`: A number that increments with each change, used for optimistic locking.
-   `isDeleted (bool)`: A flag for soft-deleting records, so deletions can be synced.

These fields are essential for tracking changes, resolving conflicts, and ensuring data integrity across devices.

### 2. Metadata Storage

Datum also requires a separate table or collection in your database (both local and remote) to store synchronization metadata, as represented by the `DatumSyncMetadata` class. This table stores information like:

-   `lastSyncTime`: To know which changes to fetch from the server.
-   `dataHash`: For quick data integrity checks.
-   `entityCounts`: To track the number of records for each entity type.

This metadata is vital for the sync engine to operate efficiently and reliably.

### 3. Development and Maintenance Overhead

While Datum significantly reduces the boilerplate for synchronization, there is still a learning curve and ongoing development effort involved:

*   **Understanding Core Concepts**: Users need to grasp Datum's core concepts like `DatumEntity`, `Adapter` (Local and Remote), `DatumManager`, and conflict resolution strategies.
*   **Adapter Implementation**: You will need to implement custom `LocalAdapter` and `RemoteAdapter` classes to integrate Datum with your chosen local database and backend API. This involves writing code to map your entities to and from your database/API formats.
*   **Conflict Resolution Logic**: While Datum provides built-in strategies, complex applications may require custom conflict resolvers, which adds to development complexity.
*   **Schema Migrations**: As your data models evolve, you will need to manage schema migrations for both your local and remote databases, ensuring compatibility with Datum's requirements.

### 4. Performance and Storage Considerations

The architectural choices made for Datum, while enabling powerful features, can introduce some overhead:

*   **Storage Footprint**: The mandatory `DatumEntity` fields (`modifiedAt`, `version`, `isDeleted`) and the `DatumSyncMetadata` table add to the storage footprint of your application's data, both on the device and on the backend.
*   **Performance Impact**: While optimized, the additional logic for change tracking, conflict detection, and metadata management can introduce a slight performance overhead compared to direct, un-synced database operations. This is generally negligible for most applications but should be considered for extremely high-throughput or resource-constrained environments.