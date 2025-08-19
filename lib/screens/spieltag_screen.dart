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
          .select('*, heimteam_id, auswärtsteam_id, hometeam_formation, awayteam_formation, heimteam:spiel_heimteam_id_fkey(name), auswaertsteam:spiel_auswärtsteam_id_fkey(name)')
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
  final dynamic spiel;
  GameScreen({required this.spiel});
  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  List<PlayerInfo> homePlayers = [];
  List<PlayerInfo> homeSubstitutes = [];
  List<PlayerInfo> awayPlayers = [];
  List<PlayerInfo> awaySubstitutes = [];
  bool isLoading = true;
  final DataManagement _dataManagement = DataManagement(); // Instanz erstellen

  String? _expandedBench; // Hält den Zustand, welche Bank ausgeklappt ist ('home' oder 'away')

  @override
  void initState() {
    super.initState();
    fetchSpieler();
  }

  Future<void> fetchSpieler() async {
    // ... (Datenabruf bleibt unverändert)
    try {
      final heimTeamId = widget.spiel['heimteam_id'];
      final auswaertsTeamId = widget.spiel['auswärtsteam_id'];
      final spielId = widget.spiel['id'];

      print("--- DEBUG: Starte fetchSpieler für Spiel-ID $spielId ---");

      // ✅ Abfrage um die neue Spalte 'match_position' erweitert
      final data = await Supabase.instance.client
          .from('spieler')
          .select('*, profilbild_url, matchrating!inner(formationsindex, match_position, punkte, statistics)') // JOIN und punkte hinzugefügt
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

      PlayerInfo _mapToPlayerInfo(Map<String, dynamic> spieler) {
        final ratingData = spieler['matchrating'][0];
        final stats = ratingData['statistics'] as Map<String, dynamic>? ?? {};

        return PlayerInfo(
          id: spieler['id'],
          name: spieler['name'],
          position: ratingData['match_position'],
          rating: ratingData['punkte'],
          profileImageUrl: spieler['profilbild_url'],
          goals: (stats['goals'] as int?) ?? 0,
          assists: (stats['assists'] as int?) ?? 0,
          ownGoals: (stats['ownGoals'] as int?) ?? 0,
        );
      }



      final List<PlayerInfo> finalHomePlayers = tempHomePlayersData
          .where((s) => s['matchrating'][0]['formationsindex'] < 11)
          .map(_mapToPlayerInfo)
          .toList();
      final List<PlayerInfo> finalHomeSubstitutes = tempHomePlayersData
          .where((s) => s['matchrating'][0]['formationsindex'] >= 11)
          .map(_mapToPlayerInfo)
          .toList();
      final List<PlayerInfo> finalAwayPlayers = tempAwayPlayersData
          .where((s) => s['matchrating'][0]['formationsindex'] < 11)
          .map(_mapToPlayerInfo)
          .toList();
      final List<PlayerInfo> finalAwaySubstitutes = tempAwayPlayersData
          .where((s) => s['matchrating'][0]['formationsindex'] >= 11)
          .map(_mapToPlayerInfo)
          .toList();

      setState(() {
        homePlayers = finalHomePlayers;
        homeSubstitutes = finalHomeSubstitutes;
        awayPlayers = finalAwayPlayers;
        awaySubstitutes = finalAwaySubstitutes;
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

  Widget _buildSubstitutesContent(List<PlayerInfo> substitutes, Color teamColor) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListView.builder(
        itemCount: substitutes.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          final player = substitutes[index];
          return ListTile(
            dense: true,
            leading: PlayerAvatar(player: player, teamColor: teamColor, radius: 20),
            title: Text(player.name, style: TextStyle(fontSize: 12)),
            subtitle: Text('Pos: ${player.position}', style: TextStyle(fontSize: 10)),
            trailing: Text('Rating: ${player.rating}', style: TextStyle(fontSize: 12)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => PlayerScreen(playerId: player.id)),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heimTeamName = widget.spiel['heimteam']?['name'] ?? 'Team A';
    final auswaertsTeamName = widget.spiel['auswaertsteam']?['name'] ?? 'Team B';
    final homeFormation = widget.spiel['hometeam_formation'] ?? 'N/A';
    final awayFormation = widget.spiel['awayteam_formation'] ?? 'N/A';
    final homeColor = Colors.blue.shade700; // Heimteam-Farbe
    final awayColor = Colors.red.shade700;   // Auswärtsteam-Farbe

    return Scaffold(
      appBar: AppBar(
        title: Text("$heimTeamName vs $auswaertsTeamName"),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () async {
              setState(() => isLoading = true);
              await _dataManagement.updateRatingsForSingleGame(widget.spiel['id']);
              await fetchSpieler();
              if(mounted) {
                setState(() => isLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Daten wurden aktualisiert!')),
                );
              }
            },
          ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          // Spielfeld im Hintergrund
          Positioned.fill(
            bottom: 48, // Platz für die Bank-Titel
            child: (homePlayers.length >= 11 && awayPlayers.length >= 11)
                ? Center(
              child: MatchFormationDisplay(
                homeFormation: homeFormation,
                homePlayers: homePlayers,
                homeColor: homeColor,
                awayFormation: awayFormation,
                awayPlayers: awayPlayers,
                awayColor: awayColor,
                onPlayerTap: (playerId) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlayerScreen(playerId: playerId),
                    ),
                  );
                },
              ),
            )
                : Center(
              child: Text("Nicht genügend Spielerdaten für die Formationsanzeige."),
            ),
          ),

          // Ausgeklappte Bank-Inhalte (über dem Spielfeld)
          Positioned(
            bottom: 48, // Direkt über den Titeln
            left: 0,
            right: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) {
                return SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1.0,
                  child: child,
                );
              },
              child: _expandedBench == 'home'
                  ? _buildSubstitutesContent(homeSubstitutes, homeColor)
                  : _expandedBench == 'away'
                  ? _buildSubstitutesContent(awaySubstitutes, awayColor)
                  : const SizedBox.shrink(),
            ),
          ),

          // Klickbare Titel der Ersatzbänke am unteren Rand
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Row(
              children: [
                if (homeSubstitutes.isNotEmpty)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _expandedBench = (_expandedBench == 'home') ? null : 'home';
                        });
                      },
                      child: Card(
                        margin: EdgeInsets.zero,
                        elevation: 4,
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("Ersatzbank Heim", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              Icon(_expandedBench == 'home' ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (awaySubstitutes.isNotEmpty)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _expandedBench = (_expandedBench == 'away') ? null : 'away';
                        });
                      },
                      child: Card(
                        margin: EdgeInsets.zero,
                        elevation: 4,
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("Ersatzbank Auswärts", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                              Icon(_expandedBench == 'away' ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
