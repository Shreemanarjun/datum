# Sync scenarios

What the sync engine has to do in each situation, and the test that checks
it. Test names are written as the rule they check, so each bullet below is
both. `test/doc/sync_scenarios_doc_test.dart` fails when a test named here no
longer exists, or a section id is missing from its suite.

Design background: [SYNC_ENGINE_AUDIT.md](SYNC_ENGINE_AUDIT.md).

## Where the suites run

The sync-stack suite (sections `sync.roundtrip` to `sync.queue.hygiene`) runs
against every combination of local store and kind of remote:

| Local store | Remotes |
|---|---|
| in-memory (`datum_test`) | in-memory full read; in-memory that guards writes; HTTP with timestamp delta; HTTP with cursor feed |
| Hive on disk (`datum_hive`) | the same four |
| SQLite on disk (`datum_sqlite`) | the same four |

That is 12 stacks. The HTTP remotes talk to a real local server
(`LocalSyncServer`) over sockets. The remote that guards writes refuses an
upload made on top of a row that has since changed (`GuardedWriteCapable`).
Other sections name the single file they live in.

## sync.roundtrip: A write reaches the other side

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_roundTripTests`)

- `push: a local save reaches the remote after sync`
- `pull: a remote row reaches the local store after sync`
- `two devices converge through the shared backend`
- `offline saves queue and replay when connectivity returns`
- `a clean second cycle is a no-op`
- `saveMany pushes the whole batch`
- `sync metadata is stamped on both sides with matching hashes`

## sync.order: Direction and order of operations

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_directionAndOrderingTests`)

- `pushOnly and pullOnly move data in one direction only`
- `create -> update -> update of one entity lands as the final state exactly once`
- `create -> update -> delete before any sync ends deleted on both sides`

## sync.failure: Uploads that fail

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_failureTests`)

- `a retryable failure defers later ops for that entity only, then succeeds`
- `an exhausted retry budget parks the op instead of dropping it`
- `a failed batch falls back per op without losing its siblings`
- `an update of an entity missing remotely is converted to a create`
- `a delete of an entity missing remotely is tolerated`

## sync.parked: Writes the server rejects for good

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_parkingTests`)

- `non-retryable 403 parks the op: kept, skipped with its successors, others sync, retry re-arms, discard drops`
- `parked state survives a crash and reopen`

## sync.auth: Expired login

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_authPauseTests`)

- `an expired session (401) pauses sync with the queue untouched; signing back in resumes and delivers on its own`
- `AuthErrorPolicy.park keeps the pre-pause behaviour`

## sync.options: Per-sync options

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_syncOptionTests`)

- `a retryable failure is retried by itself after the backoff delay`
- `includeDeletes: false holds deletes (and later ops of that entity) while other writes sync`
- `resolveConflicts: false reports the conflict and leaves both sides untouched`

## sync.guard: Guards on writes and clock-free rules

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_writeGuardTests`)

- `push(expectedVersion:) refuses a stale edit after a pull changed the row`
- `an edit made after seeing another one wins whatever the clocks say`
- `RemotePriorityResolver decides concurrent edits without device clocks: first push wins when pulling first, last push wins when pushing first`
- `a rate-limited write (429) is retried, not parked`

## sync.queue.api: Queue state and compaction

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_queueAndCompactionApiTests`)

- `watchPendingCount / isPending / waitUntilSynced follow the queue live`
- `purgeTombstones removes only old, uploaded tombstones`
- `a fresh device does not store tombstones of rows it never had`
- `clearUserData wipes one user\'s rows and queue only`

## sync.replay: Replay after a lost acknowledgement

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_crashAndReplayTests`)

- `an op whose remote write landed but was never dequeued (crash / lost ack) replays idempotently`
- `the first of two queued edits landed but its ack was lost: the second is still delivered, under every resolver and both directions`
- `a crash with a mixed offline queue resumes in order after reopen`

## sync.conflict: Conflicts

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_conflictTests`)

- `concurrent same-version edits resolve by last-write-wins and converge`
- `a stale remote row does not clobber a newer local one`
- `two devices editing concurrently converge on the later write`
- `clock skew: LWW follows device wall clocks, so a device running 10 min ahead beats a later real-time edit (documents current behavior; see API_AND_TESTING_REVIEW #10)`
- `an upload that fails leaves the edit in place for every resolver: the unchanged remote row is not a competing version`
- `two devices upload edits of one row without seeing each other, one of them twice: a remote that guards writes hands it to the resolver, one that accepts every write keeps the last upload`
- `a remote edit of a row this device never touched is taken as is, whatever the resolver; an unsynced local edit of it is a conflict`
- `pullThenPush conflict with $label converges on both sides`

