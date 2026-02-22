// lib/screens/league_tabs/ranking_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:premier_league/data_service.dart';


class RankingScreen extends StatefulWidget {
  final int leagueId;
  // currentSeasonRound wurde hier aus dem Konstruktor entfernt!
  const RankingScreen({Key? key, required this.leagueId}) : super(key: key);

  @override
  _RankingScreenState createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  bool isOverallRanking = true; // true = Gesamt, false = Spieltag
  int selectedRound = 1;        // Startwert, wird gleich überschrieben
  List<Map<String, dynamic>> rankingData = [];
  bool isLoading = true;
  final dataService = SupabaseService();

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  /// Kümmert sich um die korrekte Reihenfolge beim Laden
  Future<void> _initializeData() async {
    setState(() => isLoading = true);

    // 1. Aktuellen Spieltag abrufen
    await _fetchCurrentRound();

    // 2. Rangliste für diesen (oder alle) Spieltag(e) laden
    await _loadRanking();
  }

  /// Holt den aktuellen Spieltag aus der Datenbank
  Future<void> _fetchCurrentRound() async {
    try {

      final dataManagement = Provider.of<DataManagement>(context, listen: false);
      final seasonId = dataManagement.seasonId;

      selectedRound = await dataService.getCurrentRound(seasonId);

    } catch (e) {
      print('Fehler beim Laden des aktuellen Spieltags: $e');
      selectedRound = 1; // Fallback
    }
  }

  /// Lädt das eigentliche Ranking (Gesamt oder für den ausgewählten Spieltag)
  Future<void> _loadRanking() async {
    setState(() => isLoading = true);

    try {
      if (isOverallRanking) {
        rankingData = await dataService.fetchOverallRanking(widget.leagueId);
      } else {
        rankingData = await dataService.fetchMatchdayRanking(widget.leagueId, selectedRound);
      }
    } catch (e) {
      print('Fehler beim Laden der Rangliste: $e');
    }

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Rangliste')),
      body: Column(
        children: [
          // 1. Der Toggle-Button (Gesamt / Spieltag)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: Text('Gesamt'),
                  selected: isOverallRanking,
                  onSelected: (val) {
                    if (!isOverallRanking) {
                      setState(() => isOverallRanking = true);
                      _loadRanking();
                    }
                  },
                ),
                SizedBox(width: 10),
                ChoiceChip(
                  label: Text('Spieltag'),
                  selected: !isOverallRanking,
                  onSelected: (val) {
                    if (isOverallRanking) {
                      setState(() => isOverallRanking = false);
                      _loadRanking();
                    }
                  },
                ),
              ],
            ),
          ),

          // 2. Die Spieltags-Auswahl (nur sichtbar, wenn "Spieltag" aktiv ist)
          if (!isOverallRanking)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_ios, size: 16),
                  onPressed: selectedRound > 1 ? () {
                    setState(() => selectedRound--);
                    _loadRanking();
                  } : null,
                ),
                Text(
                    'Spieltag $selectedRound',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                ),
                IconButton(
                  icon: Icon(Icons.arrow_forward_ios, size: 16),
                  onPressed: selectedRound < 34 ? () { // Maximal 34 Spieltage (bei Bundesliga)
                    setState(() => selectedRound++);
                    _loadRanking();
                  } : null,
                ),
              ],
            ),

          Divider(),

          // 3. Die Liste der Manager
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : rankingData.isEmpty
                ? Center(child: Text('Noch keine Punkte vorhanden.'))
                : ListView.builder(
              itemCount: rankingData.length,
              itemBuilder: (context, index) {
                final user = rankingData[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blueAccent,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(user['manager_team_name'] ?? 'Unbekanntes Team'),
                  trailing: Text(
                      '${user['total_points']} Pkt',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}