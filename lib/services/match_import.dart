/// Reject ambiguous schedule responses before writing any event in the batch.
List<Map<String, dynamic>> validateMatchEvents(
  List<dynamic> events, {
  required int tournamentId,
  required int seasonId,
  required int round,
}) {
  final result = <Map<String, dynamic>>[];
  final teams = <int>{};
  final ids = <int>{};
  for (final raw in events) {
    if (raw is! Map) throw const FormatException('Ungültige Spieldaten.');
    final event = Map<String, dynamic>.from(raw);
    final tournament = event['tournament'];
    final uniqueTournament =
        tournament is Map ? tournament['uniqueTournament'] : null;
    final season = event['season'];
    final roundInfo = event['roundInfo'];
    final home = event['homeTeam'];
    final away = event['awayTeam'];
    if (uniqueTournament is! Map ||
        uniqueTournament['id'] != tournamentId ||
        season is! Map ||
        season['id'] != seasonId ||
        roundInfo is! Map ||
        roundInfo['round'] != round ||
        event['id'] is! int ||
        event['startTimestamp'] is! int ||
        home is! Map ||
        home['id'] is! int ||
        away is! Map ||
        away['id'] is! int) {
      throw FormatException(
        'Spiel ${event['id']}: Turnier, Saison oder Runde widersprüchlich.',
      );
    }
    if (!ids.add(event['id'] as int) ||
        !teams.add(home['id'] as int) ||
        !teams.add(away['id'] as int)) {
      throw FormatException(
        'Mehrere Spiele eines Teams in Saison $seasonId, Runde $round.',
      );
    }
    result.add(event);
  }
  return result;
}
