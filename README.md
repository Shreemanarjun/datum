<p align="center">
  <img src="https://zmozkivkhopoeutpnnum.supabase.co/storage/v1/object/public/images/datum_banner.svg" alt="Datum Banner">
</p>

# Datum Ecosystem

Monorepo for the Datum ecosystem — offline-first data synchronization for
Dart and Flutter. **Your backend, your database, one type-safe sync engine.**

**[📚 Documentation → datum.shreeman.dev](https://datum.shreeman.dev/)**

## Packages

| Package | Description |
|---|---|
| [`datum`](./packages/datum) | The sync engine: offline-first CRUD, conflict resolution, CRDTs, schema migrations, incremental sync ([pub.dev](https://pub.dev/packages/datum)) |
| [`datum_sqlite`](./packages/datum_sqlite) | SQLite local adapter — real tables, SQL query pushdown, transactional DDL migrations |
| [`datum_hive`](./packages/datum_hive) | Hive CE local adapter for Flutter |
| [`datum_test`](./packages/datum_test) | Adapter/sync-stack conformance kit, local sync server, chaos & convergence fuzzing |
| [`datum_generator`](./packages/datum_generator) | Code generation for entity boilerplate |
| [`datum_docs`](./packages/datum_docs) | The documentation website (Jaspr) — every snippet is compile-verified |

## Getting started

Start with the [`datum` README](./packages/datum/README.md) or the
[Quick Start guide](https://datum.shreeman.dev/getting_started/quick_start).
A full example app — including an on-simulator integration + benchmark
suite — lives in [`packages/datum/example`](./packages/datum/example).

## Contributing

Please see [CONTRIBUTING.md](./packages/datum/CONTRIBUTING.md) for how to
contribute to the Datum ecosystem.
