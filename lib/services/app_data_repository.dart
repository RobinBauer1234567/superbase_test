import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class _CacheEntry<T> {
  final T value;
  final DateTime createdAt;

  const _CacheEntry(this.value, this.createdAt);

  bool isFresh(Duration ttl) => DateTime.now().difference(createdAt) < ttl;
}

/// Central read repository for data that is reused across several screens.
///
/// The repository intentionally keeps the cache in memory only. This avoids stale
/// persisted state while still eliminating duplicate Supabase requests when users
/// switch between tabs repeatedly.
class AppDataRepository {
  AppDataRepository._();

  static final AppDataRepository instance = AppDataRepository._();

  final SupabaseClient _supabase = Supabase.instance.client;

  static const Duration _defaultTtl = Duration(seconds: 30);
  static const Duration _leagueTtl = Duration(seconds: 20);

  final Map<int, _CacheEntry<List<Map<String, dynamic>>>> _matchesBySeason = {};
  final Map<int, _CacheEntry<List<Map<String, dynamic>>>> _teamsBySeason = {};
  final Map<int, _CacheEntry<List<int>>> _ratedRoundsBySeason = {};
  final Map<String, _CacheEntry<List<Map<String, dynamic>>>> _topPlayers = {};

  _CacheEntry<List<Map<String, dynamic>>>? _leagues;
  _CacheEntry<String?>? _avatarUrl;

  Future<List<Map<String, dynamic>>> getUserLeagues({
    required Future<List<Map<String, dynamic>>> Function() loader,
    bool forceRefresh = false,
  }) async {
    final cached = _leagues;
    if (!forceRefresh && cached != null && cached.isFresh(_leagueTtl)) {
      return cached.value;
    }

    final value = await loader();
    _leagues = _CacheEntry(value, DateTime.now());
    return value;
  }

