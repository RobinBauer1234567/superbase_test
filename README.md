# premier_league

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Supabase troubleshooting

If league creation fails with:

`column "purchase_price" of relation "league_players" does not exist (42703)`

run the SQL migration in `docs/sql/fix_league_players_purchase_price.sql` in your Supabase SQL Editor.

## Working with Codex changes in Android Studio

If you do not see my code changes in Android Studio, your local repo is usually up to
date with `origin/main`, but my changes are still only in a separate branch/PR.

Use this workflow:

1. Open the GitHub pull request created for the change.
2. Merge the PR into `main` on GitHub.
3. In Android Studio terminal run:

```bash
git checkout main
git fetch origin
git pull origin main
```

4. Refresh Android Studio (`File -> Synchronize`) if files are not updated instantly.

Quick checks:

```bash
git remote -v
git branch -vv
git log --oneline -n 5
```

If `main` says "Already up to date" and you still do not see the change, the PR was
not merged yet or you are on a different branch than expected.