## sync.conflict.matrix: Conflict matrix

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_conflictMatrixTests`)

Three devices: this device (the resolver under test), the device that made
the remote changes, and an observer that never edits. Every device follows
one policy, seen from its own side.

| Row | Remote side did | This device did (unsynced) | Must end as |
|---|---|---|---|
| `remote-edit` | one edit | nothing | the remote edit, no conflict |
| `remote-edit-twice` | two edits | nothing | the second remote edit, no conflict |
| `remote-delete` | delete | nothing | deleted, no conflict |
| `local-edit` | nothing | one edit | the local edit, no conflict |
| `local-edit-twice` | nothing | two edits | the second local edit, no conflict |
| `local-delete` | nothing | delete | deleted, no conflict |
| `both-create` | created it | created it too | per policy |
| `both-edit` | one edit | one edit | per policy |
| `both-edit-twice` | two edits | two edits | per policy |
| `local-edit-remote-twice` | two edits | one edit | per policy |
| `local-twice-remote-edit` | one edit | two edits | per policy |
| `local-edit-remote-delete` | delete | one edit | per policy |
| `local-delete-remote-edit` | one edit | delete | per policy |
| `both-delete` | delete | delete | deleted |

Policies: last write wins everywhere; this device wins (local priority here,
remote priority elsewhere); the other device wins (remote priority here,
local priority there); merge everywhere. Each runs pull-first and push-first:
14 rows x 4 policies x 2 directions, on each of the 12 stacks.

For every row: all three devices and the server end the same; rows marked
"per policy" end as the policy's winner (the table is `_policies` in the
suite); a conflict is reported only when both sides changed, and always when
the device pulls first or the remote guards writes; nobody has uploads left;
and one more round of syncs writes nothing anywhere.

- `conflict matrix: ${policy.label}, ${direction.name}`

## sync.delete: Deletes and watch streams

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_deleteAndWatchTests`)

- `soft deletes propagate local -> remote -> other device`
- `a remote soft delete propagates to the local store`
- `watch streams emit the post-sync state`

## sync.isolation: Users, volume and overlapping syncs

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_isolationAndScaleTests`)

- `users are isolated end to end, across a mid-session user switch`
- `a 2000-op queue drains completely with per-entity order kept`
- `a sync requested while one is in flight never double-pushes`

## sync.pull: Pulls

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_pullTests`)

- `an idle sync never hides a remote change: incremental remotes are asked every time, others skip only while the metadata beacon matches`
- `incremental pulls (when capable) still deliver later remote changes`
- `incremental pulls do not miss rows stamped exactly at the watermark`
- `incremental pulls deliver a late write from a writer whose clock is 10 min behind`

## sync.scope: Partial sync (scopes)

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_scopeTests`)

- `scoped syncs pull their own rows; a different scope is never skipped as "nothing changed", and rows outside the scope are left alone`
- `devices syncing different scopes do not hide each other\'s changes`
- `pull positions are remembered for a bounded number of scopes; a forgotten scope is simply read in full again`

## sync.queue.hygiene: Queue hygiene

Suite: `datum_test/lib/src/sync_stack_conformance.dart` (`_queueHygieneTests`)

- `an entity held back by retryable failures does not grow the queue`
- `a still-pending local hard delete is not undone by the pull`

## sync.live: Changes received live (no sync cycle)

Suite: `datum/test/unit/live_changes_test.dart`

- `changes applied from the remote change stream are reported per batch, without a sync cycle`
- `a live change follows the pull rules: stale rows are ignored and a row competing with an unsynced edit goes to the resolver`
- `a live change keeps the device-only fields of the row it updates`

## sync.clock: Vector clocks

Suite: `datum/test/integration/collaborative_editor_test.dart`

- `two devices edit the same document offline and converge via CRDT merge`
- `with vector clocks, an edit overwritten by a device that edited more often is still a conflict, not an update`

## sync.reconnect: Offline queue and reconnect

Suite: `datum/test/integration/connectivity_auto_sync_integration_test.dart`

