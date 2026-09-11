import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/utils/season_order.dart';

class TournamentViewModel extends ChangeNotifier {
  final Future<List<Map<String, dynamic>>> Function() _load;
  List<Map<String, dynamic>> allTournaments = [];
  Map<String, dynamic>? selectedTournament;
  Map<String, dynamic>? selectedSeason;
  final Map<int, int> _explicitSelections = {};
  bool isLoading = true;
  String? error;
  int _request = 0;
  bool _disposed = false;

  TournamentViewModel({
    Future<List<Map<String, dynamic>>> Function()? load,
    bool autoLoad = true,
  }) : _load = load ?? _loadFromDatabase {
    if (autoLoad) fetchTournaments();
  }

  static Future<List<Map<String, dynamic>>> _loadFromDatabase() async =>
      List<Map<String, dynamic>>.from(
        await Supabase.instance.client
            .from('tournaments')
            .select('*, season(*)')
            .order('name')
            .order('id'),
      );

  Future<void> fetchTournaments() async {
    final request = ++_request;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final rows = await _load();
      if (_disposed || request != _request) return;
      final previousId = currentTournamentId;
      allTournaments =
          rows.map((t) => {...t, 'season': sortedSeasons(t['season'])}).toList()
            ..sort((a, b) {
              final byName = (a['name'] as String).compareTo(
                b['name'] as String,
              );
              return byName != 0
                  ? byName
                  : (a['id'] as int).compareTo(b['id'] as int);
            });
      selectedTournament = null;
      selectedSeason = null;
      if (allTournaments.isNotEmpty) {
        final tournament = allTournaments.firstWhere(
          (t) => t['id'] == previousId,
          orElse:
              () => allTournaments.firstWhere(
                (t) => sortedSeasons(
                  t['season'],
                ).any((s) => s['is_active'] == true),
                orElse: () => allTournaments.first,
              ),
        );
        _select(tournament);
      }
    } catch (e) {
      if (_disposed || request != _request) return;
      error = 'Turniere konnten nicht geladen werden: $e';
    }
    if (_disposed || request != _request) return;
    isLoading = false;
    notifyListeners();
  }

  void _select(Map<String, dynamic> tournament) {
    selectedTournament = tournament;
    final seasons = sortedSeasons(tournament['season']);
    selectedSeason =
        seasons.isEmpty
            ? null
            : seasons.firstWhere(
              (s) => s['id'] == _explicitSelections[tournament['id']],
              orElse:
                  () => seasons.firstWhere(
                    (s) => s['is_active'] == true,
                    orElse: () => seasons.first,
                  ),
            );
  }

  void selectTournament(int tournamentId, int seasonId) {
    final tournament = allTournaments.firstWhere(
      (t) => t['id'] == tournamentId,
    );
    if (!sortedSeasons(tournament['season']).any((s) => s['id'] == seasonId)) {
      throw ArgumentError('Saison gehört nicht zu diesem Turnier');
    }
    _explicitSelections[tournamentId] = seasonId;
    _select(tournament);
    notifyListeners();
  }

  List<Map<String, dynamic>> get seasons =>
      sortedSeasons(selectedTournament?['season']);
  Map<String, dynamic>? get activeSeason {
    for (final season in seasons) {
      if (season['is_active'] == true) return season;
    }
    return null;
  }

  int? get leagueCreationSeasonId =>
      activeSeason?['is_initialized'] == true
          ? activeSeason!['id'] as int
          : null;
  int? get currentTournamentId => selectedTournament?['id'];
  int? get currentSeasonId => selectedSeason?['id'];
  String get currentTournamentName => selectedTournament?['name'] ?? 'Turniere';
  String get currentSeasonName => selectedSeason?['name'] ?? 'Keine Saison';
  String get currentSeasonLabel =>
      '$currentTournamentName – Saison $currentSeasonName';
  String? get currentTournamentLogo => selectedTournament?['image_url'];
  bool get isCurrentActive => selectedSeason?['is_active'] == true;
  bool get isCurrentInitialized => selectedSeason?['is_initialized'] == true;

  static String seasonStatus(Map<String, dynamic> season) => [
    if (season['is_active'] == true)
      'aktuell · aktiv'
    else if (season['archived_at'] != null)
      'archiviert'
    else
      'inaktiv',
    season['is_initialized'] == true ? 'initialisiert' : 'nicht initialisiert',
  ].join(' · ');

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
