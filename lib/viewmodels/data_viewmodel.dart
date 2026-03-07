// lib/viewmodels/data_viewmodel.dart
import 'dart:convert';
import 'package:pool/pool.dart';
import 'package:premier_league/data_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math'; // <-- Wichtig für Random()

class DataManagement {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ApiService apiService = ApiService();
  final SupabaseService supabaseService = SupabaseService();
  final int seasonId;

  DataManagement({required this.seasonId});
// Steuerungsvariable, um die Schleife an- und auszuschalten
  bool _isAutoSyncRunning = false;

  /// Startet die automatische Update-Schleife
  void startAutoSync() async {
    // Verhindert, dass aus Versehen zwei Schleifen gleichzeitig laufen
    if (_isAutoSyncRunning) return;
    _isAutoSyncRunning = true;

    print('🔄 🟢 Auto-Sync Schleife gestartet.');

    while (_isAutoSyncRunning) {
      // 1. Das Update durchführen
      await updateData();

      final int syncLockMinutes = 2;

      final int randomSeconds = Random().nextInt(121);

      // Gesamte Wartezeit zusammensetzen
      final Duration waitTime = Duration(
          minutes: syncLockMinutes,
          seconds: randomSeconds
      );

      print('⏳ Auto-Sync schläft jetzt für ${waitTime.inMinutes} Min und ${waitTime.inSeconds % 60} Sek...');

      // 3. Warten (Diese Zeile pausiert NUR diese Schleife, die App läuft normal weiter!)
      await Future.delayed(waitTime);
    }
  }

  /// Stoppt die automatische Update-Schleife
  void stopAutoSync() {
    _isAutoSyncRunning = false;
    print('🛑 🔴 Auto-Sync Schleife gestoppt.');
  }

  Future<void> collectNewData() async {
    print('start: collectNewData for season $seasonId');

    // **ÄNDERUNG HIER:** Übergib die seasonId an fetchAndStoreTeams
    await apiService.fetchAndStoreTeams(seasonId.toString());
    print('Teams gespeichert');

    await apiService.fetchAndStoreSpieltage(seasonId.toString());
    print('Spieltage für Saison $seasonId gespeichert');

    List<int> spieltage = await supabaseService.fetchAllSpieltagIds(seasonId);
    await Future.wait(
      spieltage.map((spieltag) async {
        await apiService.fetchAndStoreSpiele(spieltag, seasonId.toString());
        print('Spiele für Spieltag $spieltag gespeichert');
      }),
    );

    await Future.delayed(const Duration(seconds: 5));
    await updateData();
    print('finish');
  }

  Future<void> updateData() async {
    print('🔍 Update-Check gestartet...');

    if (await _isDeviceBanned()) {
      print(
        '📵 LOKALE SPERRE: Dieses Gerät pausiert API-Anfragen wegen vorheriger Limits.',
      );
      return; // Hier brechen wir ab, ohne Server-Last zu erzeugen.
    }

    bool permissionGranted = await supabaseService.requestSyncPermission();
    if (!permissionGranted) {
      print('⏳ Kein Sync-Token erhalten (Globaler Lock).');
      return;
    }

    print('🚀 Sync-Token erhalten! Frage Datenbank nach Arbeit...');

    try {
      final bool needsScheduleUpdate = await _supabase.rpc(
        'check_schedule_update_needed',
        params: {'p_season_id': seasonId},
      );

      if (needsScheduleUpdate) {
        print('📅 Spielplan ist älter als 2 Tage. Starte Routine-Update...');
        // NEU: Wir holen NUR die Spieltage, die noch NICHT final sind!
        List<int> aktiveSpieltage = await supabaseService
            .fetchUnfinishedSpieltage(seasonId);

        print('🔍 Überprüfe ${aktiveSpieltage.length} offene Spieltage...');

        for (var spieltag in aktiveSpieltage) {
          await apiService.fetchAndStoreSpiele(spieltag, seasonId.toString());
          await Future.delayed(const Duration(milliseconds: 500));
        }
        checkAllTeamTransfers();
        await _supabase.rpc(
          'mark_schedule_updated',
          params: {'p_season_id': seasonId},
        );
        print('✅ Spielplan erfolgreich aktualisiert!');
      }

      final response = await _supabase.rpc(
        'get_pending_updates',
        params: {'p_season_id': seasonId},
      );

      final List<dynamic> pendingMatches = response as List<dynamic>;

      if (pendingMatches.isEmpty) {
        print('✅ Alles aktuell.');
        return;
      }

      print('📋 Auftrag: ${pendingMatches.length} Spiele.');

      // Pool auf 1 setzen (Wichtig für Sicherheit!)
      final pool = Pool(1);
      List<Future> updateFutures = [];

      for (var match in pendingMatches) {
        updateFutures.add(
          pool.withResource(() async {
            int spielId = match['id'];
            int homeId = match['heimteam_id'];
            int awayId = match['auswärtsteam_id'];

            String neuerStatus = await getSpielStatus(spielId);
            await apiService.updateSpielData(seasonId, spielId, neuerStatus);

            if (neuerStatus != 'nicht gestartet') {
              await apiService.fetchAndStoreSpielerundMatchratings(
                spielId,
                homeId,
                awayId,
                seasonId,
              );
            }
          }),
        );
      }

      await Future.wait(updateFutures);
      print('🏁 Update abgeschlossen.');

      await apiService.fixIncompletePlayers(seasonId);
    } catch (e) {
      if (e.toString().contains('API_LIMIT_REACHED')) {
        print('🛑 API-Limit erkannt! Aktiviere lokale Sperre für 30 Minuten.');
        await _setLocalApiBan(Duration(days: 1));
      } else {
        print('❌ Fehler beim Smart Update: $e');
      }
    }
  }

