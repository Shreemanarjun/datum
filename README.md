# Datum

[![pub package](https://img.shields.io/pub/v/datum.svg)](https://pub.dev/packages/datum)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub stars](https://img.shields.io/github/stars/your_username/datum.svg?style=social&label=Star)](https://github.com/your_username/datum)

A powerful, offline-first data synchronization engine for Flutter and Dart, featuring relational data support, real-time queries, and intelligent conflict resolution.

Datum is the evolution of `synq_manager`, rebuilt to handle complex, connected data models with ease, while providing a seamless and reactive developer experience.

---

## ✨ Features

- **Offline-First by Design**: Your app remains fully functional, with complete CRUD (Create, Read, Update, Delete) capabilities, even without a network connection. All changes are automatically queued and synced intelligently when the connection is restored.

- **Relational Data Support**: Go beyond simple key-value stores. Natively define and sync one-to-many and many-to-many relationships between your data models, maintaining data integrity across your local and remote databases.

- **Reactive Queries**: Build dynamic, responsive UIs that reflect the current state of your data. Use `watchAll`, `watchById`, and `watchQuery` to get streams of data that automatically update your UI whenever the underlying data changes.

- **Intelligent Conflict Resolution**: Datum provides built-in conflict resolution strategies, such as `LastWriteWins`, `LocalPriority`, and `RemotePriority`. You can also create your own custom resolvers to handle complex data conflicts gracefully, ensuring data consistency.

- **Pluggable and Backend-Agnostic**: The architecture is designed to be backend-agnostic. Use pre-built adapters for popular backends like Firebase, Supabase, or your own REST API. If a pre-built adapter doesn't fit your needs, you can easily create your own.

- **Robust and Reliable**: Datum is built for resilience. It includes features like schema migrations to evolve your data models over time, multi-user support for collaborative applications, and a resilient sync mechanism with automatic retries to handle unreliable network conditions.

- **Real-time Sync**: Keep your data up-to-date across all devices. Datum can be configured for real-time synchronization, pushing changes to all connected clients as they happen.

- **Customizable Middleware**: Intercept and modify data before it's written to the local database or sent to the remote backend. This is useful for data validation, encryption, or adding metadata.

---

## 🚀 Quick Start

### 1. Add Dependency

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  datum: ^1.0.0 # Use the latest version from pub.dev
```

### 2. Define Your Models

Create your data models by extending `DatumEntity`.

```dart
class User extends DatumEntity {
  final String name;
  final String email;

  User({String? id, required this.name, required this.email}) : super(id: id);

  @override
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};

  factory User.fromJson(Map<String, dynamic> json) => User(id: json['id'], name: json['name'], email: json['email']);
}
```

### 3. Initialize Datum

Configure and initialize Datum with your local and remote adapters.

```dart
import 'package:datum/datum.dart';

Future<void> main() async {
  // Initialize Datum
  await Datum.initialize(
    localAdapter: LocalAdapter(), // Your implementation of LocalAdapter
    remoteAdapter: RemoteAdapter(), // Your implementation of RemoteAdapter
    conflictResolver: LastWriteWinsResolver(),
  );

  runApp(MyApp());
}
```

### 4. Perform CRUD Operations

Once initialized, you can use Datum to perform CRUD operations on your data.

```dart
// Get a repository for your model
final userRepository = Datum.repository<User>();

// Create a new user
final newUser = User(name: 'John Doe', email: 'john.doe@example.com');
await userRepository.create(newUser);

// Read a user by ID
final user = await userRepository.getById(newUser.id);

// Update a user
final updatedUser = User(id: user.id, name: 'Johnathan Doe', email: user.email);
await userRepository.update(updatedUser);

// Delete a user
await userRepository.delete(updatedUser.id);
```

### 5. Watch for Changes

Use the `watch` methods to get real-time updates on your data.

```dart
// Watch all users
userRepository.watchAll().listen((users) {
  // Update your UI with the list of users
});

// Watch a single user by ID
userRepository.watchById('user-id').listen((user) {
  // Update your UI with the user's data
});

// Watch a query
userRepository.watchQuery(
  DatumQuery<User>()..where('name', isEqualTo: 'John Doe')
).listen((users) {
  // Update your UI with the query results
});
```

---

## 🔧 Customization

### Custom Adapters

You can create your own adapters to connect to any backend. Simply implement the `LocalAdapter` and `RemoteAdapter` interfaces.

```dart
class MyLocalAdapter extends LocalAdapter {
  // Implement the required methods
}

class MyRemoteAdapter extends RemoteAdapter {
  // Implement the required methods
}
```

### Custom Conflict Resolvers

If the built-in conflict resolvers don't meet your needs, you can create your own by implementing the `ConflictResolver` interface.

```dart
class MyConflictResolver extends ConflictResolver {
  @override
  Future<Resolution> resolve<T extends DatumEntity>(ConflictContext<T> context) async {
    // Implement your conflict resolution logic
  }
}
```

---

### 🤝 Contributing

Contributions are welcome! Please feel free to open an issue to report a bug or a pull request for new features.

### 📄 License

Datum is licensed under the MIT License. See the LICENSE file for details.
