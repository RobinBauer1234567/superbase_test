//main
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://erpsqbbbdibtdddaxhfh.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVycHNxYmJiZGlidGRkZGF4aGZoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDIyMDc0MjcsImV4cCI6MjA1Nzc4MzQyN30.19pUS2rKFH8jhzOPA9JOnsEJJnBcAhqFVnnDqcgCHKI',
  );
  final DataManagement dataManagement = DataManagement();
  await dataManagement.collectNewData();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fußball Liga Manager',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: SpieltageScreen(),
    );
  }
}

class ApiService {
  final String baseUrl = 'https://www.sofascore.com/api/v1';
  SupabaseService supabaseService = SupabaseService();
  //einmalig
  Future<void> fetchAndStoreSpieltage() async {
    final url = '$baseUrl/unique-tournament/17/season/61627/rounds';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final parsedJson = json.decode(response.body);
      List<dynamic> roundsJson = parsedJson['rounds'] ?? [];

      for (var round in roundsJson) {
        int roundNumber =
            int.tryParse(round['round'].toString()) ??
            0; // Sicherstellen, dass round eine Zahl ist
        await supabaseService.saveSpieltag(roundNumber, 'nicht gestartet');
      }
    } else {
      throw Exception(
        "Fehler beim Abrufen der Spieltage: ${response.statusCode}",
      );
    }
  }
  //einmalig
  Future<void> fetchAndStoreSpiele(int round) async {
    final url =
        '$baseUrl/unique-tournament/17/season/61627/events/round/$round';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final parsedJson = json.decode(response.body);

      List<dynamic> eventsJson = parsedJson['events'] ?? [];
      for (var event in eventsJson) {
        int matchId = event['id'];
        int homeTeamId = event['homeTeam']['id'];
        String homeTeamName = event['homeTeam']['name']; // Heimteam-Name
        int awayTeamId = event['awayTeam']['id'];
        String awayTeamName = event['awayTeam']['name']; // Auswärtsteam-Name
        int timestampInt =
            event['startTimestamp']; // Annahme: Der Wert ist ein Unix-Zeitstempel in Sekunden
        DateTime startTimestamp = DateTime.fromMillisecondsSinceEpoch(
          timestampInt * 1000,
        );
        String startTimeString =
            startTimestamp.toIso8601String(); // ISO 8601 Format
        String status = event['status']['description'] ?? 'nicht gestartet';

        // Score-Daten extrahieren (null abfangen)
        var homeScore = event['homeScore']?['current'] ?? 0;
        var awayScore = event['awayScore']?['current'] ?? 0;

        String ergebnis =
            (event['homeScore'] == null || event['awayScore'] == null)
                ? "Noch kein Ergebnis"
                : "$homeScore:$awayScore";
        await supabaseService.saveTeam(homeTeamId, homeTeamName);
        await supabaseService.saveTeam(awayTeamId, awayTeamName);
        await supabaseService.saveSpiel(
          matchId,
          startTimeString,
          homeTeamId,
          awayTeamId,
          ergebnis,
          status,
          round,
        );
      }
    } else {
      throw Exception(
        "Fehler beim Abrufen der Spiele für Runde $round: ${response.statusCode}",
      );
    }
  }
  //regelmäßig
  Future<void> fetchAndStoreSpielerundMatchratings(int spielId, hometeamId, awayteamId) async {
    final url = 'https://www.sofascore.com/api/v1/event/$spielId/lineups';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final parsedJson = json.decode(response.body);

      // Heim- und Auswärtsteam-Spieler extrahieren
      List<dynamic> homePlayers = parsedJson['home']['players'] ?? [];
      List<dynamic> awayPlayers = parsedJson['away']['players'] ?? [];

      // Spieler-Daten verarbeiten (Heimteam)
      for (var playerData in homePlayers) {
        await processPlayerData(playerData, hometeamId, spielId);
      }

      // Spieler-Daten verarbeiten (Auswärtsteam)
      for (var playerData in awayPlayers) {
        await processPlayerData(playerData, awayteamId, spielId);
      }
    } else {
      throw Exception("Fehler beim Abrufen der Spieler für Spiel $spielId: ${response.statusCode}");
    }
  }
// Hilfsfunktion zur Verarbeitung und Speicherung eines Spielers
  Future<void> processPlayerData(Map<String, dynamic> playerData, int teamId, int spielId) async {
    var player = playerData['player'];

    int playerId = player['id'];
    String playerName = player['name'];
    String position = player['position'];
    double rating = playerData['statistics']?['rating'] ?? 6.0; // Falls kein Rating vorhanden
    double punkte = (rating - 6) * 100;
    int punktzahl = punkte.round();
    int ratingId = int.parse('$spielId$playerId');

    // Daten in Supabase speichern
    await supabaseService.saveSpieler(playerId, playerName, position, teamId);
    await supabaseService.saveMatchrating(ratingId, spielId, playerId, punktzahl);
  }
}

class SupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Spieltag speichern
  Future<void> saveSpieltag(int round, String status) async {
    try {
      await _supabase.from('spieltag').upsert(
          {
            'round': round, // Unique Key
            'status': status,
          },
          onConflict: 'round'
      );
    } catch (error) {
      print('Fehler beim Speichern des Spieltags: $error');
    }
  }
  // Alle Spieltage abrufen
  Future<List<int>> fetchAllSpieltagIds() async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase.from('spieltag').select('round');

      if (response.isEmpty) {
        print('Keine Spieltage gefunden.');
        return [];
      }

      List<int> spieltagIds =
          response.map<int>((row) => row['round'] as int).toList();
      return spieltagIds;
    } catch (error) {
      print('Fehler beim Abrufen der Spieltag-IDs: $error');
      return [];
    }
  }
  // Team speichern
  Future<void> saveTeam(int id, String name) async {
    try {
      await _supabase.from('team').upsert({
        'id': id, // Unique Key
        'name': name,
      },
      onConflict: 'id'
    );
    } catch (error) {
      print('Fehler beim Speichern des Teams: $error');
    }
  }
  // Spiel speichern
  Future<void> saveSpiel(int id, datum, int heimteamId, int auswartsteamId, String ergebnis, String status, int round) async {
    try {
      await _supabase.from('spiel').upsert({
        'id': id,
        'datum': datum,
        'heimteam_id': heimteamId,
        'auswärtsteam_id': auswartsteamId,
        'ergebnis': ergebnis,
        'round': round,
      },
      onConflict: 'id'
      );
    } catch (error) {
      print('Fehler beim Speichern des Spiels: $error');
    }
  }
  // Alle Spiele eies Spieltags abrufen
  Future<List<int>> fetchSpielIdsForRound(int round) async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase.from('spiel').select('id').eq('round', round);
      return response.map<int>((spiel) => spiel['id'] as int).toList();
    } catch (error) {
      print('Fehler beim Abrufen der Spiel-IDs: $error');
      return [];
    }
  }
  // Spieldatum für Spiel abrufen
  Future <DateTime> fetchSpieldatum (spielId) async {
    final response = await _supabase
        .from('spiel')
        .select('datum')
        .eq('id', spielId)
        .single(); // Falls du genau ein Ergebnis erwartest

      DateTime spielDatum = DateTime.parse(response['datum']);
      return spielDatum;
  }
  // Status für Spiel ändern
  Future<void> updateSpielStatus(int spielId, String neuerStatus) async {
    await _supabase
        .from('spiel')
        .update({'status': neuerStatus}) // Neuer Status setzen
        .eq('id', spielId); // Nur das Spiel mit der passenden ID aktualisieren
  }
  // Status für Spieltag ändern
  Future<void> updateSpieltagStatus(int round, String neuerStatus) async {
    await _supabase
        .from('spieltag')
        .update({'status': neuerStatus}) // Neuer Status setzen
        .eq('round', round); // Nur das Spiel mit der passenden ID aktualisieren
  }
  // Spieler speichern
  Future<void> saveSpieler(int id, String name, String position, int teamId) async {
    try {
      await _supabase.from('spieler').upsert(
          {
            'id': id, // Unique Key
            'name': name,
            'position': position,
            'team_id': teamId
          },
          onConflict: 'id'
      );
    } catch (error) {
      print('Fehler beim Speichern des Spielers: $error');
    }
  }
  // Matchrating speichern
  Future<void> saveMatchrating(int id, int spielId, int spielerId, int rating) async {
    try {
      await _supabase.from('matchrating').upsert(
          {
            'id': id,
            'spiel_id': spielId,
            'spieler_id': spielerId,
            'punkte': rating,
          },
          onConflict: 'id'
      );

    } catch (error) {
      print('Fehler beim Speichern des Matchratings: $error');
    }
  }
}

class DataManagement {
  final SupabaseClient _supabase = Supabase.instance.client;
  ApiService apiService = ApiService();
  SupabaseService supabaseService = SupabaseService();

