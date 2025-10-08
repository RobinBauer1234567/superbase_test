// lib/screens/premier_league/table_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/team_screen.dart';

// Die TeamStats-Klasse bleibt unverändert
class TeamStats {
  final int id;
  final String name;
  final String imageUrl;
  int position = 0;
  int gamesPlayed = 0;
  int wins = 0;
  int draws = 0;
  int losses = 0;
  int goalsFor = 0;
  int goalsAgainst = 0;
  int points = 0;

  TeamStats({required this.id, required this.name, required this.imageUrl});

  int get goalDifference => goalsFor - goalsAgainst;
}

class TableScreen extends StatefulWidget {
  const TableScreen({super.key});

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  bool _isLoading = true;
  List<TeamStats> _tableStats = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _calculateTable();
  }

  Future<void> _calculateTable() async {
    // Diese Methode bleibt unverändert
    if (!mounted) return;
    setState(() => _isLoading = true);
    final dataManagement = Provider.of<DataManagement>(context, listen: false);

    try {
      final teamsResponse = await Supabase.instance.client
          .from('season_teams')
          .select('teams:team(id, name, image_url)')
          .eq('season_id', dataManagement.seasonId);

      final finishedGamesResponse = await Supabase.instance.client
          .from('spiel')
          .select('heimteam_id, auswärtsteam_id, ergebnis')
          .eq('season_id', dataManagement.seasonId)
          .neq('ergebnis', 'Noch kein Ergebnis');

      final Map<int, TeamStats> statsMap = {
        for (var teamEntry in teamsResponse)
          teamEntry['teams']['id']: TeamStats(
            id: teamEntry['teams']['id'],
            name: teamEntry['teams']['name'],
            imageUrl: teamEntry['teams']['image_url'] ?? '',
          )
      };

      for (var game in finishedGamesResponse) {
        final homeTeamId = game['heimteam_id'];
        final awayTeamId = game['auswärtsteam_id'];
        final scores = (game['ergebnis'] as String).split(':').map(int.parse).toList();
        final homeGoals = scores[0];
        final awayGoals = scores[1];
        final homeStats = statsMap[homeTeamId];
        final awayStats = statsMap[awayTeamId];

        if (homeStats == null || awayStats == null) continue;

        homeStats.gamesPlayed++;
        awayStats.gamesPlayed++;
        homeStats.goalsFor += homeGoals;
        awayStats.goalsFor += awayGoals;
        homeStats.goalsAgainst += awayGoals;
        awayStats.goalsAgainst += homeGoals;

        if (homeGoals > awayGoals) {
          homeStats.wins++;
          awayStats.losses++;
          homeStats.points += 3;
        } else if (awayGoals > homeGoals) {
          awayStats.wins++;
          homeStats.losses++;
          awayStats.points += 3;
        } else {
          homeStats.draws++;
          awayStats.draws++;
          homeStats.points += 1;
          awayStats.points += 1;
        }
      }

      final sortedStats = statsMap.values.toList();
      sortedStats.sort((a, b) {
        if (b.points != a.points) return b.points.compareTo(a.points);
        if (b.goalDifference != a.goalDifference) return b.goalDifference.compareTo(a.goalDifference);
        return b.goalsFor.compareTo(a.goalsFor);
      });

      for (int i = 0; i < sortedStats.length; i++) {
        sortedStats[i].position = i + 1;
      }
      if (mounted) {
        setState(() {
          _tableStats = sortedStats;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Fehler bei Tabellenberechnung: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
      child: DataTable(
        columnSpacing: 12.0,
        horizontalMargin: 8.0,
        // Wir entfernen onSelectChanged von der DataRow
        // und fügen onTap zur DataCell hinzu.
        columns: const [
          DataColumn(label: Text('#')),
          DataColumn(label: Text('Club')),
          DataColumn(label: Text('Sp')),
          DataColumn(label: Text('S')),
          DataColumn(label: Text('U')),
          DataColumn(label: Text('N')),
          DataColumn(label: Text('Tordiff.')),
          DataColumn(label: Text('Pkt.')),
        ],
        rows: _tableStats.map((stats) {
          return DataRow(
            cells: [
              DataCell(Text(stats.position.toString())),
              DataCell(
                // **ÄNDERUNG HIER:** Wir wickeln den Inhalt in einen InkWell
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TeamScreen(teamId: stats.id),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Image.network(stats.imageUrl, width: 24, height: 24, errorBuilder: (c, e, s) => const Icon(Icons.shield, size: 24)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(stats.name, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ),
              DataCell(Text(stats.gamesPlayed.toString())),
              DataCell(Text(stats.wins.toString())),
              DataCell(Text(stats.draws.toString())),
              DataCell(Text(stats.losses.toString())),
              DataCell(Text(stats.goalDifference.toString())),
              DataCell(Text(stats.points.toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
          );
        }).toList(),
      ),
    );
  }
}