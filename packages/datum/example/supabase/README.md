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

## Sync improvements (done)

- **Expired session → pause, not park.** The adapter maps a missing/expired
  session and PostgREST `401`/`PGRST30x` to `AuthenticationException`; the
  manager pauses with the queue untouched and resumes by itself when
  `DatumConfig.authState` (Supabase `onAuthStateChange`) reports a session.
  Row-level-security rejections (`42501`) map to `AuthorizationException` and
  park. `authErrorPolicy: AuthErrorPolicy.park` restores the old behaviour.
- **Delta pulls.** Tables carry a trigger-maintained `updated_at`; the adapter
  is `DeltaSyncCapable` and pulls `updated_at > watermark - deltaSyncOverlap`
  instead of the whole table.
- **UUID ids.** Entity ids are client-generated UUIDs and the `id` columns are
  `UUID`, so ids can't collide across accounts.
- **Upload soon after writes.** `syncAfterWriteDelay: 300ms` sends a burst of
  local writes (paint strokes) in one debounced sync; other devices get them
  by realtime within ~1–2 s.
- **Theme syncs per account** through a hand-written (no codegen)
  `UserSettings` entity in `user_settings`.

## Multi-device run (1 iOS simulator + 2 Android emulators)

```sh
supabase start --runtime native --eager
adb -s <serial> reverse tcp:54321 tcp:54321      # per emulator
flutter run -d <ios-udid> --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<PUBLISHABLE_KEY>
flutter build apk --profile --dart-define=...   # then adb install -r on each
```

Debug/profile manifests allow cleartext HTTP for the local stack. Checked
live on all three at once: sign-in/sign-out routing, user switch (Bob's rows
never shown to Alice), task create → realtime on the other devices, paint
strokes from three devices converging, theme sync, and concurrent theme
changes converging on the later write.

Found and fixed during the run: Hive adapters hid entities whose maps use
`user_id` (all generated entities, i.e. the paint feature); the default
`diff` sent epoch-ms timestamps to Postgres; `Datum.instance.pushAndSync`
threw when `T` inferred as the base interface; the task "pending" badge
guessed from timestamps instead of reading the queue; no sign-out on phones.

Profile build, Android emulator, 20 strokes drawn while syncing: RSS
233 → 247 MB then flat (no growth on idle or navigation churn), CPU ~25–30%
while drawing, 0% idle. Emulator frame timing isn't representative; measure
jank on a device.

## Still open

- Stroke points are stored in device pixels, so a stroke from a wide screen
  overflows a narrow one. Store points normalized to the canvas size.
- `sync_metadata` is one row per user shared by every entity type; each
  manager overwrites the others' entry. It only costs extra syncs now, but a
  per-entity-type key would make the skip check exact.
- A parked op blocks later edits of its entity until retried; the app should
  surface parked ops (count + retry) instead of failing silently.
