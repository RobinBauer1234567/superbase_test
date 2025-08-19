import 'package:flutter/material.dart';
import 'package:premier_league/screens/screenelements/radial_chart.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/viewmodels/radar_chart_viewmodel.dart'; // ViewModel importieren

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
  bool isLoading = true;
  RadarChartResult? _radarChartResult; // Ergebnisobjekt statt einzelner Listen
  final RadarChartViewModel _viewModel = RadarChartViewModel();

  @override
  void initState() {
    super.initState();
    _triggerCalculation();
  }

  Future<void> _triggerCalculation() async {
    if (!mounted) return;

    // Wir erstellen ein "künstliches" matchRatings-Array, das nur dieses eine Spiel enthält
    final singleMatchRating = {
      "punkte": widget.playerInfo.rating,
      "statistics": widget.matchStatistics,
    };

    final result = await _viewModel.calculateRadarChartData(
      comparisonPosition: widget.playerInfo.position,
      matchRatings: [singleMatchRating], // Hier wird nur die eine Statistik übergeben
      averagePlayerRating: widget.playerInfo.rating.toDouble(),
    );

    if (mounted) {
      setState(() {
        _radarChartResult = result;
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
            GestureDetector(
              onTap: () {
                // Navigator.pop(context); // Schließt den Dialog zuerst
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) =>
                          PlayerScreen(playerId: widget.playerInfo.id)),
                );
              },
              child: Padding(
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
                          : const Icon(Icons.person,
                          size: 80, color: Colors.grey),
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
            ),
            Expanded(
              child: isLoading || _radarChartResult == null
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                padding: const EdgeInsets.all(16.0),
                child: RadialSegmentChart(
                  groups: _radarChartResult!.radarChartData,
                  maxAbsValue: 100.0,
                  centerDisplayValue: widget.playerInfo.rating.round(),
                  centerComparisonValue:
                  _radarChartResult!.averagePlayerRatingPercentile,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}