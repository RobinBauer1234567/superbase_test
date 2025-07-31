import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// lib/screens/spieltag_screen.dart


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
      // Dieser Aufruf ist für deine Datenbankstruktur korrekt.
      final data = await Supabase.instance.client
          .from('spiel')
          .select('*, heimteam:spiel_heimteam_id_fkey(name), auswaertsteam:spiel_auswärtsteam_id_fkey(name)')
          .eq('round', widget.round)
          .order('id', ascending: true);

      setState(() {
        spiele = data;
        isLoading = false;
      });
    } catch (error) {
      print("Fehler beim Abruf der Spiele: $error");
      // Zeige den Fehler im UI an, das hilft beim Debuggen!
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

  // Die Funktion getTeamNameById wird jetzt nicht mehr benötigt,
  // da wir die Namen bereits in der Hauptabfrage erhalten. Das verbessert die Performance enorm.

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

          // ✅ KORREKTER ZUGRIFF:
          // Greife direkt auf die Namen zu, die bereits mitgeladen wurden.
          // Kein 'await', kein 'FutureBuilder' nötig.
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
  List<dynamic> spieler = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchSpieler();
  }

  Future<void> fetchSpieler() async {
    try {
      final heimTeamId = widget.spiel['heimteam_id'];
      final auswaertsTeamId = widget.spiel['auswaertsteam_id'];

      final data = await Supabase.instance.client
          .from('spieler')
          .select()
          .filter('team_id', 'in', '(${heimTeamId}, ${auswaertsTeamId})');


      setState(() {
        spieler = data;
        isLoading = false;
      });
    } catch (error) {
      print("Fehler beim Abruf der Spieler: $error");
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ FIX: Korrekter Zugriff auf die Teamnamen für den Titel
    final heimTeamName = widget.spiel['heimteam']?['name'] ?? 'Team A';
    final auswaertsTeamName = widget.spiel['auswaertsteam']?['name'] ?? 'Team B';

    return Scaffold(
      appBar: AppBar(title: Text("$heimTeamName vs $auswaertsTeamName")),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView(
        children: [
          ListTile(title: Text("Ergebnis: ${widget.spiel['ergebnis']}")),
          Divider(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text("Spieler des Spiels:",
                style:
                TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          ...spieler.map((s) => ListTile(
            title: Text(s['name']),
            subtitle: Text(s['position']),
            onTap: () {
              // Der Navigator zum PlayerScreen (unverändert)
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        PlayerScreen(playerId: s['id'])),
              );
            },
          )),
        ],
      ),
    );
  }
}
class PlayerScreen extends StatefulWidget {
  final int playerId;
  PlayerScreen({required this.playerId});
  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  Map<String, dynamic>? player;
  List<dynamic> matchratings = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchPlayerDetails();
  }

  // in class _PlayerScreenState

  Future<void> fetchPlayerDetails() async {
    try {
      final results = await Future.wait<dynamic>([
        Supabase.instance.client
            .from('spieler')
            .select('*, team:team_id(name)')
            .eq('id', widget.playerId)
            .single(),

        Supabase.instance.client
            .from('matchrating')
            .select()
            .eq('spieler_id', widget.playerId),
      ]);


      setState(() {
        player = results[0] as Map<String, dynamic>;
        matchratings = results[1] as List<dynamic>;
        isLoading = false;
      });
    } catch (error) {
      print("Fehler beim Abruf des Spielers oder der Matchratings: $error");
      setState(() {
        isLoading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(player != null ? player!['name'] : 'Spieler')),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : player == null
          ? Center(child: Text('Keine Daten gefunden'))
          : SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 20),
            CircleAvatar(
              radius: 50,
              backgroundImage: player!['profilbild_url'] != null &&
                  player!['profilbild_url'] != ''
                  ? NetworkImage(player!['profilbild_url'])
                  : AssetImage('assets/placeholder.png')
              as ImageProvider,
            ),
            SizedBox(height: 10),
            Text("Position: ${player!['position']}",
                style: TextStyle(fontSize: 18)),
            // ✅ FIX: Teamnamen aus dem verschachtelten Objekt holen
            Text("Team: ${player!['team']?['name'] ?? 'Unbekannt'}",
                style: TextStyle(fontSize: 18)),
            SizedBox(height: 20),
            Text('Matchratings:',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            ...matchratings.map((r) => ListTile(
              // ✅ FIX: 'punkte' statt 'rating' verwenden
              title: Text('Punkte: ${r['punkte']}'),
              subtitle: Text('Spiel-ID: ${r['spiel_id']}'),
            )),
          ],
        ),
      ),
    );
  }
}