  Future<bool> _isDeviceBanned() async {
    final prefs = await SharedPreferences.getInstance();
    final banTimestamp = prefs.getInt('api_ban_until');

    if (banTimestamp == null) return false;

    final banUntil = DateTime.fromMillisecondsSinceEpoch(banTimestamp);
    final now = DateTime.now();

    if (now.isBefore(banUntil)) {
      final remaining = banUntil.difference(now);
      print('   -> Sperre aktiv für noch ${remaining.inMinutes} Minuten.');
      return true;
    } else {
      // Sperre ist abgelaufen, wir löschen sie
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

    // 1. LOKALE SPERRE PRÜFEN
    if (await _isDeviceBanned()) {
      print('📵 Update blockiert: Gerät hat API-Sperre.');
      return;
    }

    if (currentStatus == 'finished') return;
    String neuerStatus = await getSpielStatus(spielId);
    if (neuerStatus == 'nicht gestartet') {
      print('nicht gestartet');
      return;
    }

    try {
      final spielResponse =
          await _supabase
              .from('spiel')
              .select('heimteam_id, auswärtsteam_id')
              .eq('id', spielId)
              .single();

      final hometeamId = spielResponse['heimteam_id'];
      final awayteamId = spielResponse['auswärtsteam_id'];

      if (hometeamId == null || awayteamId == null) {
        print('Fehler: Team-IDs nicht gefunden.');
        return;
      }

      await apiService.updateSpielData(seasonId, spielId, neuerStatus);

      await apiService.fetchAndStoreSpielerundMatchratings(
        spielId,
        hometeamId,
        awayteamId,
        seasonId,
      );

      print('✅ Manuelles Update für Spiel $spielId fertig.');
    } catch (e) {
      // 4. FEHLER ABFANGEN & SPERREN
      if (e.toString().contains('API_LIMIT_REACHED')) {
        print('🛑 API-Limit beim manuellen Update! Aktiviere Sperre.');
        await _setLocalApiBan(const Duration(minutes: 30));
      } else {
        print('❌ Fehler beim manuellen Update: $e');
      }
    }
  }

  Future<void> checkAllTeamTransfers() async {
    print('🔄 Starte Transfer-Rundgang...');

    // Hole alle Teams, die zu dieser Saison gehören
    final response = await _supabase
        .from('season_teams')
        .select('team_id')
        .eq('season_id', seasonId);

    final List<dynamic> teams = response as List<dynamic>;

    for (var row in teams) {
      int teamId = row['team_id'];
      await apiService.fetchAndProcessTransfers(teamId, seasonId);
      // Kurze Pause, um die Sofascore API nicht zu triggern
      await Future.delayed(const Duration(milliseconds: 500));
    }

    print('✅ Transfer-Rundgang abgeschlossen.');
  }
}