  Future<void> collectNewData() async {
    print('start: collectnewData');
    await apiService.fetchAndStoreSpieltage();
    print('spieltage gespeichert');
    List<int> spieltage = await supabaseService.fetchAllSpieltagIds();
    for (var spieltag in spieltage) {
      await apiService.fetchAndStoreSpiele(spieltag);
      print('spiele für Spieltag $spieltag gespeichert');
    }
    await updateData();
    print('finish');
  }

  Future<void> updateData() async {
    List<int> spieltage = await supabaseService.fetchAllSpieltagIds();
    print('Update gestartet');

    for (var spieltagId in spieltage) {
      final response = await _supabase
          .from('spieltag')
          .select('status')
          .eq('round', spieltagId)
          .maybeSingle(); // Falls kein Ergebnis, wird `null` zurückgegeben

      if (response == null || response['status'] == null) {
        print('Kein Status für Spieltag $spieltagId gefunden.');
        continue;
      }

      String spieltagStatus = response['status'];//hallo
      if (spieltagStatus == 'final') {
        print ('spieltag: $spieltagId ist bereits final');
        continue;
      }

      List<int> spiele = await supabaseService.fetchSpielIdsForRound(spieltagId);
      List<String> spielStatusSpieltag = [];

      for (var spiel in spiele) {
        final spielResponse = await _supabase
            .from('spiel')
            .select('id, status, heimteam_id, auswärtsteam_id')
            .eq('id', spiel)
            .maybeSingle();


        String status = spielResponse?['status'] ?? 'unbekannt'; // Falls `null`, Standardwert setzen

        int hometeamId = spielResponse?['heimteam_id'] ?? 'unbekannt';
        int awayteamId = spielResponse?['auswärtsteam_id'] ?? 'unbekannt';
        if (status != 'final') {
          String neuerStatus = await getSpielStatus(spiel);
          if (status != neuerStatus) {
            status = neuerStatus;
            await supabaseService.updateSpielStatus(spiel, status);
          }
          await apiService.fetchAndStoreSpielerundMatchratings(spiel, hometeamId, awayteamId);
        }
        spielStatusSpieltag.add(status);
      }

      // Spieltag-Status basierend auf den Spiel-Status setzen
      if (spielStatusSpieltag.every((s) => s == 'final')) {
        await supabaseService.updateSpieltagStatus(spieltagId, 'final');
      } else if (spielStatusSpieltag.every((s) => s == 'nicht gestartet')) {
        await supabaseService.updateSpieltagStatus(spieltagId, 'nicht gestartet');
      } else {
        if (spielStatusSpieltag.any((s) => s == 'nicht gestartet') || spielStatusSpieltag.any((s) => s == 'läuft')) {
          await supabaseService.updateSpieltagStatus(spieltagId, 'läuft');
        } else {
          await supabaseService.updateSpieltagStatus(spieltagId, 'beendet');
        }
      }
      print('spieltag:$spieltagId wurde geupdated');
    }
  }


  Future <String> getSpielStatus (spielId) async {
    String spielstatus;
    DateTime spielDatum = await supabaseService.fetchSpieldatum(spielId);
    DateTime jetzt = DateTime.now();
    Duration differenz = jetzt.difference(spielDatum);

    if (differenz.inHours <= 0) {
      spielstatus = 'nicht gestartet';
    } else if (differenz.inHours < 2) {
      spielstatus = 'läuft';
    } else if (differenz.inHours < 24) {
      spielstatus = 'beendet';
    } else if (differenz.inHours >= 24) {
      spielstatus = 'final';
    } else {
      spielstatus = 'unklar';
    }

    return spielstatus;
  }
}

class SpieltageScreen extends StatefulWidget {
  @override
  _SpieltageScreenState createState() => _SpieltageScreenState();
}

class _SpieltageScreenState extends State<SpieltageScreen> {
  List<dynamic> spieltage = [];
  final ApiService apiService = ApiService();
  SupabaseService supabaseService = SupabaseService();

  @override
  void initState() {
    super.initState();
    fetchSpieltage();
  }

  Future<void> fetchSpieltage() async {
    final response = await supabaseService._supabase.from('spieltag').select();

    setState(() {
      spieltage = response;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Spieltag')),
      body:
          spieltage.isEmpty
              ? Center(
                child: CircularProgressIndicator(),
              ) // Ladeanzeige, falls noch keine Daten geladen sind
              : ListView.builder(
                itemCount: spieltage.length,
                itemBuilder: (context, index) {
                  final spieltag = spieltage[index];
                  return ListTile(
                    title: Text("Spieltag ${spieltag['round']}"),
                    subtitle: Text("Status: ${spieltag['status']}"),
                  );
                },
              ),
    );
  }
}
