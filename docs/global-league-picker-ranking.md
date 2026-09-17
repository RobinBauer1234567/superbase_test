# Global league picker ranking

The tournament picker uses one country/association coefficient to order countries globally.

## Sources

- UEFA associations: five-year association coefficient snapshot for 2026/27.
- Non-UEFA associations: deliberately coarse manual comparison values. They are not presented as an official ranking and can later be replaced by a global league-strength model.

The database stores the selected value in `tournaments.association_coefficient` and its provenance in `tournaments.coefficient_source` (`uefa_5y_2026_27` or `manual_global`).

## Tournament metadata

Each tournament carries:

- `country_name`
- `gender`: `M` or `F`
- `tier`: domestic league level, where `1` is the highest division
- `association_coefficient`
- `coefficient_source`

The initial migration backfills known tournaments. A database trigger also enriches newly discovered tournaments and normalizes common country aliases. Explicit metadata can later be supplied by the SofaScore scout; the trigger keeps known league levels and obvious women's competitions consistent.

## Picker ordering

1. Apply text search to league name, raw country name and German country display name.
2. Apply optional gender filter (`all`, `M`, `F`).
3. Group remaining tournaments by country.
4. Sort countries by `association_coefficient` descending.
5. Within a country, show men's competitions first, ordered by `tier` ascending; then women's competitions, also ordered by `tier` ascending.
6. Use the league name alphabetically only as a final tie-breaker.

The country heading is display-only and remains non-interactive.
