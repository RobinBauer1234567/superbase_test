import 'package:flutter/material.dart';
import 'package:premier_league/screens/screenelements/radial_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';

class MatchRatingScreen extends StatefulWidget {
  final PlayerInfo playerInfo;
  final Map<String, dynamic> matchStatistics;

  const MatchRatingScreen({
    super.key,
    required this.playerInfo,
    required this.matchStatistics,
  });

  @override
  _MatchRatingScreenState createState() => _MatchRatingScreenState();
}

class _MatchRatingScreenState extends State<MatchRatingScreen> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  List<GroupData> radarChartData = [];
  double averagePlayerRatingPercentile = 0.0;

  @override
  void initState() {
    super.initState();
    _calculateRadarChartData();
  }

  Future<void> _calculateRadarChartData() async {
    if (!mounted) return;

    final playerAverageStats =
    widget.matchStatistics.map((key, value) => MapEntry(key, (value is num) ? value.toDouble() : 0.0));

    final allRatingsForPositionResponse = await supabase
        .from('matchrating')
        .select('spieler_id, statistics, punkte')
        .eq('match_position', '"${widget.playerInfo.position}"');

    final Map<int, List<double>> allPlayerPoints = {};
    for (var rating in allRatingsForPositionResponse) {
      final playerId = rating['spieler_id'] as int;
      final points = (rating['punkte'] as num? ?? 0.0).toDouble();
      allPlayerPoints.putIfAbsent(playerId, () => []).add(points);
    }
    final List<double> averagePointsPerPlayer = allPlayerPoints.values.map((points) {
      return points.reduce((a, b) => a + b) / points.length;
    }).toList();

    double calculatedPercentile = 0;
    if (averagePointsPerPlayer.isNotEmpty) {
      averagePointsPerPlayer.sort();
      int playersBetter = averagePointsPerPlayer
          .where((score) => score > widget.playerInfo.rating)
          .length;
      calculatedPercentile =
          (1 - (playersBetter / averagePointsPerPlayer.length)) * 100.0;
    }

    // Perzentil-Berechnung für Kategorien
    double calculatePercentileRankForCategory(
        Map<String, double> weightedStatKeys,
        {bool higherIsBetter = true}) {
      double getCategoryScore(Map<String, double> stats) {
        double score = 0;
        weightedStatKeys.forEach((key, weight) {
          score += (stats[key] ?? 0.0) * weight;
        });
        return score;
      }

      final currentPlayerCategoryScore = getCategoryScore(playerAverageStats);

      final Map<int, Map<String, dynamic>> playerAggregates = {};
      for (var rating in allRatingsForPositionResponse) {
        final playerId = rating['spieler_id'] as int;
        final stats = rating['statistics'] as Map<String, dynamic>? ?? {};
        playerAggregates.putIfAbsent(
            playerId, () => {'total_stats': <String, double>{}, 'game_count': 0});
        final currentAggregates = playerAggregates[playerId]!;
        final currentTotalStats =
        currentAggregates['total_stats'] as Map<String, double>;
        stats.forEach((key, value) {
          double statValue = 0;
          if (value is num)
            statValue = value.toDouble();
          else if (value is Map && value.containsKey('total'))
            statValue = (value['total'] as num? ?? 0).toDouble();
          currentTotalStats[key] =
              (currentTotalStats[key] ?? 0.0) + statValue;
        });
        currentAggregates['game_count'] =
            (currentAggregates['game_count'] as int) + 1;
      }

      final comparisonPlayerAverages = <int, Map<String, double>>{};
      playerAggregates.forEach((playerId, data) {
        final totalStats = data['total_stats'] as Map<String, double>;
        final gameCount = data['game_count'] as int;
        if (gameCount > 0) {
          comparisonPlayerAverages[playerId] =
              totalStats.map((key, value) => MapEntry(key, value / gameCount));
        }
      });

      if (comparisonPlayerAverages.isEmpty) return 50.0;

      final allCategoryScores = comparisonPlayerAverages.values
          .map((playerStats) => getCategoryScore(playerStats))
          .toList();

      int playersBetter = allCategoryScores
          .where((score) => higherIsBetter
          ? score > currentPlayerCategoryScore
          : score < currentPlayerCategoryScore)
          .length;
      double percentile =
          (playersBetter / allCategoryScores.length) * 100.0;
      return 100.0 - percentile;
    }

    if (mounted) {
      List<GroupData> finalRadarChartData;
      String genericPosition = widget.playerInfo.position;

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
              }, higherIsBetter: false)),
            ],
          ),
        ];
      }

      setState(() {
        radarChartData = finalRadarChartData;
        averagePlayerRatingPercentile = calculatedPercentile;
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  ClipOval(
                    child: widget.playerInfo.profileImageUrl != null
                        ? Image.network(
                      widget.playerInfo.profileImageUrl!,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.error,
                            size: 80, color: Colors.red);
                      },
                    )
                        : const Icon(Icons.person, size: 80, color: Colors.grey),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.playerInfo.name,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        Text("Position: ${widget.playerInfo.position}",
                            style: const TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                padding: const EdgeInsets.all(16.0),
                child: RadialSegmentChart(
                  groups: radarChartData,
                  maxAbsValue: 100.0,
                  centerDisplayValue: widget.playerInfo.rating.round(),
                  centerComparisonValue: averagePlayerRatingPercentile,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}