import 'package:flutter/material.dart';
import 'package:premier_league/screens/screenelements/radial_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

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

  // Player Info
  String playerName = "";
  String teamName = "";
  String? profileImageUrl;

  // Data for views
  bool isLoading = true;
  List<dynamic> matchRatingsRaw = [];
  List<GroupData> radarChartData = [];

  // ✅ NEUE STATE-VARIABLEN
  List<String> availablePositions = [];
  String? selectedPosition;
  double averagePlayerRating = 0.0;
  double averagePlayerRatingPercentile = 0.0; // Der neue Vergleichswert

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    fetchPlayerData();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
          .select('name')
          .eq('id', playerResponse['team_id'])
          .single();

      final matchRatingsResponse = await supabase
          .from('matchrating')
          .select('spiel_id, punkte, statistics')
          .eq('spieler_id', widget.playerId);

      if (!mounted) return;

      String rawPositions = playerResponse['position'] ?? 'N/A';
      List<String> parsedPositions = rawPositions.split(',').map((p) =>
          p.trim()).toList();

      double totalRating = 0;
      for (var rating in matchRatingsResponse) {
        totalRating += (rating['punkte'] as num? ?? 0.0).toDouble();
      }

      setState(() {
        playerName = playerResponse['name'];
        teamName = teamResponse['name'];
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

      if (selectedPosition != null) {
        await _calculateRadarChartData(selectedPosition!);
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


  Future<void> _calculateRadarChartData(String comparisonPosition) async {
    if (!mounted) return;

    // --- Schritt 1 & 2: Datenbeschaffung ---
    // (Bleibt größtenteils gleich, aber fügen die Berechnung für den Perzentilwert hinzu)

    // Durchschnittliche Stats des aktuellen Spielers
    Map<String, double> playerAverageStats = {};
    Map<String, double> playerTotalStats = {};
    for (var rating in matchRatingsRaw) {
      final stats = rating['statistics'] as Map<String, dynamic>? ?? {};
      stats.forEach((key, value) {
        double statValue = 0;
        if (value is num) {
          statValue = value.toDouble();
        } else if (value is Map && value.containsKey('total')) {
          statValue = (value['total'] as num? ?? 0).toDouble();
        }
        playerTotalStats[key] = (playerTotalStats[key] ?? 0.0) + statValue;
      });
    }
    final int matchCount = matchRatingsRaw.length;
    if (matchCount > 0) {
      playerAverageStats = playerTotalStats.map((key, value) => MapEntry(key, value / matchCount));
    }


    // ✅ DATEN FÜR VERGLEICH ALLER SPIELER HOLEN
    final allRatingsForPositionResponse = await supabase
        .from('matchrating')
        .select('spieler_id, statistics, punkte') // 'punkte' mit abfragen
        .eq('match_position', '"$comparisonPosition"');


    // Durchschnittswerte für alle Vergleichsspieler berechnen
    Map<int, Map<String, double>> comparisonPlayerAverages = {};
    final Map<int, Map<String, dynamic>> playerAggregates = {};

    // ✅ Durchschnittliche Punktzahl für alle Vergleichsspieler berechnen
    final Map<int, List<double>> allPlayerPoints = {};
    for (var rating in allRatingsForPositionResponse) {
      final playerId = rating['spieler_id'] as int;
      final points = (rating['punkte'] as num? ?? 0.0).toDouble();
      allPlayerPoints.putIfAbsent(playerId, () => []).add(points);
    }
    final List<double> averagePointsPerPlayer = allPlayerPoints.values.map((points) {
      return points.reduce((a, b) => a + b) / points.length;
    }).toList();

    // ✅ PERZENTIL FÜR DIE MITTE BERECHNEN
    double calculatedPercentile = 0;
    if (averagePointsPerPlayer.isNotEmpty) {
      averagePointsPerPlayer.sort();
      int playersBetter = averagePointsPerPlayer.where((score) => score > averagePlayerRating).length;
      calculatedPercentile = (1 - (playersBetter / averagePointsPerPlayer.length)) * 100.0;
    }


    for (var rating in allRatingsForPositionResponse) {
      final playerId = rating['spieler_id'] as int;
      final stats = rating['statistics'] as Map<String, dynamic>? ?? {};
      playerAggregates.putIfAbsent(playerId, () => {'total_stats': <String, double>{}, 'game_count': 0});
      final currentAggregates = playerAggregates[playerId]!;
      final currentTotalStats = currentAggregates['total_stats'] as Map<String, double>;
      stats.forEach((key, value) {
        double statValue = 0;
        if (value is num) statValue = value.toDouble();
        else if (value is Map && value.containsKey('total')) statValue = (value['total'] as num? ?? 0).toDouble();
        currentTotalStats[key] = (currentTotalStats[key] ?? 0.0) + statValue;
      });
      currentAggregates['game_count'] = (currentAggregates['game_count'] as int) + 1;
    }
    playerAggregates.forEach((playerId, data) {
      final totalStats = data['total_stats'] as Map<String, double>;
      final gameCount = data['game_count'] as int;
      if (gameCount > 0) {
        comparisonPlayerAverages[playerId] = totalStats.map((key, value) => MapEntry(key, value / gameCount));
      }
    });

    // --- Schritt 3: Perzentil-Berechnung (bleibt gleich) ---
    double calculatePercentileRankForCategory(Map<String, double> weightedStatKeys, {bool higherIsBetter = true}) {
      double getCategoryScore(Map<String, double> stats) {
        double score = 0;
        weightedStatKeys.forEach((key, weight) {
          score += (stats[key] ?? 0.0) * weight;
        });
        return score;
      }

      final currentPlayerCategoryScore = getCategoryScore(playerAverageStats);
      if (comparisonPlayerAverages.isEmpty) return 50.0;

      final allCategoryScores = comparisonPlayerAverages.values
          .map((playerStats) => getCategoryScore(playerStats))
          .toList();

      int playersBetter = allCategoryScores.where((score) => higherIsBetter ? score > currentPlayerCategoryScore : score < currentPlayerCategoryScore).length;
      double percentile = (playersBetter / allCategoryScores.length) * 100.0;
      return 100.0 - percentile;
    }

    // --- Schritt 4 & 5: Radar-Chart-Daten erstellen (bleibt gleich) ---
    if (mounted) {
      List<GroupData> finalRadarChartData;
      String genericPosition = availablePositions.first.trim();

      if (genericPosition == 'G' || genericPosition == 'TW') {
        finalRadarChartData = [
          GroupData(
            name: 'Torwartspiel',
            backgroundColor: Colors.cyan.withOpacity(0.12),
            segments: [
              SegmentData(name: 'Abgewehrte Schüsse', value: calculatePercentileRankForCategory({'saves': 1.0, 'punches' : 1.0})),
              SegmentData(name: 'Paraden', value: calculatePercentileRankForCategory({'savedShotsFromInsideTheBox': 1.0, 'goalsPrevented': 3.0, 'penaltySave' : 2.0})),
              SegmentData(name: 'Fehlerressistenz', value: calculatePercentileRankForCategory({'errorLeadToAShot': 1.0, 'errorLeadToAGoal' : 5.0, 'penaltyConceded' : 3.0}, higherIsBetter: false)),
            ],
          ),
          GroupData(
            name: 'Strafraumbeherrschung',
            backgroundColor: Colors.green.withOpacity(0.12),
            segments: [
              SegmentData(name: 'Hohe Bälle', value: calculatePercentileRankForCategory({'goodHighClaim': 1.0, 'aerialWon': 1.0, 'aerialLost' : -1.0})),
              SegmentData(name: 'Herauslaufen', value: calculatePercentileRankForCategory({'accurateKeeperSweeper': 2.0, 'totalKeeperSweeper' : -1.0, 'totalTackle' : 2.0, 'lastManTackle' : 5.0, 'interceptionWon' : 2.0})),
            ],
          ),
          GroupData(
            name: 'Ballverteilung',
            backgroundColor: Colors.orange.withOpacity(0.12),
            segments: [
              SegmentData(name: 'Ballbesitz', value: calculatePercentileRankForCategory({'touches': 2.0, 'dispossessed': -5.0})),
              SegmentData(name: 'Passspiel', value: calculatePercentileRankForCategory({'accurateLongBalls': 4.0, 'totalLongBalls' : -1.0,'accuratePass': 2.0, 'totalPass': -1.0, 'bigChanceCreated' : 10.0, 'keyPass' : 5.0})),
            ],
          ),
        ];
      } else {
        finalRadarChartData = [
          GroupData(
            name: 'Schießen',
            backgroundColor: Colors.blue.withOpacity(0.12),
            segments: [
              SegmentData(
                  name: 'Abschlussvolumen',
                  value: calculatePercentileRankForCategory({
                    'onTargetScoringAttempt': 1.0,
                    'blockedScoringAttempt': 1.0,
                    'shotOffTarget': 1.0,
                    'hitWoodwork': 1.0,
                  })
              ),
              SegmentData(
                  name: 'Abschlussqualität',
                  value: calculatePercentileRankForCategory({
                    'goals': 10.0,
                    'expectedGoals' : -5.0,
                    'bigChanceMissed' : -3.0,
                    'onTargetScoringAttempt' : 1.0,
                    'blockedScoringAttempt' : 1.0,
                    'hitWoodwork' : 1.0,
                    'penaltyMiss' : -5.0,
                    'shotOffTarget' : 1.0
                  })
              ),
            ],
          ),
          GroupData(
            name: 'Passen',
            backgroundColor: Colors.green.withOpacity(0.12),
            segments: [
              SegmentData(name: 'Passvolumen', value: calculatePercentileRankForCategory({'totalPass': 1.0})),
              SegmentData(
                  name: 'Passsicherheit',
                  value: calculatePercentileRankForCategory({
                    'accuratePass': 1.0,
                    'possessionLostCtrl': -1.0,
                    'accurateCross' : 1.5,
                    'accurateLongBalls' : 1.5
                  })
              ),
              SegmentData(name: 'Kreative Pässe', value: calculatePercentileRankForCategory({
                'keyPass': 1.5,
                'bigChanceCreated': 1.5,
                'expectedAssists': 1.0,
                'goalAssist' : 1.0,
              })),
            ],
          ),
          GroupData(
            name: 'Duelle',
            backgroundColor: Colors.orange.withOpacity(0.12),
            segments: [
              SegmentData(name: 'Zweikampfaktivität', value: calculatePercentileRankForCategory({
                'duelWon': 1.0,
                'duelLost': 1.0,
                'aerialWon': 1.0,
                'aerialLost': 1.0
              })),
              SegmentData(name: 'Zweikämpferfolg', value: calculatePercentileRankForCategory({
                'duelWon': 1.0,
                'duelLost': -1.0,
                'aerialWon': 1.0,
                'aerialLost': -1.0

              })),
              SegmentData(name: 'Foulstatistik', value: calculatePercentileRankForCategory({
                'fouls': -1.0,
                'wasFouled' : 1.0,
                'penaltyWon' : 5.0,
                'penaltyConceded' : -5.0
              })),
            ],
          ),
          GroupData(
            name: 'Ballbesitz',
            backgroundColor: Colors.red.withOpacity(0.12),
            segments: [
              SegmentData(name: 'Ballaktionen', value: calculatePercentileRankForCategory({
                'touches': 2.0,
                'wonContest' : 1.0
              })),
              SegmentData(name: 'Ballsicherheit', value: calculatePercentileRankForCategory({
                'dispossessed': -1.0,
                'possessionLostCtrl': -1.0,
                'challengeLost' : -1.0,
                'totalOffside' : -1.0
              })),
              SegmentData(name: 'Ballgewinne', value: calculatePercentileRankForCategory({
                'interceptionWon': 1.0
              })),
            ],
          ),
          GroupData(
            name: 'Defensive',
            backgroundColor: Colors.purple.withOpacity(0.12),
            segments: [
              SegmentData(name: 'Tacklings', value: calculatePercentileRankForCategory({
                'totalTackle': 1.0,
                'lastManTackle': 20.0
              })),
              SegmentData(name: 'Klärende Aktionen', value: calculatePercentileRankForCategory({
                'totalClearance': 1.0,
                'outfielderBlock': 1.0,
                'clearanceOffLine': 20
              })),
              SegmentData(name: 'Fehlerresistenz', value: calculatePercentileRankForCategory({
                'errorLeadToAGoal': 5.0,
                'errorLeadToAShot': 1.0,
                'ownGoals': 3.0
              }, higherIsBetter: false)), // Fehler werden als "niedriger ist besser" markiert
            ],
          ),
        ];
      }


      setState(() {
        radarChartData = finalRadarChartData;
        averagePlayerRatingPercentile = calculatedPercentile; // ✅ State aktualisieren
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
                Center(
                  child: ClipOval(
                    child: profileImageUrl != null
                        ? Image.network(
                      profileImageUrl!,
                      width: 150,
                      height: 150,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.error, size: 120, color: Colors
                            .red);
                      },
                    )
                        : const Icon(
                        Icons.person, size: 120, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 16),
                Text("Team: $teamName", style: const TextStyle(fontSize: 18)),
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
                    ? const Center(child: Text("Keine Bewertungen vorhanden"))
                    : ListView(
                  children: matchRatingsRaw.map((rating) {
                    return ListTile(
                      title: Text("Match ID: ${rating['spiel_id']}"),
                      trailing: Text("Rating: ${(rating['punkte'] as num)
                          .toDouble()
                          .toStringAsFixed(1)}"),
                    );
                  }).toList(),
                ),
                radarChartData.isEmpty
                    ? const Center(child: Text("Statistiken nicht verfügbar."))
                    : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8.0, horizontal: 16.0),
                      child: DropdownButton<String>(
                        value: selectedPosition,
                        isExpanded: true,
                        hint: const Text("Vergleichsposition wählen"),
                        items: availablePositions.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (newValue) {
                          if (newValue != null) {
                            setState(() {
                              selectedPosition = newValue;
                              isLoading = true;
                            });
                            _calculateRadarChartData(newValue);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        // ✅ BEIDE WERTE AN DAS DIAGRAMM ÜBERGEBEN
                        child: RadialSegmentChart(
                          groups: radarChartData,
                          maxAbsValue: 100.0,
                          centerDisplayValue: averagePlayerRating.round(),
                          centerComparisonValue: averagePlayerRatingPercentile,
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