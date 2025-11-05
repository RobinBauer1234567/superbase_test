// lib/screens/league_tabs/ranking_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';

class RankingScreen extends StatefulWidget {
  final int leagueId;
  const RankingScreen({super.key, required this.leagueId});

  @override
  _RankingScreenState createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> _rankingFuture;

  @override
  void initState() {
    super.initState();
    _rankingFuture = _fetchRanking();
  }

  Future<List<Map<String, dynamic>>> _fetchRanking() async {
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    return dataManagement.supabaseService.getLeagueRanking(widget.leagueId);
  }

  @override
  bool get wantKeepAlive => true; // Behält den Zustand des Tabs bei

  @override
  Widget build(BuildContext context) {
    super.build(context); // Wichtig für AutomaticKeepAliveClientMixin
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _rankingFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Center(child: Text('Ranking konnte nicht geladen werden.'));
        }
        final ranking = snapshot.data!;
        if (ranking.isEmpty) {
          return const Center(child: Text('Noch keine Punkte in dieser Liga.'));
        }

        return ListView.builder(
          itemCount: ranking.length,
          itemBuilder: (context, index) {
            final entry = ranking[index];
            return ListTile(
              leading: CircleAvatar(
                child: Text('${index + 1}'),
              ),
              title: Text(entry['username'] ?? 'Unbekannter Spieler'),
              subtitle: Text(entry['manager_team_name'] ?? 'Teamname'),
              trailing: Text(
                '${entry['total_points']} Pkt.',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            );
          },
        );
      },
    );
  }
}