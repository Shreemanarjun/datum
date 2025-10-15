# Datum

[![pub package](https://img.shields.io/pub/v/datum.svg)](https://pub.dev/packages/datum)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub stars](https://img.shields.io/github/stars/your_username/datum.svg?style=social&label=Star)](https://github.com/your_username/datum)

A powerful, offline-first data synchronization engine for Flutter and Dart, featuring relational data support, real-time queries, and intelligent conflict resolution.

Datum is the evolution of `synq_manager`, rebuilt to handle complex, connected data models with ease, while providing a seamless and reactive developer experience.

---

## ✨ Features

- **Offline-First by Design**: Full CRUD functionality without a network connection. Operations are queued and synced automatically when online.
- **Relational Data Support**: Natively define and sync one-to-many and many-to-many relationships between your data models.
- **Reactive Queries**: Build dynamic UIs that update in real-time with `watchAll`, `watchById`, and `watchQuery`.
- **Intelligent Conflict Resolution**: Built-in strategies like `LastWriteWins` and support for custom resolvers to handle data conflicts gracefully.
- **Pluggable Architecture**: Backend-agnostic. Use provided adapters for common backends (Firebase, Supabase, REST) or create your own.
- **Robust & Reliable**: Features schema migrations, multi-user support, and resilient sync with automatic retries.

---

## 🚀 Quick Start

### 1. Add Dependency

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  datum: ^1.0.0 # Use the latest version from pub.dev
```




### 🤝 Contributing
Contributions are welcome! Please feel free to open an issue to report a bug or a pull request for new features.

### 📄 License
Datum is licensed under the MIT License. See the LICENSE file for details.