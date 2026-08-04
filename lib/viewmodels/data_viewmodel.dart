import 'package:flutter/foundation.dart';
import 'package:premier_league/data_service.dart';
import 'package:premier_league/services/client_sync_task_worker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// App-wide data coordinator.
///
/// The selected season is supplied by TournamentViewModel through the root
/// proxy provider. Existing screens can keep reading seasonId, while the value
/// now follows the tournament selected by the user.
class DataManagement extends ChangeNotifier {
  DataManagement({int? seasonId}) : _seasonId = seasonId {
    _syncWorker = ClientSyncTaskWorker(apiService: apiService);
  }

  final SupabaseClient _supabase = Supabase.instance.client;
  final ApiService apiService = ApiService();
  final SupabaseService supabaseService = SupabaseService();

  late final ClientSyncTaskWorker _syncWorker;
  int? _seasonId;

  /// Fallback preserves startup compatibility until tournaments have loaded.
  int get seasonId => _seasonId ?? 76986;

  void setSelectedSeason(int? value) {
    if (value == null || value == _seasonId) return;
    _seasonId = value;
  }

  void startAutoSync() => _syncWorker.start();

  void stopAutoSync() => _syncWorker.stop();

  Future<bool> processNextSyncTask() => _syncWorker.processNextTask();

  /// Backwards-compatible alias used by older call sites.
  Future<void> updateData() async {
    await processNextSyncTask();
  }

  /// Enqueues initialization for the currently selected season when needed.
  /// Normal initialization should still be started by activating the season;
  /// this method only keeps historical call sites functional.
  Future<void> collectNewData() async {
    final selectedSeasonId = seasonId;
    final season = await _supabase
        .from('season')
        .select('id, tournament_id, is_active, is_initialized')
        .eq('id', selectedSeasonId)
        .single();

    if (season['is_initialized'] == true) return;
    if (season['is_active'] != true) {
      await _supabase
          .from('season')
          .update(<String, dynamic>{'is_active': true})
          .eq('id', selectedSeasonId);
      return;
    }

    final existingTask = await _supabase
        .from('sync_tasks')
        .select('id')
        .eq('season_id', selectedSeasonId)
        .limit(1)
        .maybeSingle();
    if (existingTask != null) return;

    await _supabase.from('sync_tasks').insert(<String, dynamic>{
      'task_type': 'FETCH_TEAMS',
      'tournament_id': season['tournament_id'],
      'season_id': selectedSeasonId,
      'priority': 10,
      'status': 'PENDING',
    });
  }

  Future<String> getSpielStatus(int spielId) async {
    final date = await supabaseService.fetchSpieldatum(spielId);
    final difference = DateTime.now().toUtc().difference(date.toUtc());
    if (difference.isNegative) return 'nicht gestartet';
    if (difference < const Duration(hours: 2)) return 'läuft';
    if (difference < const Duration(hours: 24)) return 'beendet';
    return 'final';
  }

  Future<void> updateRatingsForSingleGame(
    int spielId,
    String? currentStatus, [
    int? explicitSeasonId,
  ]) async {
    final normalizedStatus = (currentStatus ?? '').trim().toLowerCase();
    if (normalizedStatus == 'final' || normalizedStatus == 'finished') return;

    final newStatus = await getSpielStatus(spielId);
    if (newStatus == 'nicht gestartet') return;

    final match = await _supabase
        .from('spiel')
        .select('season_id, heimteam_id, auswärtsteam_id')
        .eq('id', spielId)
        .single();
    final targetSeasonId = explicitSeasonId ??
        (match['season_id'] as num?)?.toInt() ??
        seasonId;
    final homeTeamId = (match['heimteam_id'] as num?)?.toInt();
    final awayTeamId = (match['auswärtsteam_id'] as num?)?.toInt();
    if (homeTeamId == null || awayTeamId == null) return;

    await apiService.updateSpielData(targetSeasonId, spielId, newStatus);
    await apiService.fetchAndStoreSpielerundMatchratings(
      spielId,
      homeTeamId,
      awayTeamId,
      targetSeasonId,
    );
  }

  @override
  void dispose() {
    _syncWorker.stop();
    super.dispose();
  }
}
