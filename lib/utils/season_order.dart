/// Unknown season labels sort last and cannot cause an automatic DB transition.
int seasonYear(Map<String, dynamic> season) {
  final label = (season['year'] ?? season['name'] ?? '').toString().trim();
  final match = RegExp(r'^(\d{4}|\d{2})(?:[/\-]\d{2,4})?$').firstMatch(label);
  if (match == null) return -1;
  final year = int.parse(match.group(1)!);
  return year < 100 ? 2000 + year : year;
}

List<Map<String, dynamic>> sortedSeasons(dynamic value) {
  final seasons = List<Map<String, dynamic>>.from(value ?? []);
  seasons.sort((a, b) {
    final byYear = seasonYear(b).compareTo(seasonYear(a));
    return byYear != 0 ? byYear : (b['id'] as int).compareTo(a['id'] as int);
  });
  return seasons;
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
