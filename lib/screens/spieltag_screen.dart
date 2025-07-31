import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


/// HomeScreen: Zeigt den aktuellen Spieltag und listet alle Spiele aus der Tabelle 'spiel'
class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> spiele = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchSpiele();
  }

  Future<void> fetchSpiele() async {
    try {
      // Direkter Abruf ohne execute/get
      final data = await Supabase.instance.client
          .from('spiel')
          .select()
          .order('id', ascending: true);
      setState(() {
        spiele = data;
        isLoading = false;
      });
    } catch (error) {
      print("Fehler beim Abruf der Spiele: $error");
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Spieltag 1')),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: spiele.length,
        itemBuilder: (context, index) {
          final spiel = spiele[index];
          return ListTile(
            title: Text("${spiel['heimteam']} vs ${spiel['auswärtsteam']}"),
            subtitle: Text("Ergebnis: ${spiel['ergebnis']}"),
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

/// GameScreen: Zeigt Details zu einem Spiel und listet die Spieler beider Teams
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
      // Filtere Spieler, deren Team entweder dem Heim- oder Auswärtsteam entspricht
      final data = await Supabase.instance.client
          .from('spieler')
          .select()
          .filter('team', 'in', [widget.spiel['heimteam'], widget.spiel['auswärtsteam']]);

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
    return Scaffold(
      appBar:
      AppBar(title: Text("${widget.spiel['heimteam']} vs ${widget.spiel['auswärtsteam']}")),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView(
        children: [
          ListTile(title: Text("Ergebnis: ${widget.spiel['ergebnis']}")),
          Divider(),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text("Spieler des Spiels:",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          ...spieler.map((s) => ListTile(
            title: Text(s['name']),
            subtitle: Text(s['position']),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => PlayerScreen(playerId: s['id'])),
              );
            },
          )),
        ],
      ),
    );
  }
}

/// PlayerScreen: Zeigt Details zu einem Spieler inklusive Profilbild und Matchratings
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

  Future<void> fetchPlayerDetails() async {
    try {
      // Abruf des Spielers aus der Tabelle 'spieler'
      final playerData = await Supabase.instance.client
          .from('spieler')
          .select()
          .eq('id', widget.playerId)
          .single();
      // Abruf der Matchratings für den Spieler
      final ratingData = await Supabase.instance.client
          .from('matchrating')
          .select()
          .eq('spieler_id', widget.playerId);
      setState(() {
        player = playerData;
        matchratings = ratingData;
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
                  : AssetImage('assets/placeholder.png') as ImageProvider,
            ),
            SizedBox(height: 10),
            Text("Position: ${player!['position']}", style: TextStyle(fontSize: 18)),
            Text("Team: ${player!['team']}", style: TextStyle(fontSize: 18)),
            SizedBox(height: 20),
            Text('Matchratings:',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ...matchratings.map((r) => ListTile(
              title: Text('Rating: ${r['rating']}'),
              subtitle: Text('Spiel-ID: ${r['spiel_id']}'),
            )),
          ],
        ),
      ),
    );
  }
}
