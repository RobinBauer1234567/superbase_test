import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/player_screen.dart';

/// HomeScreen: Zeigt jetzt die Spiele für einen bestimmten Spieltag an.
class HomeScreen extends StatefulWidget {
  // FÜGE DIESE VARIABLE HINZU, um die Spieltagsnummer zu speichern
  final int round;

  // AKTUALISIERE DEN KONSTRUKTOR, um die Spieltagsnummer zu empfangen
  HomeScreen({required this.round});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> spiele = [];
  bool isLoading = true;
  // bool Loading = true; // Dieser zweite Lade-Status ist überflüssig.

  @override
  void initState() {
    super.initState();
    fetchSpieleAndTeamNames(); // Wir benennen die Funktion um, damit klar ist, was sie tut.
  }

  /// ✅ LÄDT ALLES IN EINER ABFRAGE:
  /// Diese Funktion holt die Spieldaten und verknüpft sie direkt mit den Teamnamen.
  /// Das ist die effizienteste Methode.
  Future<void> fetchSpieleAndTeamNames() async {
    setState(() { isLoading = true; });

    try {
      // ✅ KORREKTUR: Abfrage um hometeam_formation und awayteam_formation erweitert
      final data = await Supabase.instance.client
          .from('spiel')
          .select('*, heimteam_id, auswärtsteam_id, hometeam_formation, awayteam_formation, status, heimteam:spiel_heimteam_id_fkey(name), auswaertsteam:spiel_auswärtsteam_id_fkey(name)')
          .eq('round', widget.round)
          .order('id', ascending: true);

      setState(() {
        spiele = data;
        isLoading = false;
      });
    } catch (error) {
      print("Fehler beim Abruf der Spiele: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: ${error.toString()}'))
        );
      }
      setState(() {
        isLoading = false;
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Spieltag ${widget.round}')),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: spiele.length,
        itemBuilder: (context, index) {
          final spiel = spiele[index];


          final heimTeamName = spiel['heimteam']['name'] ?? 'Unbekannt';
          final auswaertsTeamName = spiel['auswaertsteam']['name'] ?? 'Unbekannt';

          return ListTile(
            title: Text("$heimTeamName vs $auswaertsTeamName"),
            subtitle: Text("Ergebnis: ${spiel['ergebnis'] ?? 'N/A'}"),
            trailing: Icon(Icons.arrow_forward),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => GameScreen(spiel: spiel)),
              );
            },
          );
        },
      ),
    );
  }
}

class GameScreen extends StatefulWidget {
  final Map<String, dynamic> spiel;
  GameScreen({required this.spiel});
  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  List<PlayerInfo> homePlayers = [];
  List<PlayerInfo> awayPlayers = [];
  bool isLoading = true;
  final DataManagement _dataManagement = DataManagement();

  @override
  void initState() {
    super.initState();
    // NEU: Diese Methode prüft die Daten und aktualisiert sie bei Bedarf.
    _checkAndUpdateData();
  }

  /// **NEU: Überprüft die Spieleranzahl und den Spielstatus.**
  /// Ruft bei Bedarf ein Update auf, bevor die Spielerdaten geladen werden.
  Future<void> _checkAndUpdateData() async {
    final spielId = widget.spiel['id'];
    final heimTeamId = widget.spiel['heimteam_id'];
    final auswaertsTeamId = widget.spiel['auswärtsteam_id'];
    final status = widget.spiel['status'];

    // Rufe die von dir bereitgestellte Methode auf
    final spielerAnzahl = await getSpieleranzahl(spielId, heimTeamId, auswaertsTeamId);

    // Prüfe die Bedingungen
    if (spielerAnzahl < 40 || status != 'final') {
      print("--- DATEN UNVOLLSTÄNDIG ($spielerAnzahl Spieler, Status: $status). Starte Update für Spiel $spielId ---");
      // Zeige dem Benutzer, dass etwas passiert
      setState(() {
        isLoading = true;
      });
      // Rufe die Update-Funktion auf
      await _dataManagement.updateRatingsForSingleGame(spielId);
      print("--- Update für Spiel $spielId abgeschlossen ---");
    }

    // Lade die (jetzt aktuellen) Spielerdaten für die Anzeige
    await fetchSpieler();
  }

  /// **NEU: Deine Methode zur Zählung der Spieler, hier integriert.**
  Future<int> getSpieleranzahl(int spielId, int heimTeamId, int auswaertsTeamId) async {
    final data = await Supabase.instance.client
        .from('spieler')
        .select('*, matchrating!inner(formationsindex, match_position)')
        .eq('matchrating.spiel_id', spielId)
        .filter('team_id', 'in', '($heimTeamId, $auswaertsTeamId)');

    return data.length;
  }

