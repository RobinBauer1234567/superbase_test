import 'package:premier_league/utils/season_order.dart';

class LeagueCreationTarget {
  final int tournamentId;
  final String tournamentName;
  final int seasonId;
  final String seasonName;
  final String? imageUrl;

  const LeagueCreationTarget({
    required this.tournamentId,
    required this.tournamentName,
    required this.seasonId,
    required this.seasonName,
    this.imageUrl,
  });

  String get label => '$tournamentName – Saison $seasonName';
}

List<LeagueCreationTarget> leagueCreationTargets(
  List<Map<String, dynamic>> tournaments,
) {
  final targets = <LeagueCreationTarget>[];

  for (final tournament in tournaments) {
    final seasons = sortedSeasons(tournament['season']);
    Map<String, dynamic>? activeSeason;

    for (final season in seasons) {
      if (season['is_active'] == true &&
          season['is_initialized'] == true &&
          season['finished_at'] == null) {
        activeSeason = season;
        break;
      }
    }

    if (activeSeason == null) continue;

    targets.add(
      LeagueCreationTarget(
        tournamentId: (tournament['id'] as num).toInt(),
        tournamentName: tournament['name']?.toString() ?? 'Unbekannte Liga',
        seasonId: (activeSeason['id'] as num).toInt(),
        seasonName: activeSeason['name']?.toString() ?? 'Unbekannt',
        imageUrl: tournament['image_url']?.toString(),
      ),
    );
  }

  targets.sort((a, b) {
    final byName = a.tournamentName.compareTo(b.tournamentName);
    return byName != 0 ? byName : a.tournamentId.compareTo(b.tournamentId);
  });
  return targets;
}

LeagueCreationTarget? preferredLeagueCreationTarget(
  List<LeagueCreationTarget> targets,
  int? currentTournamentId,
) {
  if (targets.isEmpty) return null;
  if (currentTournamentId == null) return targets.first;

  for (final target in targets) {
    if (target.tournamentId == currentTournamentId) return target;
  }
  return targets.first;
}