- `queue is maintained offline - operations are queued when offline`
- `queue is maintained offline - delete operations are queued`
- `syncs successfully when online - connectivity restoration triggers sync`
- `connectivity restoration catches up a user kept in sync who has nothing to upload`
- `syncs successfully when online - multiple users with pending operations`
- `syncs successfully when online - handles mixed create/update/delete operations`

## sync.http: Over real HTTP (local server)

Suite: `datum/test/integration/local_server_integration_test.dart`

- `happy path: push and pull round-trip over real HTTP`
- `patch->create fallback: real 404 on PATCH converts the op to a create`
- `transient 500 on push: op is re-queued and succeeds on the next sync`
- `metadata pre-check failure degrades to a full sync instead of failing`
- `severed connection maps to a retryable failure; recovery converges`
- `503 outage then recovery: nothing lost across the offline window`
- `config.syncTimeout fires against real server latency`
- `server-side 409 version conflict surfaces as ConflictException; pull converges`
- `unicode and special characters survive the wire round-trip`
- `hard delete propagates over HTTP; deleting an already-absent entity is safe`
- `mixed create/update/delete cycle lands the correct final server state`
- `an unchanged sync on a delta-capable remote is one incremental read, and never misses a write made behind its back`
- `without incremental pulls the metadata beacon decides: an unchanged sync fetches no entities`
- `corrupted JSON response surfaces as SerializationException; recovery works`
- `401 pauses sync with the op untouched; signing back in resumes and pushes it`
- `syncAfterWriteDelay: a burst of local writes uploads in one debounced sync, no sync call`
- `429 with Retry-After: the op is retried by itself, no sooner than the server asked`
- `a throttled pull (429 + Retry-After) fails the cycle and is retried once the wait is over`
- `403 parks the op (never drops it); retry re-arms it`
- `concurrent synchronize calls serialize: exactly one POST per operation`
- `user isolation over the wire: syncing u1 never pulls u2 data`
- `large dataset pull: hundreds of entities stream over HTTP intact`
- `two devices converge across the real server (metadata beacon end-to-end)`

## sync.delta: Incremental pulls by timestamp

Suite: `datum/test/integration/delta_sync_integration_test.dart`

- `first sync pulls full, later syncs pull incrementally on the wire`
- `the watermark is widened by deltaSyncOverlap`
- `rows re-delivered inside the overlap window are idempotent`
- `soft deletes propagate through a delta pull`
- `enableDeltaSync: false always pulls full even when the adapter is capable`
- `forceFullSync pulls everything even on a delta-capable adapter`
- `a server that can no longer serve the watermark (410) gets a full pull instead of a failed sync`
- `detectRemoteDeletions forces full pulls (needs the complete remote id set)`

## sync.cursor: Incremental pulls by cursor

Suite: `datum/test/integration/cursor_sync_integration_test.dart`

- `first sync reads the feed from the beginning, later syncs pass the cursor`
- `an expired cursor (410) restarts the feed from the beginning and stores the new cursor`
- `the cursor survives an app restart (new manager, same local store)`
- `cursor path wins over the timestamp path when both are advertised`
- `the cursor is per-device: local metadata carries it, the remote beacon does not`
- `detectRemoteDeletions cycles use a full pull and leave the cursor unchanged`
- `soft deletes ride the feed`

## sync.coldstart: App start

Suite: `datum/test/integration/cold_start_integration_test.dart`

- `should not perform cold start sync when disabled`
- `should perform full sync on cold start`
- `should not perform sync on subsequent calls (not cold start)`
- `should perform sync when no previous cold start exists`
- `should skip sync when within threshold`
- `should perform sync when beyond threshold`
- `should perform incremental sync (no force full sync)`
- `should perform priority-based sync`
- `should apply initial delay before sync`
- `should respect max duration timeout`
- `should not mark cold start as completed on sync failure`
- `should allow retry after failed cold start`
- `should integrate cold start into manager initialization`

## sync.crash: Crash and reopen

Suite: `datum_test/lib/src/crash_recovery_conformance.dart`

- `queued offline ops survive a crash and deliver exactly once after reopen`
- `crash mid-sync over severed sockets recovers with exactly-once delivery`
- `schema version and sync metadata survive a crash`

## sync.fuzz: Random operations converge

Suite: `datum_test/lib/src/convergence_fuzz.dart`

Runs with several seeds and device counts; the test name is a template.

