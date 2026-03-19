// lib/viewmodels/data_viewmodel.dart
import 'package:premier_league/data_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math'; // <-- Wichtig für Random()

class DataManagement {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ApiService apiService = ApiService();
  final SupabaseService supabaseService = SupabaseService();

  final int seasonId;
  final int tournamentId;

  DataManagement({required this.seasonId, required this.tournamentId});

  bool _isAutoSyncRunning = false;

  /// Startet den Background-Worker, der kontinuierlich Tasks abarbeitet
  void startAutoSync() async {
    if (_isAutoSyncRunning) return;
    _isAutoSyncRunning = true;
    // await apiService.runGlobalLeagueScout();
    print('🔄 🟢 Auto-Sync Worker gestartet.');

    while (_isAutoSyncRunning) {
      bool didWork = await processNextSyncTask();

      if (didWork) {
        // Kurze Pause nach getaner Arbeit
        await Future.delayed(const Duration(seconds: 2));
      } else {
        // Längere Pause, wenn es nichts zu tun gibt
        final int randomSeconds = 15 + Random().nextInt(15);
        await Future.delayed(Duration(seconds: randomSeconds));
      }
    }
  }

  void stopAutoSync() {
    _isAutoSyncRunning = false;
    print('🛑 🔴 Auto-Sync Worker gestoppt.');
  }

  /// ------------------------------------------------------------------
  /// DER WORKER: Holt sich den wichtigsten Task und führt ihn aus
  /// ------------------------------------------------------------------
  Future<bool> processNextSyncTask() async {
    if (await _isDeviceBanned()) return false;

    final user = _supabase.auth.currentUser;
    if (user == null) return false;

    try {
      // 1. Task aus der DB holen und sperren
      final response = await _supabase.rpc('get_next_sync_task', params: {
        'p_user_id': user.id
      });

      final List<dynamic> tasks = response as List<dynamic>;
      if (tasks.isEmpty) return false; // Nichts zu tun

      final task = tasks.first;
      String taskId = task['id'];
      String taskType = task['task_type'];
      int tId = task['tournament_id'] ?? tournamentId;
      int sId = task['season_id'] ?? seasonId;

      print('👷 WORKER: Starte Aufgabe [$taskType] (Prio: ${task['priority']})');

      try {
        // 2. Den Auftrag ausführen
        switch (taskType) {
// --- INITIALISIERUNG EINER NEUEN LIGA ---
          case 'FETCH_TEAMS':
            await apiService.fetchAndStoreTeams(tId, sId);
            break;

        // HIER IST DER NEUE CASE:
          case 'FETCH_TEAM_SQUAD':
            int teamId = task['team_id'];
            await apiService.fetchAndStoreSingleSquad(teamId, sId);
            break;

          case 'FETCH_ROUNDS':
            await apiService.fetchAndStoreSpieltage(tId, sId);
            break;
          case 'FETCH_MATCHES':
            List<int> spieltage = await supabaseService.fetchAllSpieltagIds(sId);
            for (var spieltag in spieltage) {
              await apiService.fetchAndStoreSpiele(tId, sId, spieltag);
              await Future.delayed(const Duration(milliseconds: 300));
            }
            break;

          case 'UPDATE_MATCH':
            int matchId = task['match_id'];
            String neuerStatus = await getSpielStatus(matchId);

            // 1. Spiel-Ergebnis updaten
            await apiService.updateSpielData(sId, matchId, neuerStatus);

            // 2. Teams ermitteln
            final spielResponse = await _supabase.from('spiel')
                .select('heimteam_id, auswärtsteam_id')
                .eq('id', matchId)
                .single();

            int heimId = spielResponse['heimteam_id'];
            int auswId = spielResponse['auswärtsteam_id'];

            // 3. Aufstellung & Ratings laden
            await apiService.fetchAndStoreSpielerundMatchratings(matchId, heimId, auswId, sId);
            break;

          case 'UPDATE_SCHEDULE':
            await apiService.fetchAndStoreSpieltage(tId, sId);
            List<int> offeneSpieltage = await supabaseService.fetchUnfinishedSpieltage(sId);
            for (var spieltag in offeneSpieltage) {
              await apiService.fetchAndStoreSpiele(tId, sId, spieltag);
              await Future.delayed(const Duration(milliseconds: 300));
            }
            break;

          case 'SYNC_TRANSFERS':
            final teamResp = await _supabase.from('season_teams').select('team_id').eq('season_id', sId);
            final List<dynamic> teams = teamResp as List<dynamic>;
            for (var row in teams) {
              await apiService.fetchAndProcessTransfers(row['team_id'], sId);
              await Future.delayed(const Duration(milliseconds: 500));
            }
            break;

          case 'REPAIR_PLAYERS':
            await apiService.fixIncompletePlayers(sId);
            break;

          default:
            print('⚠️ Unbekannter Task-Typ: $taskType');
            break;
        }

        // 3. Task erfolgreich abschließen
        await _supabase.rpc('complete_sync_task', params: {'p_task_id': taskId});
        print('✅ WORKER: Aufgabe [$taskType] erfolgreich beendet!');
        return true;

      } catch (e) {
        print('❌ WORKER Fehler bei [$taskType]: $e');

        await _supabase.rpc('fail_sync_task', params: {
          'p_task_id': taskId,
          'p_error': e.toString()
        });

        if (e.toString().contains('API_LIMIT_REACHED')) {
          print('🛑 API-Limit erreicht. Aktiviere lokale Sperre.');
          await _setLocalApiBan(const Duration(minutes: 30));
        }
        return false;
      }
    } catch (e) {
      print('❌ Fehler beim Abholen von Tasks: $e');
      return false;
    }
  }

