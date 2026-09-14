/// Unknown season labels sort last and cannot cause an automatic DB transition.
int seasonYear(Map<String, dynamic> season) {
  final label = (season['year'] ?? season['name'] ?? '').toString().trim();
  final match = RegExp(r'^(\d{4}|\d{2})(?:[/\-]\d{2,4})?$').firstMatch(label);
  if (match == null) return -1;

  final rawYear = int.parse(match.group(1)!);
  if (rawYear >= 100) return rawYear;

  // SofaScore uses short labels such as 26/27, but also historical labels
  // such as 99/00. Treat 70..99 as 19xx and 00..69 as 20xx.
  return rawYear >= 70 ? 1900 + rawYear : 2000 + rawYear;
}

List<Map<String, dynamic>> sortedSeasons(dynamic value) {
  final seasons = List<Map<String, dynamic>>.from(value ?? []);
  seasons.sort((a, b) {
    final byYear = seasonYear(b).compareTo(seasonYear(a));
    return byYear != 0 ? byYear : (b['id'] as int).compareTo(a['id'] as int);
  });
  return seasons;
}

/// Seasons relevant to the manager game:
/// - always keep the newest discovered season
/// - additionally keep every initialized historical season as an archive
/// Older seasons that were never initialized are intentionally hidden.
List<Map<String, dynamic>> managerSeasons(dynamic value) {
  final seasons = sortedSeasons(value);
  if (seasons.isEmpty) return seasons;

  final newestSeasonId = seasons.first['id'];
  return seasons
      .where(
        (season) =>
            season['id'] == newestSeasonId || season['is_initialized'] == true,
      )
      .toList(growable: false);
}

Map<String, dynamic> discoveredSeason(
  int tournamentId,
  Map<String, dynamic> raw,
) {
  final id = raw['id'];
  final name = (raw['year'] ?? raw['name'])?.toString().trim();
  if (id is! int || id <= 0 || name == null || name.isEmpty) {
    throw const FormatException('Ungültige SofaScore-Saison');
  }
  return {
    'id': id,
    'name': name,
    'tournament_id': tournamentId,
    'is_active': false,
  };
}
