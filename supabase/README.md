# Supabase database history

The file migrations/20260801000000_baseline_schema.sql is the reproducible
structural baseline for ManagerSpiel. It was generated from the production
Postgres catalog on 2026-08-04, after the public RPC permission hardening.

The baseline is ordered before the security migrations so a fresh Supabase
database can be built from an empty project. It includes:

- all 27 public tables, sequences, constraints, indexes, comments, and the
  transfer_status enum
- all 64 public functions and all application triggers, including the
  auth.users profile trigger
- RLS state, policies, role grants, Realtime publication membership, Storage
  bucket configuration, and scheduled Postgres jobs

It intentionally excludes production rows, Auth users, league and sports data,
Storage objects, API keys, Vault values, and all other secrets. Stable
formation and singleton configuration rows live in seed.sql.

The unused legacy `pgjwt` extension is intentionally not recreated. Supabase
removed it from newer PostgreSQL 17 images, and no application object in this
baseline depends on it.

## Existing production project

Do not execute the baseline against the existing ManagerSpiel project. Its
objects already exist. Production adopts this file as historical baseline;
only later, unapplied migrations are executed there.

## Fresh project

Apply migrations in filename order to an empty Supabase project, then run
supabase/seed.sql. The later security migrations intentionally replace the
baseline's historical grants and policies.

Before promoting further migrations, compare the generated catalog with
production and run both Supabase security and performance advisors.
