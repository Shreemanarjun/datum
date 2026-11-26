# Local Supabase for the example app

The schema lives in [`migrations/`](migrations/). Paste it into the SQL editor
for a hosted project; a local stack applies it automatically.

## Run locally without Docker

The Supabase CLI's native runtime runs Postgres, Auth, PostgREST, Realtime and
Studio as plain processes. It needs macOS 14+ on Apple silicon, or Linux. It
is alpha and enabled through `"experimental": { "stack": true }` in
[`config.jsonc`](config.jsonc).

```sh
brew install supabase/tap/supabase
cd packages/datum/example
supabase start --runtime native --eager   # first run downloads ~services once
supabase status --env                      # API_URL, PUBLISHABLE_KEY, STUDIO_URL
supabase db reset                          # re-apply migrations
supabase stop
```

With Docker running, plain `supabase start` uses containers instead.

## Live sync journey test

[`test/live/supabase_local_sync_test.dart`](../test/live/supabase_local_sync_test.dart)
drives the real `SupabaseRemoteAdapter` with two devices on one account. It
covers push, pull, realtime fan-out, soft deletes, offline concurrent edits,
offline replay and an expired session. It prints a timing table and is
skipped unless `SUPABASE_URL` is defined.

```sh
flutter test test/live \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<PUBLISHABLE_KEY>
```

Run the app the same way: `flutter run --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`.

Typical timings on an M-series Mac, native stack:

| Step | ms |
|---|---:|
| Push 50 new tasks | ~80 |
| First pull of 50 on a second device | ~26 |
| Realtime arrival of an edit on the other device | ~110–250 |
| Idle sync (nothing changed) | 3 |
| Offline concurrent edits, three syncs to converge | ~50 |
| Replay 10 offline writes | ~19 |

## What the live run found (fixed)

- **Timestamps shifted by the UTC offset.** Entities sent local `DateTime`s
  without an offset, and Postgres stored them as UTC. Generated code and
  `Task` now serialize remote timestamps as UTC.
- **Every pulled row was a "conflict".** The detector and last-write-wins
  compared `modifiedAt` with `==`, which is false for the same instant in two
  time zones. They now compare instants (`isAtSameMomentAs`). As a result,
  concurrent offline edits now converge on the later write.
- **Double realtime subscription.** `initialize()` and the first change-stream
  listener each opened a channel on the same topic. The second one closed the
  first, which set off a spurious retry and a full resync on every start.
  Subscribing is now idempotent, and late events from a replaced channel are
  ignored.
- **Adapter state shared across clients.** State was keyed by table only, so
  two accounts or devices on one table shared a channel and auth flag. It is
  now keyed by table and client, and dropped on dispose so a later adapter
  never inherits closed controllers.

## Further improvements (not done)

- An expired session currently parks the write. The adapter should map
  PostgREST `42501` and `401` errors to an auth error that pauses sync until
  the user signs in again, instead of needing `retryParkedOperations`.
- The adapter isn't `DeltaSyncCapable`, so every sync pulls the whole table.
  Add a `readSince` filtered on a server-maintained `updated_at` column (a
  trigger), as the `DeltaSyncCapable` docs recommend.
- Entity ids are global primary keys. Another account's row with the same id
  is rejected by row-level security and the operation parks. Keep ids as UUIDs.
