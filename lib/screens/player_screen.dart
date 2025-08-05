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
  String position = "";
  String teamName = "";
  String? profileImageUrl;

  // Data for views
  bool isLoading = true;
  List<dynamic> matchRatingsRaw = [];
  List<GroupData> radarChartData = [];

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
      // 1. Spieler- und Team-Daten abrufen
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

      // 2. Alle Match-Ratings inklusive der Statistiken abrufen
      final matchRatingsResponse = await supabase
          .from('matchrating')
          .select('spiel_id, punkte, statistics')
          .eq('spieler_id', widget.playerId);

      if (!mounted) return;

      setState(() {
        playerName = playerResponse['name'];
        position = playerResponse['position'];
        teamName = teamResponse['name'];
        profileImageUrl = playerResponse['profilbild_url'] ??
            'https://rcfetlzldccwjnuabfgj.supabase.co/storage/v1/object/public/spielerbilder//Photo-Missing.png';
        matchRatingsRaw = matchRatingsResponse;
      });

      // 3. Radar-Chart-Daten berechnen
      await _calculateRadarChartData();
    } catch (error) {
      print("Fehler beim Laden der Spielerdaten: $error");
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }
  Future<void> _calculateRadarChartData() async {
    if (matchRatingsRaw.isEmpty) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
      return;
    }

    // Schritt 1: Spielerstatistiken aggregieren (bleibt unverändert)
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
    Map<String, double> playerAverageStats =
    playerTotalStats.map((key, value) => MapEntry(key, value / matchCount));

    // ✅ Schritt 2: Lade die Vergleichsdaten für die exakte, primäre Position des Spielers
    //    Die primäre Position wird aus dem 'position'-String extrahiert (z.B. "IV" aus "D, IV")
    String primaryPosition = position.split(',').last.trim();

    Map<String, double> universalAverageStats = {};

    final universalStatsResponse = await supabase
        .from('universal_stats')
        .select('statistics, anzahl')
        .eq('position', primaryPosition) // Filtert z.B. exakt nach 'ZDM'
        .maybeSingle(); // .maybeSingle() holt einen einzelnen Datensatz oder null

    if (universalStatsResponse != null) {
      final stats = universalStatsResponse['statistics'] as Map<String, dynamic>? ?? {};
      final anzahl = (universalStatsResponse['anzahl'] as int?) ?? 1;

      stats.forEach((key, value) {
        universalAverageStats[key] = (value as num).toDouble() / anzahl;
      });
    }

    // Schritt 3: Index berechnen (bleibt unverändert)
    double calculateStat(String key) {
      final playerValue = playerAverageStats[key] ?? 0.0;
      final universalValue = universalAverageStats[key] ?? 1.0; // Teilen durch 0 vermeiden
      if (universalValue == 0) return 50.0;
      return min(100, (playerValue / universalValue) * 50);
    }

    setState(() {
      radarChartData = [
        GroupData(
          name: 'Schießen',
          backgroundColor: Colors.blue.withOpacity(0.12),
          segments: [
            SegmentData(name: 'Abschlussvolumen', value: calculateStat('onTargetScoringAttempt') + calculateStat('blockedScoringAttempt') + calculateStat('shotOffTarget') + calculateStat('hitWoodwork')),
            SegmentData(name: 'Abschlussqualität', value: (2*calculateStat('goals') - calculateStat('expectedGoals'))),
          ],
        ),
        GroupData(
          name: 'Passen',
          backgroundColor: Colors.green.withOpacity(0.12),
          segments: [
            SegmentData(name: 'Passvolumen', value: calculateStat('totalPass')),
            SegmentData(name: 'Passsicherheit', value: calculateStat('accuratePass')),
            SegmentData(name: 'Kreative Pässe', value: calculateStat('keyPass')),
          ],
        ),
        GroupData(
          name: 'Duelle',
          backgroundColor: Colors.orange.withOpacity(0.12),
          segments: [
            SegmentData(name: 'Zweikampfaktivität', value: calculateStat('duelWon') + calculateStat('duelLost')),
            SegmentData(name: 'Zweikämpferfolg', value: calculateStat('duelWon')),
            SegmentData(name: 'Fouls', value: calculateStat('fouls')),
          ],
        ),
        GroupData(
          name: 'Ballbesitz',
          backgroundColor: Colors.red.withOpacity(0.12),
          segments: [
            SegmentData(name: 'Ballberührungen', value: calculateStat('touches')),
            SegmentData(name: 'Ballverluste', value: calculateStat('dispossessed')),
            SegmentData(name: 'Abgefangene Bälle', value: calculateStat('interceptionWon')),
          ],
        ),
        GroupData(
          name: 'Defensive',
          backgroundColor: Colors.purple.withOpacity(0.12),
          segments: [
            SegmentData(name: 'Tacklings', value: calculateStat('totalTackle')),
            SegmentData(name: 'Klärende Aktionen', value: calculateStat('totalClearance')),
            SegmentData(name: 'Fehler', value: calculateStat('errorLeadToAGoal')),
          ],
        ),
      ];
      isLoading = false;
    });
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
          // Statischer oberer Teil
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Center(
                  child: ClipOval(
                    child: profileImageUrl != null
                        ? Image.network(
                      profileImageUrl!,
                      width: 150, // Etwas kleiner für bessere Optik
                      height: 150,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.error, size: 120, color: Colors.red);
                      },
                    )
                        : const Icon(Icons.person, size: 120, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 16),
                Text("Team: $teamName", style: const TextStyle(fontSize: 18)),
                Text("Position: $position", style: const TextStyle(fontSize: 18)),
              ],
            ),
          ),

          // Tab-Bar für die wischbare Ansicht
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Match Ratings'),
              Tab(text: 'Radar Chart'),
            ],
          ),

          // Wischbarer Inhalt
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // View 1: Match Ratings
                matchRatingsRaw.isEmpty
                    ? const Center(child: Text("Keine Bewertungen vorhanden"))
                    : ListView(
                  children: matchRatingsRaw.map((rating) {
                    return ListTile(
                      title: Text("Match ID: ${rating['spiel_id']}"),
                      trailing: Text("Rating: ${(rating['punkte'] as num).toDouble().toStringAsFixed(1)}"),
                    );
                  }).toList(),
                ),

                // View 2: Radar Chart
                radarChartData.isEmpty
                    ? const Center(child: Text("Statistiken nicht verfügbar."))
                    : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: RadialSegmentChart(
                    groups: radarChartData,
                    maxAbsValue: 100.0,
                    centerLabel: 72, // Kann dynamisch sein
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