  Future<String?> getProfileAvatar({bool forceRefresh = false}) async {
    final cached = _avatarUrl;
    if (!forceRefresh && cached != null && cached.isFresh(_leagueTtl)) {
      return cached.value;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final profile = await _supabase
        .from('profiles')
        .select('avatar_url')
        .eq('user_id', user.id)
        .maybeSingle();
    final value = profile?['avatar_url'] as String?;
    _avatarUrl = _CacheEntry(value, DateTime.now());
    return value;
  }

  Future<List<Map<String, dynamic>>> getMatches(
    int seasonId, {
    bool forceRefresh = false,
  }) async {
    final cached = _matchesBySeason[seasonId];
    if (!forceRefresh && cached != null && cached.isFresh(_defaultTtl)) {
      return cached.value;
    }

    final data = await _supabase
        .from('spiel')
        .select(
          'id, datum, heimteam_id, auswärtsteam_id, ergebnis, status, round, season_id, '
          'heimteam:team!spiel_heimteam_id_fkey(id, name, image_url), '
          'auswaertsteam:team!spiel_auswärtsteam_id_fkey(id, name, image_url)',
        )
        .eq('season_id', seasonId)
        .order('datum', ascending: true);

    final value = List<Map<String, dynamic>>.from(data);
    _matchesBySeason[seasonId] = _CacheEntry(value, DateTime.now());
    return value;
  }

  /// Applies a Realtime row payload locally. Joined team objects are preserved from
  /// the cached row, so a score/status update does not trigger a full-season reload.
  /// Returns the updated cached list or null when no cache for the season exists.
  List<Map<String, dynamic>>? applyMatchChange(
    int seasonId,
    Map<String, dynamic> newRecord,
  ) {
    final cached = _matchesBySeason[seasonId];
    if (cached == null) return null;

    final id = newRecord['id'];
    if (id == null) return cached.value;

    final list = cached.value.map((row) => Map<String, dynamic>.from(row)).toList();
    final index = list.indexWhere((row) => row['id'] == id);

    if (index >= 0) {
      list[index] = <String, dynamic>{...list[index], ...newRecord};
    } else {
      // A newly inserted game does not contain joined team objects in the realtime
      // payload, therefore a targeted fetch is better than reloading the season.
      unawaited(_fetchAndMergeSingleMatch(seasonId, id));
      return cached.value;
    }

    list.sort((a, b) {
      final da = DateTime.tryParse(a['datum']?.toString() ?? '');
      final db = DateTime.tryParse(b['datum']?.toString() ?? '');
      if (da == null || db == null) return 0;
      return da.compareTo(db);
    });

    _matchesBySeason[seasonId] = _CacheEntry(list, DateTime.now());
    return list;
  }

  Future<List<Map<String, dynamic>>> _fetchAndMergeSingleMatch(
    int seasonId,
    dynamic matchId,
  ) async {
    final row = await _supabase
        .from('spiel')
        .select(
          'id, datum, heimteam_id, auswärtsteam_id, ergebnis, status, round, season_id, '
          'heimteam:team!spiel_heimteam_id_fkey(id, name, image_url), '
          'auswaertsteam:team!spiel_auswärtsteam_id_fkey(id, name, image_url)',
        )
        .eq('season_id', seasonId)
        .eq('id', matchId)
        .maybeSingle();

    final current = _matchesBySeason[seasonId]?.value ?? <Map<String, dynamic>>[];
    final list = current.map((e) => Map<String, dynamic>.from(e)).toList();
    if (row != null) {
      final index = list.indexWhere((e) => e['id'] == row['id']);
      if (index >= 0) {
        list[index] = Map<String, dynamic>.from(row);
      } else {
        list.add(Map<String, dynamic>.from(row));
      }
    }
    _matchesBySeason[seasonId] = _CacheEntry(list, DateTime.now());
    return list;
  }

  Future<List<Map<String, dynamic>>> getSeasonTeams(
    int seasonId, {
    bool forceRefresh = false,
  }) async {
    final cached = _teamsBySeason[seasonId];
    if (!forceRefresh && cached != null && cached.isFresh(_defaultTtl)) {
      return cached.value;
    }

    final rows = await _supabase
        .from('season_teams')
        .select('team:team(id, name, image_url)')
        .eq('season_id', seasonId);

    final value = <Map<String, dynamic>>[];
    for (final row in rows) {
      final team = row['team'];
      if (team is Map) value.add(Map<String, dynamic>.from(team));
    }
    value.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    _teamsBySeason[seasonId] = _CacheEntry(value, DateTime.now());
    return value;
  }

  Future<List<int>> getRatedRounds(
    int seasonId, {
    bool forceRefresh = false,
  }) async {
    final cached = _ratedRoundsBySeason[seasonId];
    if (!forceRefresh && cached != null && cached.isFresh(_defaultTtl)) {
      return cached.value;
    }

    final rows = await _supabase
        .from('spieltag')
        .select('round')
        .eq('season_id', seasonId)
        .neq('status', 'nicht gestartet');
    final value = rows.map<int>((row) => row['round'] as int).toList()..sort();
    _ratedRoundsBySeason[seasonId] = _CacheEntry(value, DateTime.now());
    return value;
  }

  Future<List<Map<String, dynamic>>> getTopPlayers({
    required int seasonId,
    int? teamId,
    String? position,
    int limit = 50,
    bool forceRefresh = false,
  }) async {
    final normalizedPosition = position?.trim();
    final key = '$seasonId:${teamId ?? 0}:${normalizedPosition ?? ''}:$limit';
    final cached = _topPlayers[key];
    if (!forceRefresh && cached != null && cached.isFresh(_defaultTtl)) {
      return cached.value;
    }

    final rows = await _supabase.rpc(
      'get_top_players',
      params: {
        'p_season_id': seasonId,
        'p_team_id': teamId,
        'p_position': normalizedPosition?.isEmpty == true ? null : normalizedPosition,
        'p_limit': limit,
      },
    );

    final value = List<Map<String, dynamic>>.from(rows as List);
    _topPlayers[key] = _CacheEntry(value, DateTime.now());
    return value;
  }

  Future<List<String>> getSeasonPositions(int seasonId) async {
    final rows = await _supabase
        .from('season_players')
        .select('spieler:spieler(position)')
        .eq('season_id', seasonId);
    final positions = <String>{};
    for (final row in rows) {
      final player = row['spieler'];
      final raw = player is Map ? player['position'] : null;
      if (raw == null) continue;
      for (final item in raw.toString().split(',')) {
        final value = item.trim();
        if (value.isNotEmpty) positions.add(value);
      }
    }
    return positions.toList()..sort();
  }

  void invalidateSeason(int seasonId) {
    _matchesBySeason.remove(seasonId);
    _teamsBySeason.remove(seasonId);
    _ratedRoundsBySeason.remove(seasonId);
    _topPlayers.removeWhere((key, _) => key.startsWith('$seasonId:'));
  }

  void invalidateLeagues() {
    _leagues = null;
  }

  void invalidateProfile() {
    _avatarUrl = null;
  }

  void clear() {
    _matchesBySeason.clear();
    _teamsBySeason.clear();
    _ratedRoundsBySeason.clear();
    _topPlayers.clear();
    _leagues = null;
    _avatarUrl = null;
  }
}
