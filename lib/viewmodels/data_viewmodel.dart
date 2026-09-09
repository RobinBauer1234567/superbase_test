import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:premier_league/data_service.dart';
import 'package:premier_league/services/client_sync_task_worker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// App-wide data coordinator.
///
/// Existing screens retain their season interface; imports use queue season IDs.
class DataManagement extends ChangeNotifier with WidgetsBindingObserver {
  DataManagement({int? seasonId}) : _seasonId = seasonId {
    _syncWorker = ClientSyncTaskWorker();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = _supabase.auth.onAuthStateChange.listen(
      (_) => _updateWorker(),
    );
  }

  final SupabaseClient _supabase = Supabase.instance.client;
  final ApiService apiService = ApiService();
  final SupabaseService supabaseService = SupabaseService();

  late final ClientSyncTaskWorker _syncWorker;
  int? _seasonId;
  StreamSubscription<AuthState>? _authSubscription;
  bool _foreground = true;
  bool _requested = false;
  void _updateWorker() {
    if (_requested && _foreground && _supabase.auth.currentUser != null) {
      _syncWorker.start();
    } else {
      _syncWorker.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _updateWorker();
  }

  /// Fallback preserves startup compatibility until tournaments have loaded.
  int get seasonId => _seasonId ?? 76986;

  void setSelectedSeason(int? value) {
    if (value == null || value == _seasonId) return;
    _seasonId = value;
  }

  void startAutoSync() {
    _requested = true;
    _updateWorker();
  }

  void stopAutoSync() {
    _requested = false;
    _updateWorker();
  }

  Future<bool> processNextSyncTask() => _syncWorker.processNextTask();

  /// Backwards-compatible alias used by older call sites.
  Future<void> updateData() async {
    await processNextSyncTask();
  }

  /// Enqueues initialization for the currently selected season when needed.
  /// Normal initialization should still be started by activating the season;
  /// this method only keeps historical call sites functional.
  Future<void> collectNewData() async {
    await _supabase.rpc(
      'request_season_sync',
      params: {'p_season_id': seasonId},
    );
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
    await _supabase.rpc('request_match_sync', params: {'p_match_id': spielId});
  }

  @override
  void dispose() {
    _syncWorker.stop();
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
