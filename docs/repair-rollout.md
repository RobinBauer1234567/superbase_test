# Repair rollout and verification

Base: `main` at `fa9261ef517cce82480f6cf38c4d35c5a49e1aef`.
Worker source: `agent/port-league-settings-screen` at `36bee1a06daeb14c02755ec6b7b7b421c705a81b`.
No unrelated league settings screens were imported.

## Production gate

**Do not deploy these migrations or the new application until the fixture conflicts
are resolved.** The read-only 2026-09-09 audit found 92 conflicting team/round
combinations involving 97 distinct fixture IDs, documented in
`fixture-conflicts-2026-09-09.json`. Production has not been changed.

Direct SofaScore event requests returned HTTP 403. Stored `api_debug_dump` samples
contain lineups, not authoritative event metadata. Ratings or timestamps alone
are insufficient to choose which record is canonical. Do not keep the first ID,
discard conflicts with `ON CONFLICT DO NOTHING`, or delete rows without evidence.

For every conflicting group obtain authoritative event metadata (event ID,
tournament, season, round, status and replacement/cancellation information).
Record the source and explicit old-to-canonical mapping. Before applying that
mapping, export the affected fixtures, ratings and snapshots. Reconcile ratings
and snapshot references in one transaction, preserving lineup positions, locked
states and ownership; recompute affected totals and matchday time windows.
Conflicting nonidentical ratings require explicit resolution, not summation.
No data-cleanup mapping is included because source validity is still unresolved.

Run `supabase/preflight_repair.sql` again. Resolve missing team/round references,
multiple active teams per player and duplicate ratings as well. The integrity
migration intentionally aborts on duplicate fixture slots without changing data.

## Deployment order

1. Stop client imports during the maintenance window and snapshot the affected
   schema/data. Check the deployed function definitions against the reviewed base.
2. Apply the verified fixture reconciliation, then the two new migrations in filename
   order. Never reapply the historical baseline to the existing production project.
3. Deploy the matching Flutter application. Old clients cannot write to the queue
   or import tables freely after the migration; do not leave them active as workers.
4. Sign in and verify tasks complete through the full initialization chain. Test a
   second account, app pause/resume, sign-out and a league with starting players.
5. Verify the next daily cron run using `private.market_value_runs`, plus actual
   `spieler_analytics` changes for each active season. Cron success alone is insufficient.

The UTC daily schedule remains unchanged. Each season is adjusted at most once
per UTC date; retries can rerun failed seasons. Missed historical days are not
replayed. Failures are logged per season and do not abort later seasons.
Task failures back off and stop after five attempts. A failed task is retained
for investigation; an administrator can reset it after its cause is fixed.
Claim reservations expire after ten minutes and the active client renews them
every two minutes. Tasks run only while a signed-in client is active.

If validation fails, stop workers and keep the rollout paused. Do not restore
broad client grants as a workaround. Preserve the failure logs and repair forward.

## Tests

`flutter test` covers import metadata, duplicate team appearances, worker failures,
cancellation/concurrent entry, and signed-out app startup. `flutter build web`
checks the full application. No new package dependencies were added; the lockfile
reflects the installed Flutter 3.41.4 SDK's test/runtime pins.

With a separate local PostgreSQL 17 instance listening only on 127.0.0.1:55439:

```
python supabase/tests/run_native.py --database managerspiel_test_repair
python supabase/tests/concurrency.py managerspiel_test_repair
```

The runner creates a new database with a required test-only name. It applies the
real baseline and migrations, seeds reference data and executes transactional SQL
tests. Minimal Auth/Storage stubs replace hosted services and pg_cron scheduling
is omitted. Therefore these tests do not validate hosted Auth, Storage uploads,
the external provider or an actual scheduled cron invocation. Repeat the end-to-end
checks on a Supabase staging project before production promotion.
