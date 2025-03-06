import 'dart:convert';

class Player {
  final String name;
  final String shortName;
  final String position;
  final double statistic;
  final String team;
  final String league;
  final int matchId;

  Player({
    required this.name,
    required this.shortName,
    required this.position,
    required this.statistic,
    required this.team,
    required this.league,
    required this.matchId,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      name: json['player']['name'] ?? 'Unbekannt',
      shortName: json['player']['shortName'] ?? '',
      position: json['player']['position'] ?? '',
      statistic: json['statistic'] ?? 0,
      team: json['event']['homeTeam']['name'] ?? 'Unbekannt',
      league: json['event']['tournament']['name'] ?? 'Unbekannt',
      matchId: json['event']['id'] ?? 0,
    );
  }
}

List<Player> parsePlayers(String responseBody) {
  final parsed = json.decode(responseBody)['topPlayers']['rating'] as List;
  return parsed.map<Player>((json) => Player.fromJson(json)).toList();
}
