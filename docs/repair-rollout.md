# Repair rollout and verification

Base: `codex/add-progress-bar-and-player-display-g4o25s` at `88f0576`.
The initialization progress UI and player display changes are retained.

## Production handling

Production has not been changed by this PR. Apply the migrations only during a
maintenance window with old client workers stopped, because task permissions and
import-table writes are tightened together.

The read-only 2026-09-09 audit found 92 conflicting team/round combinations
involving 97 fixture IDs, documented in `fixture-conflicts-2026-09-09.json`.
The integrity migration handles these conflicts in one transaction:

- archive each affected fixture, its ratings and affected snapshots in the
  private `fixture_reimports` table
- mark older open tasks for those fixtures as failed
- create one high-priority `UPDATE_MATCH` task for every removed fixture
- clear imported match/rating references from affected snapshots while keeping
  ownership, lineup positions and locks
- delete the conflicting fixtures and rebuild matchday time windows

The refreshed source import must recreate a fixture with consistent tournament,
season and round metadata. If the source still returns conflicting data or an
unsupported match status, the task fails and remains visible for investigation.
Do not bypass this by keeping the first row, using `LIMIT 1`, or suppressing
duplicates with `ON CONFLICT DO NOTHING`.

## Deployment order

1. Stop active client workers and take a database backup.
2. Apply the new migrations in filename order. Never reapply the historical
   baseline to an existing production project.
3. Deploy the matching Flutter app version from this PR.
4. Sign in with two accounts and verify task claim, completion, failure,
   lease expiry and the initialization progress display.
5. Create and join leagues with zero and multiple starting players.
6. Verify the next daily market-value run through `private.market_value_runs`
   and actual `spieler_analytics` changes for every active season.

Task reservations expire after ten minutes and the client renews them every two
minutes. Failed tasks back off and stop after five attempts. The task processor
is intentionally still tied to a signed-in, running app.

## Tests

Validated in this PR:

```
flutter test --no-pub test/client_sync_task_worker_test.dart test/match_import_test.dart
python supabase/tests/run_native.py --port 55440 --database managerspiel_test_progress_01
python supabase/tests/run_native.py --port 55440 --database managerspiel_test_progress_reimport_01 --fixture-reimport
flutter analyze --no-pub lib/services/client_sync_task_worker.dart lib/services/match_import.dart lib/viewmodels/data_viewmodel.dart test/client_sync_task_worker_test.dart test/match_import_test.dart
```

The full project analysis still reports existing warnings outside the repair
scope. A Web build should pass before merging and deploying.
