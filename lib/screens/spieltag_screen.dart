import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/screenelements/match_screen/matchrating_screen.dart';

// HomeScreen: Zeigt jetzt die Spiele für einen bestimmten Spieltag an.
class HomeScreen extends StatefulWidget {
  // FÜGE DIESE VARIABLE HINZU, um die Spieltagsnummer zu speichern
  final int round;

  // AKTUALISIERE DEN KONSTRUKTOR, um die Spieltagsnummer zu empfangen
  const HomeScreen({super.key, required this.round});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
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
    setState(() {
      isLoading = true;
    });

    try {
      // ✅ KORREKTUR: Abfrage um hometeam_formation und awayteam_formation erweitert
      final data = await Supabase.instance.client
          .from('spiel')
          .select(
          '*, heimteam_id, auswärtsteam_id, hometeam_formation, awayteam_formation, heimteam:spiel_heimteam_id_fkey(name), auswaertsteam:spiel_auswärtsteam_id_fkey(name)')
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
            SnackBar(content: Text('Fehler: ${error.toString()}')));
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
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: spiele.length,
        itemBuilder: (context, index) {
          final spiel = spiele[index];

          final heimTeamName = spiel['heimteam']['name'] ?? 'Unbekannt';
          final auswaertsTeamName =
              spiel['auswaertsteam']['name'] ?? 'Unbekannt';

          return ListTile(
            title: Text("$heimTeamName vs $auswaertsTeamName"),
            subtitle: Text("Ergebnis: ${spiel['ergebnis'] ?? 'N/A'}"),
            trailing: const Icon(Icons.arrow_forward),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => GameScreen(spiel: spiel)),
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
  const GameScreen({super.key, required this.spiel});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  List<PlayerInfo> homePlayers = [];
  List<PlayerInfo> homeSubstitutes = [];
  List<PlayerInfo> awayPlayers = [];
  List<PlayerInfo> awaySubstitutes = [];
  List<dynamic> data = [];
  bool isLoading = true;
  final DataManagement _dataManagement = DataManagement(); // Instanz erstellen

  String?
  _expandedBench; // Hält den Zustand, welche Bank ausgeklappt ist ('home' oder 'away')
  double playerAvatarRadiusOnField = 20.0; // Standardwert

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
      data = await Supabase.instance.client
          .from('spieler')
          .select(
          '*, profilbild_url, matchrating!inner(formationsindex, match_position, punkte, statistics)') // JOIN und punkte hinzugefügt
          .eq('matchrating.spiel_id', spielId)
          .filter('team_id', 'in', '($heimTeamId, $auswaertsTeamId)');

      print(
          "--- DEBUG: Rohdaten von Supabase erhalten (${data.length} Spieler) ---");
      // Logge die Rohdaten, um zu sehen, was ankommt
      for (var spieler in data) {
        final index = spieler['matchrating']?[0]?['formationsindex'];
        print(
            "Spieler: ${spieler['name']}, Team: ${spieler['team_id']}, Formationsindex: $index");
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
      tempHomePlayersData.forEach((p) => print(
          "Index: ${p['matchrating'][0]['formationsindex']}, Name: ${p['name']}"));
      print("----------------------------------------\n");

      print("\n--- DEBUG: Sortierte Auswärts-Mannschaft ---");
      tempAwayPlayersData.forEach((p) => print(
          "Index: ${p['matchrating'][0]['formationsindex']}, Name: ${p['name']}"));
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

      if (data.length != 40){
        _dataManagement.updateRatingsForSingleGame(spielId);
        fetchSpieler();
        return;
      }
      setState(() {
        homePlayers = finalHomePlayers;
        homeSubstitutes = finalHomeSubstitutes;
        awayPlayers = finalAwayPlayers;
        awaySubstitutes = finalAwaySubstitutes;
        isLoading = false;
      });

    } catch (error) {
      print("Fehler beim Abruf der Spieler: $error");
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Widget _buildSubstitutesContent(
      List<PlayerInfo> substitutes, Color teamColor) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListView.builder(
        itemCount: substitutes.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          final player = substitutes[index];
          return SubstitutePlayerRow(
            player: player,
            teamColor: teamColor,
            avatarRadius: playerAvatarRadiusOnField,
            onTap: () {
              final spielerDaten =
              data.firstWhere((element) => element['id'] == player.id);
              final matchStatistics =
              spielerDaten['matchrating'][0]['statistics'];
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return MatchRatingScreen(
                    playerInfo: player,
                    matchStatistics: matchStatistics,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heimTeamName = widget.spiel['heimteam']?['name'] ?? 'Team A';
    final auswaertsTeamName =
        widget.spiel['auswaertsteam']?['name'] ?? 'Team B';
    final homeFormation = widget.spiel['hometeam_formation'] ?? 'N/A';
    final awayFormation = widget.spiel['awayteam_formation'] ?? 'N/A';
    final homeColor = Colors.blue.shade700; // Heimteam-Farbe
    final awayColor = Colors.red.shade700; // Auswärtsteam-Farbe

    return Scaffold(
      appBar: AppBar(
        title: Text("$heimTeamName vs $auswaertsTeamName"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              setState(() => isLoading = true);
              await _dataManagement
                  .updateRatingsForSingleGame(widget.spiel['id']);
              await fetchSpieler();
              if (mounted) {
                setState(() => isLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Daten wurden aktualisiert!')),
                );
              }
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, constraints) {
        // Aktualisiere den Radius basierend auf der verfügbaren Breite
        playerAvatarRadiusOnField = constraints.maxHeight / 40;

        return Stack(
          children: [
            // Spielfeld im Hintergrund
            Positioned.fill(
              bottom: 48, // Platz für die Bank-Titel
              child: (homePlayers.length >= 11 &&
                  awayPlayers.length >= 11)
                  ? Center(
                  child: MatchFormationDisplay(
                    homeFormation: homeFormation,
                    homePlayers: homePlayers,
                    homeColor: homeColor,
                    awayFormation: awayFormation,
                    awayPlayers: awayPlayers,
                    awayColor: awayColor,
                    onPlayerTap: (player) {
                      final spielerDaten = data.firstWhere(
                              (element) => element['id'] == player.id);
                      final matchStatistics =
                      spielerDaten['matchrating'][0]['statistics'];
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return MatchRatingScreen(
                            playerInfo: player,
                            matchStatistics: matchStatistics,
                          );
                        },
                      );
                    },
                  ))
                  : const Center(
                child: Text(
                    "Nicht genügend Spielerdaten für die Formationsanzeige."),
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
                    ? _buildSubstitutesContent(
                    homeSubstitutes, homeColor)
                    : _expandedBench == 'away'
                    ? _buildSubstitutesContent(
                    awaySubstitutes, awayColor)
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
                            _expandedBench =
                            (_expandedBench == 'home') ? null : 'home';
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
                                const Text("Ersatzbank Heim",
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                Icon(_expandedBench == 'home'
                                    ? Icons.keyboard_arrow_down
                                    : Icons.keyboard_arrow_up),
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
                            _expandedBench =
                            (_expandedBench == 'away') ? null : 'away';
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
                                const Text("Ersatzbank Auswärts",
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                Icon(_expandedBench == 'away'
                                    ? Icons.keyboard_arrow_down
                                    : Icons.keyboard_arrow_up),
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
        );
      }),
    );
  }
}

/// Widget für eine einzelne Spieler-Zeile auf der Ersatzbank
class SubstitutePlayerRow extends StatelessWidget {
  final PlayerInfo player;
  final Color teamColor;
  final double avatarRadius;
  final VoidCallback onTap;

  const SubstitutePlayerRow({
    super.key,
    required this.player,
    required this.teamColor,
    required this.avatarRadius,
    required this.onTap,
  });

  Color _getColorForRating(int rating) {
    if (rating >= 150) return Colors.teal;
    if (rating >= 100) return Colors.green;
    if (rating >= 50) return Colors.yellow.shade700;
    return Colors.red;
  }

  Widget _buildEventIcon(IconData icon, Color color, int count) {
    if (count == 0) return const SizedBox.shrink();
    // Die Größe der Icons wird jetzt proportional zum avatarRadius berechnet
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Icon(icon, color: color, size: avatarRadius * 0.8),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isGoalkeeper =
        player.position.toUpperCase() == 'TW' || player.position.toUpperCase() == 'G';
    // Dynamische Schriftgrößen
    final double titleFontSize = avatarRadius * 0.8;
    final double ratingFontSize = avatarRadius * 0.8;

    return ListTile(
      dense: true,
      onTap: onTap,
      // Die Höhe der Zeile passt sich jetzt an die Größe des Avatars an
      visualDensity: VisualDensity(vertical: avatarRadius / 50),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16.0, // Horizontaler Abstand bleibt fest
        vertical: 0, // Vertikaler Abstand ist jetzt dynamisch
      ),
      leading: Container(
        width: avatarRadius * 2,
        height: avatarRadius * 2,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          shape: BoxShape.circle,
          border: Border.all(
            color: isGoalkeeper ? Colors.orange.shade700 : teamColor,
            width: 1,
          ),
          image: player.profileImageUrl != null
              ? DecorationImage(
            image: NetworkImage(player.profileImageUrl!),
            fit: BoxFit.cover, // WICHTIG: Verhindert das Abschneiden
          )
              : null,
        ),
        child: player.profileImageUrl == null
            ? Icon(Icons.person, color: Colors.white, size: avatarRadius * 1.2)
            : null,
      ),
      title: Row(
        children: [
          Text(player.name, style: TextStyle(fontSize: titleFontSize)),
          const SizedBox(width: 8),
          _buildEventIcon(Icons.sports_soccer, Colors.black, player.goals),
          _buildEventIcon(Icons.assistant, Colors.blue, player.assists),
          _buildEventIcon(Icons.sports_soccer, Colors.red, player.ownGoals),
        ],
      ),
      trailing: Container(
        padding: EdgeInsets.symmetric(
            horizontal: avatarRadius * 0.3, vertical: avatarRadius * 0.1),
        decoration: BoxDecoration(
          color: _getColorForRating(player.rating),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          player.rating.toString(),
          style: TextStyle(
            color: Colors.white,
            fontSize: ratingFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}