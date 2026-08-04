import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:premier_league/data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Temporary authenticated client worker for the database-backed sync queue.
///
/// The database remains the source of truth for task ordering and dependencies.
/// This worker only claims one task at a time, performs the external SofaScore
/// request, and reports completion or failure through ownership-checked RPCs.
class ClientSyncTaskWorker {
  ClientSyncTaskWorker({
    SupabaseClient? supabase,
    ApiService? apiService,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _apiService = apiService ?? ApiService();

  static const String _apiBaseUrl = 'https://www.sofascore.com/api/v1';
  static const Duration _busyDelay = Duration(seconds: 2);
  static const Duration _idleDelay = Duration(seconds: 20);
  static const Duration _requestDelay = Duration(milliseconds: 350);
  static const Duration _apiBanDuration = Duration(minutes: 30);
  static const String _banPreferenceKey = 'api_ban_until';

  final SupabaseClient _supabase;
  final ApiService _apiService;

  bool _isRunning = false;
  Future<void>? _loopFuture;

  final Map<String, String> _headers = const <String, String>{
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 '
        'Mobile/15E148 Safari/604.1',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7',
    'Origin': 'https://www.sofascore.com',
    'Referer': 'https://www.sofascore.com/',
  };

  bool get isRunning => _isRunning;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _loopFuture = _runLoop();
  }

  void stop() {
    _isRunning = false;
  }

  Future<void> waitUntilStopped() async {
    await _loopFuture;
  }

  Future<void> _runLoop() async {
    while (_isRunning) {
      bool didWork = false;
      try {
        didWork = await processNextTask();
      } catch (error, stackTrace) {
        print('Client-Sync-Worker: unerwarteter Fehler: $error');
        print(stackTrace);
      }

      if (!_isRunning) break;
      await Future<void>.delayed(didWork ? _busyDelay : _idleDelay);
    }
  }

  Future<bool> processNextTask() async {
    final user = _supabase.auth.currentUser;
    if (user == null || await _isDeviceBanned()) return false;

    Map<String, dynamic>? task;
    try {
      final response = await _supabase.rpc(
        'get_next_sync_task',
        params: <String, dynamic>{'p_user_id': user.id},
      );
      if (response is! List || response.isEmpty) return false;
      task = Map<String, dynamic>.from(response.first as Map);
    } catch (error) {
      print('Client-Sync-Worker: Task konnte nicht beansprucht werden: $error');
      return false;
    }

    final taskId = task['id']?.toString();
    final taskType = task['task_type']?.toString().toUpperCase();
    if (taskId == null || taskType == null) return false;

    try {
      await _executeTask(taskType, task);
      await _supabase.rpc(
        'complete_sync_task',
        params: <String, dynamic>{'p_task_id': taskId},
      );
      print('Client-Sync-Worker: $taskType abgeschlossen.');
      return true;
    } catch (error, stackTrace) {
      print('Client-Sync-Worker: $taskType fehlgeschlagen: $error');
      print(stackTrace);

      try {
        await _supabase.rpc(
          'fail_sync_task',
          params: <String, dynamic>{
            'p_task_id': taskId,
            'p_error': _truncateError(error.toString()),
          },
        );
      } catch (reportError) {
        print('Client-Sync-Worker: Fehlerstatus konnte nicht gespeichert werden: '
            '$reportError');
      }

      if (error is _ApiLimitException ||
          error.toString().contains('API_LIMIT_REACHED')) {
        await _setLocalApiBan(_apiBanDuration);
      }
      return false;
    }
  }

  Future<void> _executeTask(
    String taskType,
    Map<String, dynamic> task,
  ) async {
    final tournamentId = _requiredInt(task, 'tournament_id');
    final seasonId = _requiredInt(task, 'season_id');

    switch (taskType) {
      case 'FETCH_TEAMS':
        await _fetchAndStoreTeams(tournamentId, seasonId);
        return;
      case 'FETCH_TEAM_SQUAD':
        await _fetchAndStoreSingleSquad(
          _requiredInt(task, 'team_id'),
          seasonId,
        );
        return;
      case 'FETCH_SQUADS':
        await _fetchAndStoreAllSquads(seasonId);
        return;
      case 'FETCH_ROUNDS':
        await _fetchAndStoreRounds(tournamentId, seasonId);
        return;
      case 'FETCH_MATCHES':
        await _fetchAndStoreAllMatches(tournamentId, seasonId);
        return;
      case 'UPDATE_SCHEDULE':
        await _updateSchedule(tournamentId, seasonId);
        return;
      case 'UPDATE_MATCH':
        await _updateMatch(
          _requiredInt(task, 'match_id'),
          seasonId,
        );
        return;
      case 'SYNC_TRANSFERS':
        await _syncTransfers(seasonId);
        return;
      case 'REPAIR_PLAYERS':
        await _apiService.fixIncompletePlayers(seasonId);
        return;
      default:
        throw UnsupportedError('Unbekannter sync_tasks-Typ: $taskType');
    }
  }

  Future<void> _fetchAndStoreTeams(int tournamentId, int seasonId) async {
    final response = await _getJson(
      '$_apiBaseUrl/unique-tournament/$tournamentId/season/$seasonId/teams',
    );
    final teams = response['teams'] as List<dynamic>? ?? const <dynamic>[];

    for (final rawTeam in teams) {
      if (rawTeam is! Map || rawTeam['id'] == null) continue;
      final team = Map<String, dynamic>.from(rawTeam);
      final teamId = (team['id'] as num).toInt();
      final teamName = team['name']?.toString() ?? 'Team $teamId';
      final imageUrl = await _downloadAndStoreImage(
        url: '$_apiBaseUrl/team/$teamId/image',
        bucket: 'wappen',
        path: 'wappen/$teamId.jpg',
      );

      final teamData = <String, dynamic>{
        'id': teamId,
        'name': teamName,
      };
      if (imageUrl != null) teamData['image_url'] = imageUrl;

      await _supabase.from('team').upsert(teamData, onConflict: 'id');
      await _supabase.from('season_teams').upsert(
        <String, dynamic>{'season_id': seasonId, 'team_id': teamId},
        onConflict: 'season_id,team_id',
      );
    }
  }

  Future<void> _fetchAndStoreAllSquads(int seasonId) async {
    final rows = await _supabase
        .from('season_teams')
        .select('team_id')
        .eq('season_id', seasonId);

    for (final row in rows) {
      final teamId = (row['team_id'] as num).toInt();
      await _fetchAndStoreSingleSquad(teamId, seasonId);
    }
  }

  Future<void> _fetchAndStoreSingleSquad(int teamId, int seasonId) async {
    final response = await _getJson('$_apiBaseUrl/team/$teamId/players');
    final players = response['players'] as List<dynamic>? ?? const <dynamic>[];

    // Deliberately sequential. A single mobile client should not fan out dozens
    // of SofaScore calls and accidentally trip the shared rate limit.
    for (final rawEntry in players) {
      if (rawEntry is! Map || rawEntry['player'] is! Map) continue;
      final player = Map<String, dynamic>.from(rawEntry['player'] as Map);
      await _processSquadPlayer(player, teamId, seasonId);
    }
  }

  Future<void> _processSquadPlayer(
    Map<String, dynamic> player,
    int teamId,
    int seasonId,
  ) async {
    final playerId = (player['id'] as num?)?.toInt();
    if (playerId == null) return;

    final playerName = player['name']?.toString() ?? 'Spieler $playerId';
    final initialPosition = _mapPosition(player['position']?.toString());

    await _supabase.from('spieler').upsert(
      <String, dynamic>{
        'id': playerId,
        'name': playerName,
        'position': initialPosition,
        'is_active': true,
      },
      onConflict: 'id',
    );

    await _supabase.from('season_players').upsert(
      <String, dynamic>{
        'season_id': seasonId,
        'player_id': playerId,
        'team_id': teamId,
        'is_active': true,
      },
      onConflict: 'season_id,player_id,team_id',
    );

    final analytics = await _supabase
        .from('spieler_analytics')
        .select('marktwert')
        .eq('spieler_id', playerId)
        .eq('season_id', seasonId)
        .maybeSingle();

    if (analytics == null || analytics['marktwert'] == null) {
      await _apiService.initializePlayerInDB(playerId, seasonId);
    }

    final existingPlayer = await _supabase
        .from('spieler')
        .select('profilbild_url')
        .eq('id', playerId)
        .maybeSingle();

    if ((existingPlayer?['profilbild_url']?.toString() ?? '').isEmpty) {
      final imageUrl = await _downloadAndStoreImage(
        url: '$_apiBaseUrl/player/$playerId/image',
        bucket: 'spielerbilder',
        path: 'spielerbilder/$playerId.jpg',
      );
      if (imageUrl != null) {
        await _supabase
            .from('spieler')
            .update(<String, dynamic>{'profilbild_url': imageUrl})
            .eq('id', playerId);
      }
    }
  }

  Future<void> _fetchAndStoreRounds(int tournamentId, int seasonId) async {
    final response = await _getJson(
      '$_apiBaseUrl/unique-tournament/$tournamentId/season/$seasonId/rounds',
    );
    final rounds = response['rounds'] as List<dynamic>? ?? const <dynamic>[];

    for (final rawRound in rounds) {
      if (rawRound is! Map) continue;
      final round = int.tryParse(rawRound['round']?.toString() ?? '');
      if (round == null || round <= 0) continue;
      await _supabase.from('spieltag').upsert(
        <String, dynamic>{
          'round': round,
          'status': 'nicht gestartet',
          'season_id': seasonId,
        },
        onConflict: 'round,season_id',
      );
    }
  }

  Future<void> _fetchAndStoreAllMatches(
    int tournamentId,
    int seasonId,
  ) async {
    final rounds = await _fetchRoundNumbers(seasonId, unfinishedOnly: false);
    for (final round in rounds) {
      await _fetchAndStoreMatchesForRound(tournamentId, seasonId, round);
    }
  }

  Future<void> _updateSchedule(int tournamentId, int seasonId) async {
    final rounds = await _fetchRoundNumbers(seasonId, unfinishedOnly: true);
    for (final round in rounds) {
      await _fetchAndStoreMatchesForRound(tournamentId, seasonId, round);
    }
  }

  Future<List<int>> _fetchRoundNumbers(
    int seasonId, {
    required bool unfinishedOnly,
  }) async {
    var query = _supabase
        .from('spieltag')
        .select('round')
        .eq('season_id', seasonId);
    if (unfinishedOnly) query = query.neq('status', 'final');
    final rows = await query.order('round');
    return rows
        .map<int>((row) => (row['round'] as num).toInt())
        .toList(growable: false);
  }

  Future<void> _fetchAndStoreMatchesForRound(
    int tournamentId,
    int seasonId,
    int round,
  ) async {
    final response = await _getJson(
      '$_apiBaseUrl/unique-tournament/$tournamentId/season/$seasonId/'
      'events/round/$round',
    );
    final events = response['events'] as List<dynamic>? ?? const <dynamic>[];

    for (final rawEvent in events) {
      if (rawEvent is! Map || rawEvent['id'] == null) continue;
      final event = Map<String, dynamic>.from(rawEvent);
      final homeTeam = event['homeTeam'];
      final awayTeam = event['awayTeam'];
      if (homeTeam is! Map || awayTeam is! Map) continue;

      final matchId = (event['id'] as num).toInt();
      final homeTeamId = (homeTeam['id'] as num).toInt();
      final awayTeamId = (awayTeam['id'] as num).toInt();
      final startTimestamp = (event['startTimestamp'] as num).toInt();
      final date = DateTime.fromMillisecondsSinceEpoch(
        startTimestamp * 1000,
        isUtc: true,
      ).toIso8601String();
      final status =
          (event['status'] is Map
                  ? (event['status'] as Map)['description']
                  : null)
              ?.toString() ??
          'nicht gestartet';
      final homeScore = event['homeScore'] is Map
          ? (event['homeScore'] as Map)['current']
          : null;
      final awayScore = event['awayScore'] is Map
          ? (event['awayScore'] as Map)['current']
          : null;
      final result = homeScore == null || awayScore == null
          ? 'Noch kein Ergebnis'
          : '$homeScore:$awayScore';

      await _supabase.from('spiel').upsert(
        <String, dynamic>{
          'id': matchId,
          'datum': date,
          'heimteam_id': homeTeamId,
          'auswärtsteam_id': awayTeamId,
          'ergebnis': result,
          'status': status,
          'round': round,
          'season_id': seasonId,
        },
        onConflict: 'id',
      );
    }
  }

  Future<void> _updateMatch(int matchId, int seasonId) async {
    final status = await _getMatchStatus(matchId);
    await _apiService.updateSpielData(seasonId, matchId, status);

    final match = await _supabase
        .from('spiel')
        .select('heimteam_id, auswärtsteam_id')
        .eq('id', matchId)
        .single();
    final homeTeamId = (match['heimteam_id'] as num).toInt();
    final awayTeamId = (match['auswärtsteam_id'] as num).toInt();

    if (status != 'nicht gestartet') {
      await _apiService.fetchAndStoreSpielerundMatchratings(
        matchId,
        homeTeamId,
        awayTeamId,
        seasonId,
      );
    }
  }

  Future<String> _getMatchStatus(int matchId) async {
    final row = await _supabase
        .from('spiel')
        .select('datum')
        .eq('id', matchId)
        .single();
    final date = DateTime.parse(row['datum'].toString()).toUtc();
    final difference = DateTime.now().toUtc().difference(date);
    if (difference.isNegative) return 'nicht gestartet';
    if (difference < const Duration(hours: 2)) return 'läuft';
    if (difference < const Duration(hours: 24)) return 'beendet';
    return 'final';
  }

  Future<void> _syncTransfers(int seasonId) async {
    final teams = await _supabase
        .from('season_teams')
        .select('team_id')
        .eq('season_id', seasonId);
    for (final row in teams) {
      await _fetchAndProcessTransfers(
        (row['team_id'] as num).toInt(),
        seasonId,
      );
    }
  }

  Future<void> _fetchAndProcessTransfers(int teamId, int seasonId) async {
    final response = await _getJson('$_apiBaseUrl/team/$teamId/transfers');
    final transfers = <dynamic>[
      ...(response['transfersIn'] as List<dynamic>? ?? const <dynamic>[]),
      ...(response['transfersOut'] as List<dynamic>? ?? const <dynamic>[]),
    ];

    for (final rawTransfer in transfers) {
      if (rawTransfer is! Map || rawTransfer['id'] == null) continue;
      final transfer = Map<String, dynamic>.from(rawTransfer);
      final player = transfer['player'];
      if (player is! Map || player['id'] == null) continue;

      await _supabase.rpc(
        'process_transfer_event',
        params: <String, dynamic>{
          'p_transfer_id': (transfer['id'] as num).toInt(),
          'p_player_id': (player['id'] as num).toInt(),
          'p_from_team_id': _nullableNestedId(transfer['transferFrom']),
          'p_to_team_id': _nullableNestedId(transfer['transferTo']),
          'p_season_id': seasonId,
        },
      );
    }
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final response = await _throttledGet(url);
    if (response.statusCode != 200) {
      throw http.ClientException(
        'SofaScore antwortete für $url mit HTTP ${response.statusCode}.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Unerwartetes SofaScore-Antwortformat.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<http.Response> _throttledGet(String url) async {
    await Future<void>.delayed(_requestDelay);

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http.get(Uri.parse(url), headers: _headers);
        if (response.statusCode == 403 || response.statusCode == 429) {
          throw _ApiLimitException(response.statusCode, url);
        }
        return response;
      } catch (error) {
        if (error is _ApiLimitException) rethrow;
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
    throw http.ClientException('Netzwerkfehler für $url: $lastError');
  }

  Future<String?> _downloadAndStoreImage({
    required String url,
    required String bucket,
    required String path,
  }) async {
    try {
      final response = await _throttledGet(url);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      await _supabase.storage.from(bucket).uploadBinary(
        path,
        response.bodyBytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );
      return _supabase.storage.from(bucket).getPublicUrl(path);
    } on _ApiLimitException {
      rethrow;
    } catch (error) {
      print('Bild konnte nicht gespeichert werden ($path): $error');
      return null;
    }
  }

  int _requiredInt(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      throw FormatException('Task enthält keine gültige $key.');
    }
    return parsed;
  }

  int? _nullableNestedId(dynamic value) {
    if (value is! Map || value['id'] == null) return null;
    final id = value['id'];
    return id is num ? id.toInt() : int.tryParse(id.toString());
  }

  String _mapPosition(String? rawPosition) {
    switch (rawPosition) {
      case 'G':
        return 'TW';
      case 'D':
        return 'IV';
      case 'M':
        return 'ZM';
      case 'F':
        return 'ST';
      default:
        return 'N/V';
    }
  }

  String _truncateError(String error) {
    return error.length <= 1500 ? error : error.substring(0, 1500);
  }

  Future<bool> _isDeviceBanned() async {
    final preferences = await SharedPreferences.getInstance();
    final timestamp = preferences.getInt(_banPreferenceKey);
    if (timestamp == null) return false;

    final banUntil = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (DateTime.now().isBefore(banUntil)) return true;
    await preferences.remove(_banPreferenceKey);
    return false;
  }

  Future<void> _setLocalApiBan(Duration duration) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(
      _banPreferenceKey,
      DateTime.now().add(duration).millisecondsSinceEpoch,
    );
  }
}

class _ApiLimitException implements Exception {
  const _ApiLimitException(this.statusCode, this.url);

  final int statusCode;
  final String url;

  @override
  String toString() =>
      'API_LIMIT_REACHED: SofaScore HTTP $statusCode für $url';
}