- `$devices devices converge after $rounds rounds of random ops (seed $scenarioSeed)`

## sync.chaos: Converges under network faults

Suite: `datum_test/lib/src/chaos_profiles.dart`

One test per fault profile; the test name is a template.

- `converges after ${profile.name}`

## store.keys: Map key naming and timestamp precision

Suite: `datum_test/lib/src/key_naming_conformance.dart`

- `snake_case maps are read, scoped, listed and cleared per user`
- `soft delete, tombstone filtering and restore work through a manager`
- `a timestamp finer than the local store keeps is not a conflict on every pull`
- `a device-only field stays on the device and survives whatever the remote sends`

## store.migration: Schema migrations

Suite: `datum_test/lib/src/migration_conformance.dart`

- `valid chain transforms values, stamps the target version, and flips needsMigration`
- `invalid chain (gap) fails fast with no data or version change`
- `mid-chain failure restores original data and version`
- `migration history lists every applied step, in order`
- `a failed chain records only the failing step, as failed`
- `resume from stored version runs only the remaining steps`
- `a successful migration runs once across an app relaunch`

## state.signals: State an app reads (signals)

Suite: `datum/test/unit/state_signals_test.dart`

Sync status, health, metadata, next sync time and metrics are `signals_core` signals; see section 5 of the audit.

- `the status, health, metadata and next sync time of a manager are signals that follow the engine`
- `Datum exposes its metrics, the statuses of its users and the health of every manager as signals`

## state.streams: The same state as streams

Suite: `datum/test/unit/event_stream_test.dart`

- `watchSignal gives every listener the current value, then each change, and ends with the signal`
- `batchedEvery emits what each window collected, and nothing for an empty one`
- `startWith and whereType`

## ui.strip: The sync timing strip of the example app

Suite: `datum/example/test/shared/sync_timing_strip_test.dart`

A widget test over a real Datum instance: the strip must move for a sync this device ran and for a change it only received.

- `shows a sync this device ran and a change it received live, newest first`

## ui.paintings: The paintings list of the example app

Suite: `datum/example/test/features/paint/paint_canvas_list_test.dart`

- `stroke counts follow the strokes, also when they arrive after the list is shown`

## ui.sheet: The drawing sheet of the example app

Suite: `datum/example/test/features/paint/paint_canvas_test.dart`

- `the sheet has the same 2:3 shape on a phone, a tablet and an unfolded foldable, so a drawing made on one is whole on the others`

## backend.supabase: Against a real Supabase (Postgres, Auth, Realtime)

Suite: `datum/example/test/live/supabase_local_sync_test.dart`

Needs the local Supabase stack: `flutter test test/live/supabase_local_sync_test.dart --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...` (see `example/supabase/README.md`). Skipped without those.

- `two devices on one account: push, pull, realtime, deletes, conflicts, offline, expired session`
- `what is and is not a conflict, and scoped sync, against real Postgres`

## device: Checked by hand on running devices

Not automated, and not needed to trust the rules above: every item has an
automated counterpart (named in brackets). Done on 2026-11-27 with the
example app on an iOS simulator and two Android emulators (one phone, one
foldable) against the local Supabase stack. The simulator's app was upgraded
in place and kept its data (2 tasks, 6 paintings); the emulators got a fresh
install. All three then signed in to one new account.

- A task created on the phone shows on the other two without a manual sync,
  and so does ticking it on the foldable. The timing strip moves on all
  three: `Task sync 36 ms ↑1` on the editing device, `Task live ↓1 · 8 ms to
  apply · 246 ms after the edit` on a receiver. [`ui.strip`,
  `backend.supabase`]
- One edit is one sync cycle. The app log of the editing device shows a
  single cycle (`Synced: 1`), started 4 ms after the tap. This check found
  two faults, both fixed: the debounced after-write sync ran a second, empty
  cycle whenever the first one took longer than its delay, and the app
  probed the internet for about 400 ms before every sync. [`sync.http`,
  "syncAfterWriteDelay"]
- Offline, then back: with the phone's network switched off, an edit there
  is saved, marked as waiting to upload, and no sync runs. Switching the
  network on uploads it without a tap (`Task sync 61 ms ↑1`), and the other
  two devices show it. [`sync.reconnect`, `backend.supabase`]
- Signing out and in as another user on the simulator shows that user's
  data only. [`sync.isolation`]
