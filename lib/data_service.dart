//match_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:premier_league/models/player.dart';
import 'package:premier_league/models/match.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ApiService {
  final String baseUrl = 'https://www.sofascore.com/api/v1';
  FirestoreService firestoreService = FirestoreService();
//einmalig
  Future<List<Spieltag>> fetchSpieltage() async {
    final url = '$baseUrl/unique-tournament/17/season/61627/rounds';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final parsedJson = json.decode(response.body);

      List<dynamic> roundsJson = parsedJson['rounds'] ?? [];

      List<Spieltag> spieltage = roundsJson.map<Spieltag>((json) {
        Spieltag spieltagInstance = Spieltag.fromJson(json);


        spieltagInstance = Spieltag.fromJson(json, onStatusChanged: () async {
          await firestoreService.saveSpieltag(spieltagInstance);
        });
        return spieltagInstance;
      }).toList();

      return spieltage;
    } else {
      throw Exception("Fehler beim Abrufen der Spieltage: ${response.statusCode}");
    }
  }

//einmalig
  Future<List<Spiel>> fetchSpieleForRound(int roundId) async {
    final String baseUrl = 'https://www.sofascore.com/api/v1';
    final url = '$baseUrl/unique-tournament/17/season/61627/events/round/$roundId';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final parsedJson = json.decode(response.body);
      List<dynamic> eventsJson = parsedJson['events'] ?? [];

      List<Spiel> spiele = eventsJson.map<Spiel>((json) {
        Spiel spielInstance = Spiel.fromJson(json);
        spielInstance = Spiel.fromJson(
          json,
          onStatusChanged: () async {
            await firestoreService.saveSpiel(spielInstance, spielInstance.matchId);
            print("Spiel ${spielInstance.matchId} wurde nach Statusänderung gespeichert.");
          },
        );
        return spielInstance;
      }).toList();

      return spiele;
    } else {
      throw Exception(
          "Fehler beim Abrufen der Spiele für Runde $roundId: ${response.statusCode}");
    }
  }
//regelmäßig
  Future<SpielStatus> fetchSpielstatus(int matchId) async {
    final url = Uri.parse('https://www.sofascore.com/api/v1/event/$matchId');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.containsKey('event')) {
          final event = data['event'];
          final status = event['status'];
          final String? type = status['type'];

          if (type == 'notstarted') {
            return SpielStatus.notPlayed;
          } else if (type == 'inprogress') {
            return SpielStatus.live;
          } else if (type == 'finished') {
            if (event.containsKey('startTimestamp')) {
              final int startTimeUnix = event['startTimestamp'];
              final DateTime startTime =
              DateTime.fromMillisecondsSinceEpoch(startTimeUnix * 1000);
              final DateTime estimatedEndTime =
              startTime.add(Duration(minutes: 120));
              final DateTime now = DateTime.now();
              final Duration difference = now.difference(estimatedEndTime);
              if (difference <= Duration(minutes: 1440)) {
                return SpielStatus.provisional;
              } else {
                return SpielStatus.finalStatus;
              }
            } else {
              throw Exception('⏳ Weder offizielles noch geschätztes Endzeitdatum verfügbar.');
            }
          } else if (type == 'postponed') {  // ✅ Neuer Fall für verschobene Spiele
            return SpielStatus.postponed;
          } else {
            throw Exception('🔍 Unbekannter Status: $type');
          }
        } else {
          throw Exception('❌ Fehler: Keine Statusinformationen gefunden.');
        }
      } else {
        throw Exception('❌ API-Fehler: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('❌ Fehler beim Abruf der Daten: $e');
    }
  }

//während Spielen
  Future<List<Player>> fetchLineups(int matchId) async {
    final url = 'https://www.sofascore.com/api/v1/event/$matchId/lineups';
    final response = await http.get(Uri.parse(url));
    List<Player> nullp = [];

    if (response.statusCode == 200) {
      return parsePlayers(response.body, matchId);
    } else {
      print("$matchId nicht gefunden");
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
          matchRatings: {
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

  // 🔥 Spieler speichern
  Future<void> savePlayer(List<Player> players) async {
    for (var player in players) {
      final playerRef = _db.collection('players').doc(player.name);
      await playerRef.set(player.toJson(), SetOptions(merge: true));
    }
  }

  // 🔥 Alle Spieler abrufen
  Future<List<Player>> getPlayers() async {
    final snapshot = await _db.collection('players').get();
    return snapshot.docs.map((doc) => Player.fromJson(doc.data())).toList();
  }

  // 🔥 Spieltag speichern
  Future<void> saveSpieltag(Spieltag spieltag) async {
    try {
      final docRef =
      _db.collection('spieltage').doc(spieltag.roundNumber.toString());

      // Falls nicht final, speichern
      await docRef.set(spieltag.toJson(), SetOptions(merge: true));
    } catch (e) {
      print("❌ Fehler beim Speichern des Spieltages ${spieltag.roundNumber}: $e");
    }
  }

  // 🔥 Alle Spieltage abrufen
  Future<List<Spieltag>> getSpieltage() async {
    QuerySnapshot snapshot = await _db.collection('spieltage').get();
    return snapshot.docs
        .map((doc) => Spieltag.fromJson(doc.data() as Map<String, dynamic>))
        .toList();
  }

  // 🔥 Spiel speichern
  Future<void> saveSpiel(Spiel spiel, int roundNumber) async {
    try {
      // Speichere das Spiel in der Subcollection "spiele" innerhalb des Spieltag-Dokuments
      final spielRef = _db
          .collection('spieltage')
          .doc(roundNumber.toString())
          .collection('spiele')
          .doc(spiel.matchId.toString());

      // Optionale Prüfung, ob das Spiel schon final ist (falls gewünscht)
      final snapshot = await spielRef.get();
      if (snapshot.exists) {
        final existingData = snapshot.data() as Map<String, dynamic>;
        if (existingData['status'] == SpielStatus.finalStatus.description) {
          print("⚠️ Spiel ${spiel.matchId} ist bereits final und wird nicht aktualisiert.");
          return;
        }
      }

      await spielRef.set(spiel.toJson(), SetOptions(merge: true));
    } catch (e) {
      print("❌ Fehler beim Speichern des Spiels ${spiel.matchId}: $e");
    }
  }



  // 🔥 Alle Spiele eines bestimmten Spieltags abrufen
  Future<List<Spiel>> getSpieleBySpieltag(int roundNumber) async {
    try {
      final docSnapshot = await _db.collection('spieltage').doc(roundNumber.toString()).get();

      if (!docSnapshot.exists) {
        print("⚠️ Kein Spieltag mit Nummer $roundNumber gefunden.");
        return [];
      }

      final data = docSnapshot.data();
      print("📥 Rohdaten aus Firestore: $data");
      if (data == null || !data.containsKey('spiele')) {
        print("⚠️ Kein 'spiele'-Feld in Spieltag $roundNumber gefunden.");
        return [];
      }
      print("🎮 Spiele-Array: ${data['spiele']}");

      final List<dynamic> spieleList = data['spiele'];

      return spieleList.map((spielData) => Spiel.fromJson(spielData as Map<String, dynamic>)).toList();
    } catch (e) {
      print("❌ Fehler beim Abrufen der Spiele: $e");
      return [];
    }
  }




}
