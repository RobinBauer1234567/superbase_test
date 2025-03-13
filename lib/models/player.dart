class Player {
  final String name;
  final String shortName;
  final String position;
  final String team;
  final String league;
  final Map<int, double> matchRatings; // 🔹 Jetzt als Map für zuverlässigere Updates

  Player({
    required this.name,
    required this.shortName,
    required this.position,
    required this.team,
    required this.league,
    required this.matchRatings,
  });

  // 🏗 Factory-Methode zum Erstellen eines Players aus JSON-Daten
  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      name: json['name'] ?? 'Unbekannt',
      shortName: json['shortName'] ?? '',
      position: json['position'] ?? '',
      team: json['team'] ?? 'Unbekannt',
      league: json['league'] ?? 'Unbekannt',
      matchRatings: (json['matchRatings'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(int.parse(key), (value as num).toDouble()),
      ) ?? {},
    );
  }

  // 🔄 Konvertiert das Objekt in JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'shortName': shortName,
      'position': position,
      'team': team,
      'league': league,
      'matchRatings': matchRatings.map((key, value) => MapEntry(key.toString(), value)),
    };
  }

  // 🔄 Methode zum Hinzufügen oder Aktualisieren eines MatchRatings
  void addOrUpdateMatchRating(int matchId, double rating) {
    matchRatings[matchId] = rating; // Falls matchId existiert, wird der Wert überschrieben
  }
}
