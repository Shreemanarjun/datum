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

## Also fixed after the first run

- **Strokes scale with the screen.** Points are stored as fractions of the
  canvas width (one factor for both axes, so shapes keep their proportions);
  every device draws the same picture at its own size.
- **Sync metadata per entity table.** `sync_metadata` is keyed by
  `(user_id, entity_table)`, so the task, paint and settings managers no
  longer overwrite each other's hashes and counts.
- **Parked writes are visible.** A banner above the tab bar shows how many
  changes the server rejected, why (Postgres class 22/23 errors map to a
  readable `ValidationException`), and retries them. The task page says
  "Saved here, but not synced" instead of "Error creating task" when only
  the upload failed. Checked live with a temporary `CHECK` constraint: the
  write parked, the banner showed the reason, and Retry delivered it once
  the constraint was dropped.

## Example app changes from the engine audit

- **One place ties sync to the session.** Signing in used to start three or
  four forced full syncs from the login page and the tasks page. One handler
  in the initializer now resumes sync, starts auto-sync and syncs once;
  signing out pauses. App start no longer re-reads every table either (the
  default cold-start strategy runs a normal, incremental cycle).
- **Live numbers.** The dashboard shows real values from the engine (changes
  waiting to upload, item counts, local storage size) instead of fixed
  sample numbers, and a strip above the tab bar shows how long the last sync
  of each entity type took.
- **Undo and redo in the paint screen work on every device,** because they
  are derived from the synced strokes rather than from a list in memory.
- **The timing strip follows live updates.** It used to move only on the
  device that made an edit, because a change received over realtime runs no
  sync cycle. It now shows, newest first, `Task sync 36 ms ↑1` on the editing
  device and `Task live ↓1 · 7 ms to apply · 157 ms after the edit` on the
  others (checked both ways across the iOS simulator and both emulators).
- **Staying current without a restart.** A dropped realtime subscription is
  retried for as long as the user is signed in (it gave up after five
  attempts) and followed by an incremental pull; the app also pulls when it
  returns to the foreground. Pulls ask only for the signed-in user's rows.
- **Paintings.** The list counts strokes from the strokes themselves (the
  stored `stroke_count` column was never updated and is gone), and the
  canvas is a fixed 2:3 sheet, so a drawing made on a phone is whole on a
  tablet or an unfolded foldable.
- **The adapter guards its writes.** `SupabaseRemoteAdapter` implements
  `GuardedWriteCapable`: an edit is one `UPDATE ... WHERE version <= base`
  and a create one `INSERT ... ON CONFLICT DO NOTHING`, so Postgres refuses
  an upload made on top of a row another device has since changed. Datum
  then lets the conflict resolver decide instead of the last upload
  replacing the other.
- **The strip also shows the sync from app start,** which often finishes
  before the first screen is drawn, and has a widget test over a real Datum
  instance (`test/shared/sync_timing_strip_test.dart`). The paintings list
  and the drawing sheet have widget tests too (`test/features/paint/`).
- **Conflicts on real devices.** With one emulator offline holding a queued
  edit and the same task changed elsewhere, the offline device took the
  newer row as soon as realtime delivered it, dropped its own queued edit,
  and uploaded nothing after reconnecting. The live test
  (`test/live/supabase_local_sync_test.dart`) checks the same rules, and
  scoped sync, against real Postgres. The full list of scenarios and their
  tests is in `packages/datum/doc/SYNC_SCENARIOS.md`.
- **Login:** Enter moves from email to password and submits. **Dark theme:**
  task titles, the empty state and the add button use theme colors.