  Future<void> fetchSpieler() async {
    // ... (Diese Methode bleibt unverändert)
    try {
      final heimTeamId = widget.spiel['heimteam_id'];
      final auswaertsTeamId = widget.spiel['auswärtsteam_id'];
      final spielId = widget.spiel['id'];

      print("--- DEBUG: Starte fetchSpieler für Spiel-ID $spielId ---");

      // ✅ Abfrage um die neue Spalte 'match_position' erweitert
      final data = await Supabase.instance.client
          .from('spieler')
          .select('*, matchrating!inner(formationsindex, match_position)') // JOIN
          .eq('matchrating.spiel_id', spielId)
          .filter('team_id', 'in', '($heimTeamId, $auswaertsTeamId)');

      print("--- DEBUG: Rohdaten von Supabase erhalten (${data.length} Spieler) ---");
      // Logge die Rohdaten, um zu sehen, was ankommt
      for (var spieler in data) {
        final index = spieler['matchrating']?[0]?['formationsindex'];
        print("Spieler: ${spieler['name']}, Team: ${spieler['team_id']}, Formationsindex: $index");
      }
      print("----------------------------------------------------------");


      List<Map<String, dynamic>> tempHomePlayersData = [];
      List<Map<String, dynamic>> tempAwayPlayersData = [];

      for (var spieler in data) {
        if (spieler['team_id'] == heimTeamId) {
          tempHomePlayersData.add(spieler);
        } else {
          tempAwayPlayersData.add(spieler);
        }
      }

      // ✅ ROBUSTERE SORTIERUNG HINZUGEFÜGT
      // Diese Sortierung fängt null-Werte ab und sortiert sie ans Ende.
      tempHomePlayersData.sort((a, b) {
        final indexA = a['matchrating']?[0]?['formationsindex'] ?? 99;
        final indexB = b['matchrating']?[0]?['formationsindex'] ?? 99;
        return indexA.compareTo(indexB);
      });

      tempAwayPlayersData.sort((a, b) {
        final indexA = a['matchrating']?[0]?['formationsindex'] ?? 99;
        final indexB = b['matchrating']?[0]?['formationsindex'] ?? 99;
        return indexA.compareTo(indexB);
      });

      print("\n--- DEBUG: Sortierte Heim-Mannschaft ---");
      tempHomePlayersData.forEach((p) => print("Index: ${p['matchrating'][0]['formationsindex']}, Name: ${p['name']}"));
      print("----------------------------------------\n");

      print("\n--- DEBUG: Sortierte Auswärts-Mannschaft ---");
      tempAwayPlayersData.forEach((p) => print("Index: ${p['matchrating'][0]['formationsindex']}, Name: ${p['name']}"));
      print("----------------------------------------\n");


      final List<PlayerInfo> finalHomePlayers = tempHomePlayersData
          .map((spieler) => PlayerInfo(id: spieler['id'], name: spieler['name'], position: spieler['matchrating'][0]['match_position']))
          .toList();
      final List<PlayerInfo> finalAwayPlayers = tempAwayPlayersData
          .map((spieler) => PlayerInfo(id: spieler['id'], name: spieler['name'], position: spieler['matchrating'][0]['match_position']))
          .toList();

      setState(() {
        homePlayers = finalHomePlayers;
        awayPlayers = finalAwayPlayers;
        isLoading = false;
      });
    } catch (error) {
      print("Fehler beim Abruf der Spieler: $error");
      if(mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... (Diese Methode bleibt unverändert)
    final heimTeamName = widget.spiel['heimteam']?['name'] ?? 'Team A';
    final auswaertsTeamName = widget.spiel['auswaertsteam']?['name'] ?? 'Team B';
    final homeFormation = widget.spiel['hometeam_formation'] ?? 'N/A';
    final awayFormation = widget.spiel['awayteam_formation'] ?? 'N/A';
    return Scaffold(
      appBar: AppBar(
        title: Text("$heimTeamName vs $auswaertsTeamName"),
        // ✅ NEU: Refresh-Button in der AppBar
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () async {
              // Zeige einen Ladeindikator während der Aktualisierung
              setState(() {
                isLoading = true;
              });

              // Rufe die neue Update-Funktion auf
              await _dataManagement.updateRatingsForSingleGame(widget.spiel['id']);

              // Lade die Spielerdaten neu, um die Formation zu aktualisieren
              await fetchSpieler();

              // Verstecke den Ladeindikator
              setState(() {
                isLoading = false;
              });

              // Zeige eine Bestätigung an
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Daten wurden aktualisiert!')),
              );
            },
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : (homePlayers.length >= 11 && awayPlayers.length >= 11)
          ? MatchFormationDisplay(
        homeFormation: homeFormation,
        homePlayers: homePlayers,
        homeColor: Colors.red.shade700,
        awayFormation: awayFormation,
        awayPlayers: awayPlayers,
        awayColor: Colors.blue.shade300,
        onPlayerTap: (playerId) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PlayerScreen(playerId: playerId),
            ),
          );
        },
      )
          : Center(
        child: Text(
            "Nicht genügend Spielerdaten für die Formationsanzeige."),
      ),
    );
  }
}