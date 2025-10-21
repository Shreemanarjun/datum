---
title: Datum
---


<Image src="/images/datum.png" alt="Datum Logo" width="300" height="300" />



## Offline-First Data Synchronization for Dart & Flutter

Datum is a powerful and easy-to-use framework for building offline-first applications with Dart and Flutter. It provides a seamless way to synchronize data between your local database and a remote server, ensuring your app remains functional even without a network connection.

## Key Features

*   **Offline-First:** Your app works seamlessly, whether online or offline.
*   **Automatic Synchronization:** Data is automatically synchronized between the local and remote databases.
*   **Conflict Resolution:** Built-in conflict resolution strategies to handle data conflicts.
*   **Support for Dart & Flutter:** Use Datum in your Dart backend and Flutter applications.

## Who is Datum For?

You should consider Datum if you are building an application that:

- **Needs to work offline:** From field service apps to content-heavy media apps, Datum ensures a seamless user experience, regardless of network connectivity.
- **Requires real-time collaboration:** If you're building a tool where multiple users edit the same data, Datum's conflict resolution and real-time sync are essential.
- **Has a complex data model:** For apps with relational data that needs to be available on the device.
- **You want to avoid backend lock-in:** Datum's adapter-based architecture gives you the freedom to choose—and change—your database and backend services without rewriting your app's business logic.

## Core Concepts

Datum is built around a few key ideas:

- **`DatumEntity`**: The base class for your data models. It requires a unique `id`, `userId`, and other metadata for synchronization.
- **`Adapter`**: The bridge between Datum and your data sources.
    - **`LocalAdapter`**: Manages data persistence on the device (e.g., Hive, Isar, SQLite).
    - **`RemoteAdapter`**: Communicates with your backend (e.g., a REST API, Supabase, Firestore).
- **`Datum`**: The main entry point for interacting with your data. It provides a unified API for CRUD operations, queries, and synchronization with finding Managers.
- **Offline-First:** All data operations are performed on the local database first, ensuring a snappy UI. Datum then automatically syncs changes to the remote backend when a connection is available.

---

## Why Datum?

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

**Datum's Solution:** You only interact with the `Datum`.

```dart
// In your controller or business logic layer:

final _taskManager = Datum.manager<Task>();

  // CREATE: Writes locally and queues a sync to your backend.
  Future<void> createTask(String title) async {
    await _taskManager.create(Task(title: title));
  }

  // UPDATE: Updates locally and queues a sync.
  Future<void> updateTask(Task task) async {
    await _taskManager.update(task);
  }

  // DELETE: Deletes locally and queues a sync.
  Future<void> deleteTask(String taskId) async {
    await _taskManager.delete(taskId);
  }
```

This dramatically simplifies your application code, making it cleaner, more readable, and less prone to bugs. The same unified API applies to reads, updates, deletes, and queries.

### 4. Designed for Real-time and Reactivity

Datum is built with streams at its core. The `watchAll()`, `watchById()`, and `watchQuery()` methods provide streams that automatically emit new data whenever it changes—whether from a local user action or a real-time push from the server. This makes building reactive UIs effortless.

## Comaprision Table

| **Feature**               | **Simple Local DB (e.g., Hive)** | **DB with Sync (e.g., ObjectBox)** | **Datum**                                       |
| :------------------------ | :------------------------------: | :--------------------------------: | :------------------------------------------: |
| **Primary Goal**          | Fast local storage               | Local storage + proprietary sync   | **Unify any local DB with any backend**      |
| **Backend Agnostic**      | ❌ (N/A)                         | ❌ (Proprietary backend)           | ✅ **(Key Differentiator)**                  |
| **Conflict Resolution**   | ❌ (Manual)                      | ✅ (Basic/Limited)                 | ✅ **(Advanced & Customizable)**             |
| **Offline Queue**         | ❌ (Manual)                      | ✅                                 | ✅ (Built-in & Automatic)                    |
| **Unified API**           | ❌ (Separate APIs)               | ❌ (Sync state management)         | ✅ (Single API for all data ops)             |
| **Cost Model**            | ✅ (Free & Open Source)          | 💰 (Commercial Subscription)       | ✅ (Free & OpenSource)                       |




## The Elevator Pitch

> You use Datum because you want to build a robust, offline-first application without spending months building a complex and fragile sync engine. It gives you the power of a unified, real-time data layer while giving you the freedom to choose the best local database and backend for your specific needs, both today and in the future.