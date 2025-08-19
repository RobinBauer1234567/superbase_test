import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Import für die Datumsformatierung
import 'package:premier_league/screens/screenelements/radial_chart.dart';
import 'package:premier_league/screens/spieltag_screen.dart';
import 'package:premier_league/viewmodels/radar_chart_viewmodel.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/screens/screenelements/match_screen/matchrating_screen.dart';


class PlayerScreen extends StatefulWidget {
  final int playerId;

  const PlayerScreen({super.key, required this.playerId});

  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;
  late TabController _tabController;
  final RadarChartViewModel _radarChartViewModel = RadarChartViewModel();
  final ScrollController _scrollController = ScrollController(); // Controller für das Scrollen

  // Player Info
  String playerName = "";
  String teamName = "";
  String? profileImageUrl;
  String? teamImageUrl;

  // Data for views
  bool isLoading = true;
  List<dynamic> matchRatingsRaw = [];
  List<GroupData> radarChartData = [];

  // NEUE STATE-VARIABLEN
  List<String> availablePositions = [];
  String? selectedPosition;
  double averagePlayerRating = 0.0;
  double averagePlayerRatingPercentile = 0.0; // Der neue Vergleichswert

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 0) {
        _scrollToBottom();
      }
    });
    fetchPlayerData();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }


  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> fetchPlayerData() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
    });

    try {
      final playerResponse = await supabase
          .from('spieler')
          .select('name, position, team_id, profilbild_url')
          .eq('id', widget.playerId)
          .single();

      final teamResponse = await supabase
          .from('team')
          .select('name, image_url')
          .eq('id', playerResponse['team_id'])
          .single();

      final matchRatingsResponse = await supabase
          .from('matchrating')
          .select(
          'match_position, punkte, statistics, spiel:spiel!inner(id, datum, ergebnis, heimteam_id, auswärtsteam_id, hometeam_formation, awayteam_formation, heimteam:team!spiel_heimteam_id_fkey(name, image_url), auswaertsteam:team!spiel_auswärtsteam_id_fkey(name, image_url))')
          .eq('spieler_id', widget.playerId);


      if (!mounted) return;

      matchRatingsResponse.sort((a, b) {
        final dateA = DateTime.parse(a['spiel']['datum']);
        final dateB = DateTime.parse(b['spiel']['datum']);
        return dateA.compareTo(dateB);
      });


      String rawPositions = playerResponse['position'] ?? 'N/A';
      List<String> parsedPositions =
      rawPositions.split(',').map((p) => p.trim()).toList();

      double totalRating = 0;
      for (var rating in matchRatingsResponse) {
        totalRating += (rating['punkte'] as num? ?? 0.0).toDouble();
      }

      setState(() {
        playerName = playerResponse['name'];
        teamName = teamResponse['name'];
        teamImageUrl = teamResponse['image_url'];
        profileImageUrl = playerResponse['profilbild_url'] ??
            'https://rcfetlzldccwjnuabfgj.supabase.co/storage/v1/object/public/spielerbilder//Photo-Missing.png';
        matchRatingsRaw = matchRatingsResponse;
        availablePositions = parsedPositions;

        if (parsedPositions.isNotEmpty) {
          selectedPosition = parsedPositions.last;
        }
        if (matchRatingsResponse.isNotEmpty) {
          averagePlayerRating = totalRating / matchRatingsResponse.length;
        } else {
          averagePlayerRating = 0;
        }
      });

      _scrollToBottom();


      if (selectedPosition != null) {
        await _triggerRadarChartCalculation(selectedPosition!);
      } else {
        setState(() => isLoading = false);
      }
    } catch (error) {
      print("Fehler beim Laden der Spielerdaten: $error");
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _triggerRadarChartCalculation(String comparisonPosition) async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
    });

    final result = await _radarChartViewModel.calculateRadarChartData(
      comparisonPosition: comparisonPosition,
      matchRatings: List<Map<String, dynamic>>.from(matchRatingsRaw),
      averagePlayerRating: averagePlayerRating,
    );

    if (mounted) {
      setState(() {
        radarChartData = result.radarChartData;
        averagePlayerRatingPercentile = result.averagePlayerRatingPercentile;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(playerName.isNotEmpty ? playerName : "Spieler lädt..."),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // ✅ NEUES LAYOUT für Spielerbild und Wappen
                SizedBox(
                  height: 150, // Höhe des Spielerbilds
                  child: Row(
                    children: [
                      // Linker, unsichtbarer Bereich, um das Wappen zu positionieren
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Opacity(
                            opacity: 0.4,
                            child: teamImageUrl != null
                                ? Image.network(
                              teamImageUrl!,
                              width: 120,
                              height: 120,
                              fit: BoxFit.contain,
                            )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),

                      // Zentrales Spielerbild
                      ClipOval(
                        child: profileImageUrl != null
                            ? Image.network(
                          profileImageUrl!,
                          width: 150,
                          height: 150,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.error, size: 120, color: Colors.red);
                          },
                        )
                            : const Icon(Icons.person, size: 120, color: Colors.grey),
                      ),

                      // Rechter, unsichtbarer Bereich, um die Zentrierung zu gewährleisten
                      Expanded(flex: 2, child: Container()),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text("Team: $teamName",
                    style: const TextStyle(fontSize: 18)),
                Text("Positionen: ${availablePositions.join(', ')}",
                    style: const TextStyle(fontSize: 18)),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Match Ratings'),
              Tab(text: 'Radar Chart'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                matchRatingsRaw.isEmpty
                    ? const Center(
                    child: Text("Keine Bewertungen vorhanden"))
                    : ListView.builder(
                  controller: _scrollController,
                  itemCount: matchRatingsRaw.length,
                  itemBuilder: (context, index) {
                    final rating = matchRatingsRaw[index];
                    return MatchRatingRow(
                      rating: rating,
                      playerId: widget.playerId,
                      playerName: playerName,
                      playerProfileImageUrl: profileImageUrl,
                    );
                  },
                ),
                radarChartData.isEmpty
                    ? const Center(
                    child: Text("Statistiken nicht verfügbar."))
                    : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8.0, horizontal: 16.0),
                      child: DropdownButton<String>(
                        value: selectedPosition,
                        isExpanded: true,
                        hint: const Text("Vergleichsposition wählen"),
                        items:
                        availablePositions.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (newValue) {
                          if (newValue != null) {
                            setState(() {
                              selectedPosition = newValue;
                            });
                            _triggerRadarChartCalculation(newValue);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: RadialSegmentChart(
                          groups: radarChartData,
                          maxAbsValue: 100.0,
                          centerDisplayValue:
                          averagePlayerRating.round(),
                          centerComparisonValue:
                          averagePlayerRatingPercentile,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MatchRatingRow extends StatelessWidget {
  final Map<String, dynamic> rating;
  final int playerId;
  final String playerName;
  final String? playerProfileImageUrl;

  const MatchRatingRow({
    super.key,
    required this.rating,
    required this.playerId,
    required this.playerName,
    this.playerProfileImageUrl,
  });

  Color _getColorForRating(int rating) {
    if (rating >= 150) return Colors.teal;
    if (rating >= 100) return Colors.green;
    if (rating >= 50) return Colors.yellow.shade700;
    return Colors.red;
  }

  Widget _buildEventIcon(IconData icon, Color color, int count) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1.0),
      child: Icon(icon, color: color, size: 14),
    );
  }


  @override
  Widget build(BuildContext context) {
    final spiel = rating['spiel'];
    final stats = rating['statistics'] as Map<String, dynamic>? ?? {};
    final heimTeam = spiel['heimteam'];
    final auswaertsTeam = spiel['auswaertsteam'];
    final ergebnis = spiel['ergebnis'] ?? 'N/A';
    final punkte = rating['punkte'] ?? 0;
    final minutesPlayed = stats['minutesPlayed'] ?? 0;
    final goals = stats['goals'] ?? 0;
    final assists = stats['assists'] ?? 0;
    final ownGoals = stats['ownGoals'] ?? 0;

    final datumString = spiel['datum'] ?? '';
    final datum = DateTime.tryParse(datumString);
    final formattedDate =
    datum != null ? DateFormat('dd.MM.yy').format(datum) : 'N/A';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GameScreen(spiel: spiel),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  formattedDate,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showTeamNames = constraints.maxWidth > 180;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (showTeamNames)
                          Expanded(
                            child: Text(
                              heimTeam['name'] ?? '?',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (showTeamNames) const SizedBox(width: 8),
                        _TeamCrest(imageUrl: heimTeam['image_url']),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Text(
                            ergebnis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        _TeamCrest(imageUrl: auswaertsTeam['image_url']),
                        if (showTeamNames) const SizedBox(width: 8),
                        if (showTeamNames)
                          Expanded(
                            child: Text(
                              auswaertsTeam['name'] ?? '?',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.left,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              GestureDetector(
                onTap: () {
                  final playerInfoForMatch = PlayerInfo(
                    id: playerId,
                    name: playerName,
                    position: rating['match_position'] ?? 'N/A',
                    profileImageUrl: playerProfileImageUrl,
                    rating: punkte,
                    goals: goals,
                    assists: assists,
                    ownGoals: ownGoals,
                  );
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return MatchRatingScreen(
                        playerInfo: playerInfoForMatch,
                        matchStatistics: stats,
                      );
                    },
                  );
                },
                child: Container(
                  color: Colors.transparent,
                  width: 90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 14, color: Colors.grey.shade700),
                          const SizedBox(width: 4),
                          Text("$minutesPlayed'", style: const TextStyle(fontSize: 12)),
                          const Spacer(),
                          _buildEventIcon(Icons.sports_soccer, Colors.black, goals),
                          _buildEventIcon(Icons.assistant, Colors.blue, assists),
                          _buildEventIcon(Icons.sports_soccer, Colors.red, ownGoals),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 40,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: _getColorForRating(punkte),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          punkte.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Helfer-Widget für die Team-Wappen
class _TeamCrest extends StatelessWidget {
  final String? imageUrl;
  const _TeamCrest({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: imageUrl != null
          ? Image.network(
        imageUrl!,
        errorBuilder: (context, error, stackTrace) =>
        const Icon(Icons.shield, color: Colors.grey, size: 24),
      )
          : const Icon(Icons.shield, color: Colors.grey, size: 24),
    );
  }
}