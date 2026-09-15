import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';
import 'package:premier_league/screens/team_screen.dart';
import 'package:premier_league/services/app_data_repository.dart';

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
  final AppDataRepository _repository = AppDataRepository.instance;

  bool _isLoading = true;
  List<TeamStats> _tableStats = [];
  int? _loadedSeasonId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final seasonId = context.read<TournamentViewModel>().currentSeasonId;
    if (seasonId == null || seasonId == _loadedSeasonId) return;
    _loadedSeasonId = seasonId;
    _calculateTable(seasonId);
  }

  Future<void> _calculateTable(int seasonId, {bool forceRefresh = false}) async {
    if (!mounted) return;
    if (_tableStats.isEmpty) setState(() => _isLoading = true);

    try {
      final results = await Future.wait<dynamic>([
        _repository.getSeasonTeams(seasonId, forceRefresh: forceRefresh),
        _repository.getMatches(seasonId, forceRefresh: forceRefresh),
      ]);
      if (!mounted || _loadedSeasonId != seasonId) return;

      final teams = List<Map<String, dynamic>>.from(results[0] as List);
      final games = List<Map<String, dynamic>>.from(results[1] as List);

      final Map<int, TeamStats> statsMap = {
        for (final team in teams)
          if (team['id'] is int)
            team['id'] as int: TeamStats(
              id: team['id'] as int,
              name: (team['name'] ?? 'Unbekannt').toString(),
              imageUrl: (team['image_url'] ?? '').toString(),
            ),
      };

      for (final game in games) {
        final status = (game['status'] ?? '').toString().toLowerCase();
        if (status == 'nicht gestartet' ||
            status == 'not started' ||
            status == 'postponed') {
          continue;
        }

        final homeTeamId = game['heimteam_id'];
        final awayTeamId = game['auswärtsteam_id'];
        if (homeTeamId is! int || awayTeamId is! int) continue;

        final rawResult = (game['ergebnis'] ?? '').toString();
        final parts = rawResult.split(':');
        if (parts.length != 2) continue;
        final homeGoals = int.tryParse(parts[0].trim());
        final awayGoals = int.tryParse(parts[1].trim());
        if (homeGoals == null || awayGoals == null) continue;

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
          homeStats.points++;
          awayStats.points++;
        }
      }

      final sortedStats = statsMap.values.toList()
        ..sort((a, b) {
          if (b.points != a.points) return b.points.compareTo(a.points);
          if (b.goalDifference != a.goalDifference) {
            return b.goalDifference.compareTo(a.goalDifference);
          }
          return b.goalsFor.compareTo(a.goalsFor);
        });

      for (var i = 0; i < sortedStats.length; i++) {
        sortedStats[i].position = i + 1;
      }

      setState(() {
        _tableStats = sortedStats;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Fehler bei Tabellenberechnung: $e');
      if (mounted && _loadedSeasonId == seasonId) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final showResultColumns = screenWidth >= 720;

    if (_isLoading && _tableStats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async {
        final seasonId = _loadedSeasonId;
        if (seasonId != null) {
          await _calculateTable(seasonId, forceRefresh: true);
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final clubColumnWidth = showResultColumns
              ? constraints.maxWidth * 0.30
              : constraints.maxWidth * 0.48;

          final dataTable = DataTable(
            columnSpacing: 12.0,
            horizontalMargin: 8.0,
            columns: [
              const DataColumn(label: Text('#')),
              const DataColumn(label: Text('Club')),
              const DataColumn(label: Text('Sp')),
              if (showResultColumns) const DataColumn(label: Text('S')),
              if (showResultColumns) const DataColumn(label: Text('U')),
              if (showResultColumns) const DataColumn(label: Text('N')),
              const DataColumn(label: Text('Tordiff.')),
              const DataColumn(label: Text('Pkt.')),
            ],
            rows: _tableStats.map((stats) {
              return DataRow(
                cells: [
                  DataCell(Text(stats.position.toString())),
                  DataCell(
                    SizedBox(
                      width: clubColumnWidth,
                      child: InkWell(
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
                            Image.network(
                              stats.imageUrl,
                              width: 24,
                              height: 24,
                              errorBuilder: (c, e, s) =>
                                  const Icon(Icons.shield, size: 24),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                stats.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text(stats.gamesPlayed.toString())),
                  if (showResultColumns) DataCell(Text(stats.wins.toString())),
                  if (showResultColumns) DataCell(Text(stats.draws.toString())),
                  if (showResultColumns) DataCell(Text(stats.losses.toString())),
                  DataCell(Text(stats.goalDifference.toString())),
                  DataCell(
                    Text(
                      stats.points.toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              );
            }).toList(),
          );

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                width: constraints.maxWidth,
                child: FittedBox(
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topLeft,
                  child: dataTable,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
