// lib/viewmodels/radar_chart_viewmodel.dart
import 'package:flutter/material.dart';
import 'package:premier_league/screens/screenelements/radial_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RadarChartResult {
  final List<GroupData> radarChartData;
  final double averagePlayerRatingPercentile;

  RadarChartResult({
    required this.radarChartData,
    required this.averagePlayerRatingPercentile,
  });
}

class RadarChartViewModel {
  final supabase = Supabase.instance.client;

  Future<RadarChartResult> calculateRadarChartData({
    required String comparisonPosition,
    required List<Map<String, dynamic>> matchRatings,
    required double averagePlayerRating,
  }) async {

    // --- Schritt 1: Durchschnittliche Stats des aktuellen Spielers berechnen ---
    Map<String, double> playerAverageStats = {};
    Map<String, double> playerTotalStats = {};
    for (var rating in matchRatings) {
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
    final int matchCount = matchRatings.length;
    if (matchCount > 0) {
      playerAverageStats =
          playerTotalStats.map((key, value) => MapEntry(key, value / matchCount));
    }

    // --- Schritt 2: Vergleichsdaten holen (FEHLER BEHOBEN: Ohne extra Quotes!) ---
    final allRatingsForPositionResponse = await supabase
        .from('matchrating')
        .select('spieler_id, statistics, punkte')
        .eq('match_position', comparisonPosition);

    // --- Schritt 3: Perzentil für die Gesamtbewertung berechnen ---
    final Map<int, List<double>> allPlayerPoints = {};
    for (var rating in allRatingsForPositionResponse) {
      final playerId = rating['spieler_id'] as int;
      final points = (rating['punkte'] as num? ?? 0.0).toDouble();
      allPlayerPoints.putIfAbsent(playerId, () => []).add(points);
    }
    final List<double> averagePointsPerPlayer =
    allPlayerPoints.values.map((points) {
      return points.reduce((a, b) => a + b) / points.length;
    }).toList();

    double calculatedPercentile = 0;
    if (averagePointsPerPlayer.isNotEmpty) {
      averagePointsPerPlayer.sort();
      int playersBetter = averagePointsPerPlayer
          .where((score) => score > averagePlayerRating)
          .length;
      calculatedPercentile =
          (1 - (playersBetter / averagePointsPerPlayer.length)) * 100.0;
    }

    // --- NEU: OPTIMIERUNG - Vergleichsdaten nur EINMAL vorberechnen ---
    final Map<int, Map<String, dynamic>> playerAggregates = {};
    for (var rating in allRatingsForPositionResponse) {
      final playerId = rating['spieler_id'] as int;
      final stats = rating['statistics'] as Map<String, dynamic>? ?? {};

      playerAggregates.putIfAbsent(playerId, () => {'total_stats': <String, double>{}, 'game_count': 0});
      final currentAggregates = playerAggregates[playerId]!;
      final currentTotalStats = currentAggregates['total_stats'] as Map<String, double>;

      stats.forEach((key, value) {
        double statValue = 0;
        if (value is num) {
          statValue = value.toDouble();
        } else if (value is Map && value.containsKey('total')) {
          statValue = (value['total'] as num? ?? 0).toDouble();
        }
        currentTotalStats[key] = (currentTotalStats[key] ?? 0.0) + statValue;
      });
      currentAggregates['game_count'] = (currentAggregates['game_count'] as int) + 1;
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

    // --- Schritt 4: Perzentil-Berechnung für einzelne Kategorien ---
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

      int playersBetter = allCategoryScores
          .where((score) => higherIsBetter
          ? score > currentPlayerCategoryScore
          : score < currentPlayerCategoryScore)
          .length;

      double percentile = (playersBetter / allCategoryScores.length) * 100.0;
      return 100.0 - percentile;
    }

    // --- Schritt 5: Radar-Chart-Daten finalisieren ---
    List<GroupData> finalRadarChartData;

    if (comparisonPosition == 'G' || comparisonPosition == 'TW') {
      finalRadarChartData = [
        GroupData(
          name: 'Torwartspiel',
          backgroundColor: Colors.cyan.withOpacity(0.12),
          segments: [
            SegmentData(name: 'Abgewehrte Schüsse', value: calculatePercentileRankForCategory({'saves': 1.0, 'punches' : 1.0})),
            SegmentData(name: 'Paraden', value: calculatePercentileRankForCategory({'savedShotsFromInsideTheBox': 1.0, 'goalsPrevented': 3.0, 'penaltySave' : 2.0})),
            SegmentData(name: 'Fehlerresistenz', value: calculatePercentileRankForCategory({'errorLeadToAShot': 1.0, 'errorLeadToAGoal' : 5.0, 'penaltyConceded' : 3.0}, higherIsBetter: false)),
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

    return RadarChartResult(
      radarChartData: finalRadarChartData,
      averagePlayerRatingPercentile: calculatedPercentile,
    );
  }
}