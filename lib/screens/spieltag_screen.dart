import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/utils/color_helper.dart';

// Die HomeScreen-Klasse bleibt unverändert
class HomeScreen extends StatefulWidget {
  final int round;
  const HomeScreen({super.key, required this.round});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> spiele = [];
  bool isLoading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    fetchSpieleAndTeamNames();
  }

  Future<void> fetchSpieleAndTeamNames() async {
    if (!mounted) return;
    setState(() { isLoading = true; });
    final dataManagement = Provider.of<DataManagement>(context, listen: false);

    try {
      final data = await Supabase.instance.client
          .from('spiel')
          .select('*, heimteam:spiel_heimteam_id_fkey(name), auswaertsteam:spiel_auswärtsteam_id_fkey(name)')
          .eq('round', widget.round)
          .eq('season_id', dataManagement.seasonId)
          .order('id', ascending: true);

      if(mounted){
        setState(() {
          spiele = data;
          isLoading = false;
        });
      }
    } catch (error) {
      print("Fehler beim Abruf der Spiele: $error");
      if(mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Die Build-Methode von HomeScreen bleibt unverändert
    return Scaffold(
      appBar: AppBar(title: Text('Spieltag ${widget.round}')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: spiele.length,
        itemBuilder: (context, index) {
          final spiel = spiele[index];
          final heimTeamName = spiel['heimteam']['name'] ?? 'Unbekannt';
          final auswaertsTeamName = spiel['auswaertsteam']['name'] ?? 'Unbekannt';
          return ListTile(
            title: Text("$heimTeamName vs $auswaertsTeamName"),
            subtitle: Text("Ergebnis: ${spiel['ergebnis'] ?? 'N/A'}"),
            trailing: const Icon(Icons.arrow_forward),
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
  const GameScreen({super.key, required this.spiel});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  List<PlayerInfo> homePlayers = [];
  List<PlayerInfo> homeSubstitutes = [];
  List<PlayerInfo> awayPlayers = [];
  List<PlayerInfo> awaySubstitutes = [];
  bool isLoading = true;
  bool _isInit = true;
  String? _expandedBench;
  double playerAvatarRadiusOnField = 20.0;
  late Map<String, dynamic> currentSpielData; // NEU: Eine lokale Kopie des Spiels
  @override
  void initState() {
    super.initState();
    currentSpielData = Map<String, dynamic>.from(widget.spiel);
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Wir rufen die Lade-Logik nur beim allerersten Aufbau des Screens auf
    if (_isInit) {
      _loadMatchData();
      _isInit = false;
    }
  }
  Future<void> _loadMatchData() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final dataManagement = Provider.of<DataManagement>(context, listen: false);
      final spielId = currentSpielData['id'];
      final status = currentSpielData['status'];

      await dataManagement.updateRatingsForSingleGame(spielId, status);

      final updatedSpiel = await Supabase.instance.client
          .from('spiel')
          .select('hometeam_formation, awayteam_formation')
          .eq('id', spielId)
          .single();

      if (mounted) {
        setState(() {
          currentSpielData['hometeam_formation'] = updatedSpiel['hometeam_formation'];
          currentSpielData['awayteam_formation'] = updatedSpiel['awayteam_formation'];
        });
      }

      await fetchSpieler();

    } catch (e) {
      print("❌ Fehler in _loadMatchData: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> fetchSpieler() async {
    if (!mounted) return;

    List<PlayerInfo> finalHomePlayers = [];
    List<PlayerInfo> finalHomeSubstitutes = [];
    List<PlayerInfo> finalAwayPlayers = [];
    List<PlayerInfo> finalAwaySubstitutes = [];

    try {
      final heimTeamId = currentSpielData['heimteam_id'];
      final spielId = currentSpielData['id'];


      int versuch = 0;
      const maxVersuche = 3;

      while (versuch < maxVersuche) {
        versuch++;

        final response = await Supabase.instance.client
            .from('matchrating')
            .select('*, spieler!inner(*)')
            .eq('spiel_id', spielId);

        final List<dynamic> ratingsData = response as List<dynamic>;

        List<Map<String, dynamic>> homeRatings = [];
        List<Map<String, dynamic>> awayRatings = [];

        for (var entry in ratingsData) {
          final spieler = entry['spieler'];
          if (spieler == null) continue;

          final int playerTeamId = spieler['team_id'];

          final processedPlayer = {
            'id': spieler['id'],
            'name': spieler['name'],
            'profilbild_url': spieler['profilbild_url'],
            'team_id': playerTeamId,
            'matchrating': entry
          };

          if (playerTeamId == heimTeamId) {
            homeRatings.add(processedPlayer);
          } else {
            awayRatings.add(processedPlayer);
          }
        }

        int sortByIndex(Map<String, dynamic> a, Map<String, dynamic> b) {
          final idxA = a['matchrating']['formationsindex'] ?? 99;
          final idxB = b['matchrating']['formationsindex'] ?? 99;
          return idxA.compareTo(idxB);
        }
        homeRatings.sort(sortByIndex);
        awayRatings.sort(sortByIndex);


        int homeStarters = homeRatings.where((p) => (p['matchrating']['formationsindex'] ?? 99) < 11).length;
        int awayStarters = awayRatings.where((p) => (p['matchrating']['formationsindex'] ?? 99) < 11).length;

        if (homeStarters >= 10 && awayStarters >= 10) {
          PlayerInfo mapToInfo(Map<String, dynamic> p) {
            final mr = p['matchrating'];
            final stats = mr['statistics'] ?? {};
            return PlayerInfo(
              id: p['id'],
              name: p['name'],
              position: mr['match_position'] ?? 'N/A',
              rating: mr['punkte'],
              profileImageUrl: p['profilbild_url'],
              goals: (stats['goals'] as int?) ?? 0,
              assists: (stats['assists'] as int?) ?? 0,
              ownGoals: (stats['ownGoals'] as int?) ?? 0,
            );
          }

          finalHomePlayers = homeRatings.where((p) => p['matchrating']['formationsindex'] < 11).map(mapToInfo).toList();
          finalHomeSubstitutes = homeRatings.where((p) => p['matchrating']['formationsindex'] >= 11).map(mapToInfo).toList();
          finalAwayPlayers = awayRatings.where((p) => p['matchrating']['formationsindex'] < 11).map(mapToInfo).toList();
          finalAwaySubstitutes = awayRatings.where((p) => p['matchrating']['formationsindex'] >= 11).map(mapToInfo).toList();

          break;
        }

        if (versuch < maxVersuche) {
          await Future.delayed(Duration(milliseconds: 500 * versuch));
        }
      }

      if (!mounted) return;
      setState(() {
        homePlayers = finalHomePlayers;
        homeSubstitutes = finalHomeSubstitutes;
        awayPlayers = finalAwayPlayers;
        awaySubstitutes = finalAwaySubstitutes;
        isLoading = false;
      });

    } catch (e) {
      print("❌ Fehler: $e");
      if (mounted) setState(() => isLoading = false);
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
          return SubstitutePlayerRow(
            player: player,
            teamColor: teamColor,
            avatarRadius: playerAvatarRadiusOnField,
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
    final heimTeamName = currentSpielData['heimteam']?['name'] ?? 'Team A';
    final auswaertsTeamName = currentSpielData['auswaertsteam']?['name'] ?? 'Team B';
    final homeFormation = currentSpielData['hometeam_formation'] ?? 'N/A';
    final awayFormation = currentSpielData['awayteam_formation'] ?? 'N/A';
    final homeColor = Colors.blue.shade700;
    final awayColor = Colors.red.shade700;


    return Scaffold(
      appBar: AppBar(
        title: Text("$heimTeamName vs $auswaertsTeamName"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadMatchData();
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
          builder: (context, constraints) {
            // Aktualisiere den Radius basierend auf der verfügbaren Breite
            playerAvatarRadiusOnField = constraints.maxHeight / 40;

            return Stack(
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
                      onPlayerTap: (playerId, radius) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PlayerScreen(playerId: playerId),
                          ),
                        );
                      },
                    ),
                  )
                      : const Center(
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
                                    const Text("Ersatzbank Heim", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
                                    const Text("Ersatzbank Auswärts", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
            );
          }
      ),
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


  Widget _buildEventIcon(IconData icon, Color color, int count) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Icon(icon, color: color, size: avatarRadius * 0.8),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isGoalkeeper = player.position.toUpperCase() == 'TW' || player.position.toUpperCase() == 'G';
    // Dynamische Schriftgrößen
    final double titleFontSize = avatarRadius * 0.8;
    final double ratingFontSize = avatarRadius * 0.8;

    return ListTile(
      dense: true,
      onTap: onTap,
      // Die Höhe der Zeile passt sich jetzt an die Größe des Avatars an
      visualDensity: VisualDensity(vertical: avatarRadius / 50 ),
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
        padding: EdgeInsets.symmetric(horizontal: avatarRadius * 0.3, vertical: avatarRadius * 0.1),
        decoration: BoxDecoration(
          color: getColorForRating(player.rating, 250),
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
