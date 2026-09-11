# Season-Lifecycle – Implementierung und Betriebsnachweis

Stand: 11.09.2026. Basis: `origin/main` bei `be62b28ef442881a15be81af30e0e234a1759fb4`, unmittelbar vor Abschluss erneut abgeglichen. Branch: `feat/season-lifecycle`. Das ursprüngliche lokale Checkout und dessen uncommittete Arbeiten wurden nicht verändert.

## Verhalten

- `daily-season-check` erzeugt täglich um **04:15 UTC** (im Sommer 06:15 Berlin) genau einen offenen `CHECK_SEASONS`-Task je bekanntem Tournament. Wiederholte Aufrufe am selben Tag erzeugen keine zusätzlichen Tasks. Auch bislang inaktive Tournaments werden geprüft.
- Der vorhandene angemeldete App-Worker ruft dafür `/unique-tournament/{id}/seasons` ab. Er validiert die gesamte Antwort und speichert SofaScore-ID, Jahresbezeichnung und Tournament-ID. Bestehende Zeilen werden bei Konflikten vollständig beibehalten. Der Global Scout benutzt denselben konfliktignorierenden Schreibmodus; er wird weiterhin nicht bei jedem Appstart ausgeführt.
- Entdecken und Aktivieren sind getrennt. Ein erfolgreicher Check erlaubt dem minütlichen `process-season-lifecycle` die Fortschreibung bereits aktivierter Tournaments auf eine Saison mit eindeutig neuerem Startjahr. Ein fehlgeschlagener/unvollständiger Check löst keinen automatischen Wechsel aus.
- Andere Tournaments benötigen eine explizite Aktivierungsanforderung aus der bestehenden Turnierinitialisierung. Eigene Anforderungen sind per RLS lesbar; Fehler und Bearbeitungszeit werden gespeichert. Historische, archivierte Saisons werden nicht wieder aktiviert. Mehrdeutige Wechsel innerhalb desselben Startjahres und unbekannte Jahresformate werden abgewiesen.
- Der Wechsel sperrt das Tournament, deaktiviert und markiert die alte Saison mit `archived_at`, aktiviert die neue und startet genau einen `FETCH_TEAMS`-Task. Es folgt `FETCH_TEAM_SQUAD` pro Team, dann `FETCH_ROUNDS`, dann `FETCH_MATCHES`. Leere Team-/Kader-/Runden-/Spielimporte können keine erfolgreiche Initialisierung vortäuschen. Schreibfehler in den relevanten Importhelfern werden an den Worker weitergegeben.
- Initialisierungsmarker und eindeutige Task-Indizes verhindern Wiederholungen; parallele Kader-Abschlüsse sind serialisiert. Bereits initialisierte Seasons werden bei erneuter Aktivierung nicht neu initialisiert.
- Keine Löschanweisung und kein Aufruf von `reset_season_data` gehört zum neuen Lifecycle. Alte Teams, Kader, Spiele, Spieltage, Analytics und Fantasy-Ligen bleiben erhalten.

## UI und Saisonbindung

`TournamentViewModel` sortiert Turniere nach Name/ID und Saisons nach Startjahr/ID. Standard ist die aktive Saison. Explizite Auswahlen bleiben pro Tournament bei Refresh erhalten; ein automatisch gewählter Standard folgt dem aktiven Wechsel. Leere Ergebnislisten löschen veraltete Auswahlwerte; verspätete Ladeantworten überschreiben keine neueren Antworten.

Die Überschrift zeigt zum Beispiel „Premier League – Saison 26/27“. Über die Saisonwahl sind alle vorhandenen Seasons jedes Tournaments auswählbar, einschließlich archivierter und noch nicht initialisierter Einträge. Sichtbar sind aktiv/aktuell, archiviert oder inaktiv sowie der Initialisierungsstatus. Ein Wechsel erstellt die drei Ansichten mit einem neuen Saison-Schlüssel; die Spielsubscription wird freigegeben und erneut saisonbezogen aufgebaut. Die Wahl selbst schreibt keine Saisondaten.

Managerliga-Neugründungen verwenden die aktive **initialisierte** Saison des ausgewählten Tournaments, selbst wenn gerade eine historische Saison betrachtet wird. Diese Zuordnung wird im Dialog ausdrücklich angezeigt und serverseitig beim Insert nochmals geprüft. Ein Wechsel während eines offenen Dialogs wird deshalb sicher abgewiesen, statt eine neue Liga in einer inzwischen archivierten Saison anzulegen.

