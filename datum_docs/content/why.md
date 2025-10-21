
<Image src="/images/datum.png" alt="Sample Image" width="200" height="200" />


Datum isn't just another local database; it's a complete data synchronization framework. While databases like ObjectBox or Hive are excellent at storing data locally and are very fast, Datum's primary goal is to solve the much harder problem of keeping that local data effortlessly in sync with a remote backend, all while providing a seamless offline-first experience.

You choose Datum when your application's data needs to live on both the device and a server, and you want to stop writing complex, error-prone boilerplate code for syncing, conflict resolution, and real-time updates.

## Key Differentiators: Why Choose Datum?

Here are the core strengths of Datum broken down.

### 1. Backend Agnosticism: The "Universal" Adapter Model

**The Problem:** Many solutions lock you into their specific backend. If you use ObjectBox Sync, you sync to an ObjectBox server. If you use Firestore's offline persistence, you're locked into Firestore.

**Datum's Solution:** Datum uses a brilliant **Adapter pattern**. You have a `LocalAdapter` (for Hive, Isar, etc.) and a `RemoteAdapter` (for Supabase, a custom REST API, etc.). Your application code only ever talks to the `DatumManager`. This means you can swap your entire backend or local database without changing your app's business logic.

<Image src="/images/datum_architecture.svg" alt="Datum Adapter Architecture" caption="Datum's adapter model decouples your app from the backend and local database." width="600" />

*   **Migrate your backend?** Just write a new `RemoteAdapter`.
*   **Switch local databases?** Just write a new `LocalAdapter`.

This makes your application incredibly flexible and future-proof.

### 2. Built-in "Smart" Synchronization & Conflict Resolution

**The Problem:** Writing sync logic manually is a nightmare. You have to track changes, handle network failures, manage retries, and resolve conflicts when the same data is changed in two places at once.

**Datum's Solution:** This is all handled automatically.

*   **Offline Queue:** All local changes (create, update, delete) are automatically added to a reliable queue and processed when a network connection is available.
*   **Conflict Resolution:** Datum detects conflicts and provides pre-built strategies (`LastWriteWins`, `LocalPriority`, `RemotePriority`). Most importantly, you can implement your own custom logic to resolve conflicts in a way that makes sense for your specific data.

### 3. A Single, Unified API for Everything

**The Problem:** Without a framework like Datum, you write code against two different APIs: one for your local database (e.g., `box.put()`) and another for your remote API (e.g., `dio.post()`).

**Datum's Solution:** You only interact with the `DatumManager`.

```dart
// This one line...
await Datum.manager<Task>().create(newTask);

// ...handles all of this for you:
// 1. Writes the new task to the local database (e.g., Hive) instantly.
// 2. Adds a "create" operation to the background sync queue.
// 3. When online, sends the new task to the remote backend (e.g., Supabase).
// 4. Handles any potential network errors or conflicts.
```

This dramatically simplifies your application code, making it cleaner, more readable, and less prone to bugs. The same unified API applies to reads, updates, deletes, and queries.

### 4. Designed for Real-time and Reactivity

Datum is built with streams at its core. The `watchAll()`, `watchById()`, and `watchQuery()` methods provide streams that automatically emit new data whenever it changes—whether from a local user action or a real-time push from the server. This makes building reactive UIs effortless.

## Summary Table

| Feature               | A Simple Local DB (e.g., Hive) | A DB with Sync (e.g., ObjectBox Sync) | Datum                                       |
| --------------------- | ------------------------------ | ------------------------------------- | ------------------------------------------- |
| **Primary Goal**      | Fast local storage             | Fast local storage + sync to its own backend | **Unify any local DB with any backend**|
| **Backend Agnostic**  | ❌ (N/A)                       | ❌ (Tied to its own sync server)      | ✅ **(Key Differentiator)**                  |
| **Conflict Resolution** | ❌ (You build it)              | ✅ (Often basic, less customizable)   | ✅ **(Advanced & Customizable)**           |
| **Offline Queue**     | ❌ (You build it)              | ✅                                    | ✅ (Built-in & Automatic)                    |
| **Unified API**       | ❌ (Separate local/remote logic) | ❌ (Still need to manage sync state)  | ✅ (Single API for all data ops)           |
| **Cost Model**        | ✅ (Free & Open Source)        | 💰 (Commercial Subscription)          | ✅ (Free & Open Source)                      |
| **Extensibility**     | ✅ (It's just a library)       | 🟡 (Limited)                          | ✅ (Middleware, Observers, Custom Resolvers) |

## The Elevator Pitch

> You use Datum because you want to build a robust, offline-first application without spending months building a complex and fragile sync engine. It gives you the power of a unified, real-time data layer while giving you the freedom to choose the best local database and backend for your specific needs, both today and in the future.