  /// ------------------------------------------------------------------
  /// HILFSMETHODEN
  /// ------------------------------------------------------------------

  /// Prüft, ob das Gerät gerade wegen zu vieler Anfragen pausieren muss
  Future<bool> _isDeviceBanned() async {
    final prefs = await SharedPreferences.getInstance();
    final banTimestamp = prefs.getInt('api_ban_until');

    if (banTimestamp == null) return false;

    final banUntil = DateTime.fromMillisecondsSinceEpoch(banTimestamp);
    final now = DateTime.now();

    if (now.isBefore(banUntil)) {
      return true;
    } else {
      await prefs.remove('api_ban_until');
      return false;
    }
  }

  Future<void> _setLocalApiBan(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    final banUntil = DateTime.now().add(duration).millisecondsSinceEpoch;
    await prefs.setInt('api_ban_until', banUntil);
  }

  Future<String> getSpielStatus(spielId) async {
    String spielstatus;
    DateTime spielDatum = await supabaseService.fetchSpieldatum(spielId);
    DateTime jetzt = DateTime.now();
    Duration differenz = jetzt.difference(spielDatum);

    if (differenz.inHours <= 0) {
      spielstatus = 'nicht gestartet';
    } else if (differenz.inHours < 2) {
      spielstatus = 'läuft';
    } else if (differenz.inHours < 24) {
      spielstatus = 'beendet';
    } else {
      spielstatus = 'final';
    }
    return spielstatus;
  }

  Future<void> updateRatingsForSingleGame(int spielId, String? currentStatus) async {
    print('👆 Anforderung: Update für Spiel $spielId (Status: $currentStatus)');

    if (await _isDeviceBanned()) {
      print('📵 Update blockiert: Gerät hat API-Sperre.');
      return;
    }

    final normalizedStatus = (currentStatus ?? '').trim().toLowerCase();
    if (normalizedStatus == 'final' || normalizedStatus == 'finished') {
      print('⏭️ Update übersprungen: Spiel $spielId ist bereits final.');
      return;
    }
    String neuerStatus = await getSpielStatus(spielId);
    if (neuerStatus == 'nicht gestartet') {
      return;
    }

    try {
      final spielResponse = await _supabase
          .from('spiel')
          .select('heimteam_id, auswärtsteam_id')
          .eq('id', spielId)
          .single();

      final hometeamId = spielResponse['heimteam_id'];
      final awayteamId = spielResponse['auswärtsteam_id'];

      if (hometeamId == null || awayteamId == null) return;

      await apiService.updateSpielData(seasonId, spielId, neuerStatus);
      await apiService.fetchAndStoreSpielerundMatchratings(
        spielId, hometeamId, awayteamId, seasonId,
      );
      print('✅ Manuelles Update für Spiel $spielId fertig.');
    } catch (e) {
      if (e.toString().contains('API_LIMIT_REACHED')) {
        await _setLocalApiBan(const Duration(minutes: 30));
      }
    }
  }

}
