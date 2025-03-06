import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:premier_league/models/player.dart';

class ApiService {
  Future<List<Player>> fetchTopPlayers() async {
    final response = await http.get(Uri.parse(
        'https://www.sofascore.com/api/v1/unique-tournament/17/season/61627/top-players-per-game/all/overall'));

    if (response.statusCode == 200) {
      return parsePlayers(response.body);
    } else {
      throw Exception("Fehler beim Laden der Spieler: ${response.statusCode}");
    }
  }

  List<Player> parsePlayers(String responseBody) {
    final parsedJson = json.decode(responseBody);

    if (parsedJson['topPlayers'] == null || parsedJson['topPlayers']['rating'] == null) {
      throw Exception("Ungültige API-Daten: 'topPlayers' nicht gefunden");
    }

    final List<dynamic> playersList = parsedJson['topPlayers']['rating'];

    return playersList.map<Player>((json) {
      try {
        return Player(
          name: json['player']['name'] ?? 'Unbekannt',
          shortName: json['player']['shortName'] ?? '',
          position: json['player']['position'] ?? '',
          statistic: (json['statistic'] as num).toDouble(),
          team: json['event']?['homeTeam']?['name'] ?? 'Unbekannt',
          league: json['event']?['tournament']?['name'] ?? 'Unbekannt',
          matchId: json['event']?['id'] ?? 0,
        );
      } catch (e) {
        print("Fehler beim Parsen eines Spielers: $e");
        return Player(
          name: 'Fehlerhafter Spieler',
          shortName: '',
          position: '',
          statistic: 0,
          team: 'Unbekannt',
          league: 'Unbekannt',
          matchId: 0,
        );
      }
    }).toList();
  }
}
