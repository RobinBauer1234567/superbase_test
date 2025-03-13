//match_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:premier_league/models/player.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class MatchService {
  final String baseUrl = 'https://www.sofascore.com/api/v1';
  final FirestoreService firestoreService = FirestoreService();
  final ApiService apiService = ApiService();

  Future<List<int>> collectNewData() async {
    List <int> matches = [];
    try {
      // 1️⃣ Hol alle Spieltage
      int latestround = await fetchCurrentRound();
        for (int round = 1; round < latestround; round ++) {
          // 2️⃣ Hol alle Spiele für diesen Spieltag
          List <int> newmatches = await _getMatchesForRound(round);
          matches.addAll(newmatches);
          print(round);
        }

    } catch (e) {
      print("Fehler beim Sammeln der Daten: $e");
    }
    print(matches);
    return matches;
  }

  Future<int> fetchCurrentRound() async {
    final response = await http.get(Uri.parse("https://www.sofascore.com/api/v1/unique-tournament/17/season/61627/rounds"));

    if (response.statusCode == 200) {
      final parsedJson = json.decode(response.body);

      // Sicherstellen, dass 'currentRound' existiert und ein Objekt ist
      if (parsedJson['currentRound'] is Map<String, dynamic>) {
        final roundData = parsedJson['currentRound'];

        // 🔹 Prüfen, ob die Zahl unter 'round' vorhanden ist
        if (roundData['round'] is int) {
          return roundData['round'];
        } else {
          throw Exception("❌ Fehler: 'round' ist nicht vorhanden oder kein int.");
        }
      } else {
        throw Exception("❌ Fehler: 'currentRound' ist nicht das erwartete Format.");
      }
    } else {
      throw Exception("❌ Fehler beim Abrufen der Daten: ${response.statusCode}");
    }
  }

  Future<List<int>> _getMatchesForRound(int roundId) async {
    final response = await http.get(Uri.parse('$baseUrl/unique-tournament/17/season/61627/events/round/$roundId'));

    if (response.statusCode == 200) {
      final parsed = json.decode(response.body);
      return List<int>.from(parsed['events'].map((event) => event['id']));
    } else {
      throw Exception("Fehler beim Laden der Spiele für Runde $roundId");
    }
  }
}


class ApiService {
  Future<List<Player>> fetchTopPlayers(int matchId) async {
    final url = 'https://www.sofascore.com/api/v1/event/$matchId/lineups';
    final response = await http.get(Uri.parse(url));
    List<Player> nullp = [];

    if (response.statusCode == 200) {
      return parsePlayers(response.body, matchId);
    } else {
      print ("$matchId nicht gefunden");
      return nullp;
    }
  }

  List<Player> parsePlayers(String responseBody, int matchId) {
    final parsedJson = json.decode(responseBody);

    // Sicherstellen, dass die API-Struktur korrekt ist
    if (parsedJson['home'] == null || parsedJson['away'] == null) {
      throw Exception("Fehler: 'home' oder 'away' nicht gefunden");
    }

    final List<dynamic> homePlayers = parsedJson['home']['players'] ?? [];
    final List<dynamic> awayPlayers = parsedJson['away']['players'] ?? [];

    return [...homePlayers, ...awayPlayers].map<Player>((json) {
      try {
        return Player(
          name: json['player']?['name'] ?? 'Unbekannt',
          shortName: json['player']?['shortName'] ?? '',
          position: json['position'] ?? '',
          team: json['team']?['name'] ?? 'Unbekannt',
          league: 'Premier League',
          matchRatings: { // 🔹 Hier wird die neue Map-Struktur genutzt
            matchId: (json['statistics']?['rating'] as num?)?.toDouble() ?? 0.0,
          },
        );
      } catch (e) {
        print("⚠️ Fehler beim Parsen eines Spielers: $e");
        return Player(
          name: 'Fehlerhafter Spieler',
          shortName: '',
          position: '',
          team: 'Unbekannt',
          league: 'Unbekannt',
          matchRatings: {
            matchId: 0.0
          }, // 🔹 Fehlerhafte Spieler erhalten trotzdem ein Rating
        );
      }
    }).toList();
  }
}


  class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> savePlayer(List<Player> Players) async {
    for (var player in Players) {
      final playerRef = _db.collection('players').doc(player.name);
      await playerRef.set(player.toJson(),
          SetOptions(merge: true)); // 🔥 SetOptions(merge: true)
    }
  }

  Future<List<Player>> getPlayers() async {
    final snapshot = await _db.collection('players').get();
    return snapshot.docs.map((doc) => Player.fromJson(doc.data())).toList();
  }
}