Fantasy-Kader, Aufstellungsspeicherung, Ranking, Spieltags-Overlay, Profil-Ligaansicht und Starterteam verwenden die in `leagues.season_id` gespeicherte Saison. Spielerdetails aus Fantasy-Ansichten erhalten die Liga-ID und lösen darüber die Saison auf. Spielerdetails aus einem Spiel erhalten dessen eigene Saison-ID. Beim Betrachten historischer Spiele wird kein Ratings-Sync gestartet; ein globales Spieler-Aktivflag blendet historische Matchkader nicht mehr aus.

Der ungenutzte `SeasonProvider` wurde entfernt; im aktuellen Repository gab es keine Aufrufstellen.

## Datenbankänderungen

Produktiv angewendet in **ManagerSpiel** (`rcfetlzldccwjnuabfgj`):

`supabase/migrations/20260911132711_season_lifecycle.sql`

Die Datei wurde mit `supabase migration new` erzeugt und nach Anwendung auf die vom produktiven Migrationseintrag zurückgegebene Version umbenannt. Der SQL-Inhalt ist identisch. Frühere produktive Migrationen waren bereits vor dieser Arbeit nicht im aktuellen `main` versioniert; diese inkrementelle Migration ist keine vollständige Neuinstallation des Altschemas.

| Objekt | Änderung |
|---|---|
| `season` | Default `is_active=false`; Tournament-ID NOT NULL; neue Felder `discovered_at`, `archived_at`, `initialization_started_at`; RLS und beschränkte Spaltengrants |
| `season_one_active_per_tournament` | Partieller Unique-Index: höchstens eine aktive Season je Tournament |
| `season_id_tournament_unique`, `season_tournament_lookup` | Konsistente zusammengesetzte Referenz und Tournament-Lookup |
| `leagues_season_tournament_fkey` | Verhindert widersprüchliche redundante Tournament-/Season-Zuordnungen |
| `guard_league_season`, `leagues_preserve_season` | Season einer bestehenden Fantasy-Liga unveränderlich; Tournament abgeleitet; neue Liga nur aktiv/initialisiert |
| `sync_initialization_stage_once` | Ein Initialisierungstask pro Season, Stufe und gegebenenfalls Team, unabhängig vom Taskstatus |
| `sync_one_open_season_check`, `sync_season_check_history` | Keine parallelen Discovery-Duplikate, effizienter Tagescheck |
| `handle_season_activation`, `on_season_activated` | BEFORE INSERT/UPDATE, genau einmal Initialisierung starten |
| `check_and_unlock_dependencies` | Idempotente Fan-out/Fan-in-Kette, leere Imports werden abgelehnt; bestehender Trigger `on_sync_task_status_change` bleibt angebunden |
| `season_start_year` | Gemeinsame chronologische Interpretation von `25/26`, `2026`, `2025/2026` usw. |
| `activate_season` | Transaktionaler, gesperrter Wechsel; nur Service-/Betriebsrolle darf ausführen |
| `season_activation_requests` | Neue RLS-geschützte Anforderungstabelle mit Benutzer, Verarbeitung und Fehler; eigener Pending-/Owner-Index |
| `generate_season_check_tasks` | Eigene tägliche Discovery-Queue, per Advisory Lock und Unique-Index abgesichert |
| `process_season_lifecycle` | Bearbeitet manuelle Erstaktivierungen und kontrollierte automatische Fortschreibungen |
| `daily-season-check` | Cron: `15 4 * * *` |
| `process-season-lifecycle` | Cron: `* * * * *` |

`generate_routine_sync_tasks` und der bestehende zweiminütliche Routine-Cron wurden nicht verändert. Alle neuen/ersetzten Lifecycle-Funktionen sind `SECURITY INVOKER` mit festem leerem `search_path`. Clients können die Betriebsfunktionen nicht ausführen und weder aktive Flags, Archivierung noch Initialisierungsmarker direkt schreiben. Die bereits vorhandenen authentifizierten Task-Reservierungs-/Abschluss-RPCs wurden nicht durch neue privilegierte Abkürzungen ersetzt.

## Produktiver Vorher-/Nachher-Abgleich

| Bestand | Vorher | Nachher |
|---|---:|---:|
| Seasons | 134 | 134 |
| Season-Teams | 64 | 64 |
| Season-Players | 2269 | 2269 |
| Spiele | 1366 | 1366 |
| Spieltage | 122 | 122 |
| Spieler-Analytics | 4184 | 4184 |

Aktive IDs unverändert: `76986`, `77559`, `78229`. Keine doppelt aktiven Tournaments. Die Migration selbst erfindet keine SofaScore-Seasons.

Fantasy-Liga `42` bleibt an Season `78229`, Tournament jetzt korrekt `173`. Fantasy-Liga `52` bleibt an Season `76986`, Tournament jetzt korrekt `17`. Ausschließlich die redundanten Tournament-Werte wurden korrigiert.

Produktiv bestätigt: beide neue Cronjobs aktiv, Routine-Cron unverändert aktiv, Season-RLS eingeschaltet, `activate_season` für `authenticated` nicht ausführbar. Es wurden keine synthetischen Testdaten produktiv eingefügt.

## Tests und Grenzen der Verifikation

- **7 Flutter-Tests bestanden**: deterministische Sortierung; aktive Standardauswahl; explizite Historie; neue/verspätete Ladeantworten; Fantasy-Neugründung bleibt an der aktiven Saison; tatsächlicher HTTP-Schreibmodus mit `resolution=ignore-duplicates`; API-403 wird weitergereicht; Scout überschreibt nicht; Fantasy-Saison wird aus der Liga gelesen; Widget-Wechsel inklusive aller drei tatsächlich nach `season_id` gefilterten Turnierabfragen.
- **PostgreSQL-17-Integrationstests bestanden**: Migration gegen isolierte, aus Produktion gelesene Tabellenformen, historische Daten erhalten, Ligaredundanz korrigiert, Berechtigungen und fremde Anforderungen abgewiesen, vollständige Initialisierungskette, idempotente Discovery/Aktivierung/Task-Replays, historische Neugründung abgewiesen und neue Liga korrekt gebunden.
- **Echte Paralleltests mit separaten DB-Verbindungen bestanden**: vier gleichzeitige Aktivierungen erzeugen genau einen Initialisierungsstart; zwei gleichzeitige Kader-Abschlüsse geben die Runden frei.
- **Release-Webbuild erfolgreich** (`flutter build web --release --no-pub`, einschließlich Wasm-Dry-Run). Bestehende Flutter-Web-Bootstrap-/Service-Worker-Deprecations bleiben bestehen.
- `flutter analyze`: **keine Fehler**; das Gesamtprojekt enthält weiterhin bestehende Warnungen/Infos. Kein pauschal grüner Analyzer behauptet.
- Auth und Cron sind in den lokalen DB-Tests gestubbt; getestete Worker-RPCs stammen aus der gelesenen Produktion. Die Tests sind keine vollständige Simulation aller Legacy-Trigger. Die echte Migration wurde anschließend erfolgreich in Produktion angewendet und dort separat geprüft.
- Netzwerkantworten von SofaScore sind in den Flutter-Tests gemockt. Ein tatsächlicher Import einer realen neuen Saison und ein Gerätetest mit angemeldetem Benutzer sind damit nicht nachgewiesen.

Ausführen:

```text
flutter test --no-pub
flutter analyze --no-pub
python supabase/tests/run_season_tests.py --port 55441
```

Der PostgreSQL-Test benötigt einen lokalen PostgreSQL-17-Server auf 127.0.0.1, Rolle postgres. `PSQL` kann auf die passende psql-Datei gesetzt werden. Er erzeugt eine eigene `managerspiel_test_seasons_*`-Datenbank und löscht keine bestehende Datenbank. Ein vollständiger Supabase-Reset ist wegen des fehlenden historischen Baselineschemas nicht der Testweg.

## Offene Betriebsrisiken / Rollout

1. **App-Worker erforderlich:** Cron erzeugt Aufträge unabhängig von Appstarts; SofaScore-Zugriffe laufen weiterhin im bestehenden angemeldeten App-Worker. Ohne aktualisierte laufende App bleiben sie liegen. Alte App-Versionen unterstützen `CHECK_SEASONS` noch nicht; sie können den Task reservieren und bis zum bestehenden zehnminütigen Lease-Timeout blockieren. Die neue App-Version aus diesem Branch muss ausgerollt werden. Es wurde kein unabhängiger Server-Scraper eingeführt.
2. **Jahreswechselregel:** Automatische Fortschreibung bedeutet eine eindeutig neuere von SofaScore gelieferte Jahresbezeichnung, kein bestätigtes Datum des ersten Saisonspiels. Früh veröffentlichte Folgesaisons können entsprechend früh aktiv werden. Unbekannte Formate und gleiche Startjahre benötigen bewusste Klärung durch den Betreiber.
3. **Bestehendes Datenvertrauen:** Der bestehende kooperative App-Import schreibt öffentliche Sportreferenzdaten. Er ist keine serverseitige Echtheitsprüfung von SofaScore-Antworten. Aktivierungsberechtigungen sind beschränkt, ersetzen aber keine vertrauenswürdige serverseitige Datenquelle.
4. **Import-/API-Verfügbarkeit:** 403/429, fehlende Runden oder Kader verhindern eine fertige Initialisierung. Tasks bleiben zur Wiederholung erhalten; eine aktivierte neue Saison kann deshalb vorübergehend noch keine vollständigen Daten haben. Es gibt keinen automatischen Rückwechsel, der Fantasy-Ligen umhängen würde.
5. **Bestehende Sicherheitsbefunde:** Nach Migration meldet Supabase weiterhin 18 andere öffentliche Tabellen ohne RLS, 2 Tabellen mit Policies bei deaktiviertem RLS, 49 alte Funktionen ohne festen search_path und weitere bestehende Hinweise zu privilegierten RPCs, Passwortschutz und Postgres-Patchstand. Für die neuen Lifecycle-Funktionen/-Tabelle gibt es keine neuen Sicherheitsbefunde. Eine globale Berechtigungsreparatur wäre ein eigener, deutlich größerer Auftrag. Hinweise: [RLS-Befunde](https://supabase.com/docs/guides/database/database-linter?lint=0013_rls_disabled_in_public), [Funktions-search_path](https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable).
6. **Gemeinsame Stammdaten:** Spielernamen, Positionen und Bilder bleiben globale Stammdaten. Saisonbezogene Kader und Analytics bleiben erhalten; es werden keine vollständigen historischen Stammdaten-Snapshots neu angelegt.
7. **Administrative Datenresets:** `reset_season_data` wird nicht benutzt. Der neue Initialisierungsmarker ist absichtlich dauerhaft; eine manuelle Löschung von Initialisierungstasks erfordert eine gezielte Betriebsreparatur und ist kein unterstützter Saisonwechsel.

Zum Pausieren des neuen Flows die zwei benannten Cronjobs über `cron.alter_job(..., active := false)` deaktivieren. Seasons, Fantasy-Ligen und Daten dabei nicht löschen oder umhängen. Cron-Verhalten: [Supabase Cron](https://supabase.com/docs/guides/cron).

## Geänderte Dateien

Die folgende Liste enthält sämtliche Änderungen dieses Branches (einschließlich Tests und Dokumentation).

- `docs/season-lifecycle.md`
- `lib/data_service.dart`
- `lib/screens/User/profile_screen.dart`
- `lib/screens/leagues/activity_feed_tab.dart`
- `lib/screens/leagues/league_hub_screen.dart`
- `lib/screens/leagues/league_settings_screen.dart`
- `lib/screens/leagues/league_team_screen.dart`
- `lib/screens/leagues/matchday_team_overlay.dart`
- `lib/screens/leagues/ranking_screen.dart`
- `lib/screens/leagues/starter_team_reveal_screen.dart`
- `lib/screens/leagues/transfer_market_screen.dart`
- `lib/screens/player_screen.dart`
- `lib/screens/premier_league/matches_screen.dart`
- `lib/screens/premier_league/premier_league_screen.dart`
- `lib/screens/premier_league/season_picker.dart`
- `lib/screens/premier_league/top_team_screen.dart`
- `lib/screens/spiel_screen.dart`
- `lib/utils/season_order.dart`
- `lib/viewmodels/data_viewmodel.dart`
- `lib/viewmodels/season_provider.dart` (entfernt)
- `lib/viewmodels/tournament_viewmodel.dart`
- `supabase/.gitignore`
- `supabase/config.toml`
- `supabase/migrations/20260911132711_season_lifecycle.sql`
- `supabase/tests/legacy_fixture.sql`
- `supabase/tests/production_shape.sql`
- `supabase/tests/run_season_tests.py`
- `supabase/tests/season_lifecycle.sql`
- `test/season_viewmodel_test.dart`
- `test/widget_test.dart`
