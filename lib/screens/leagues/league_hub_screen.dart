// lib/screens/leagues/league_hub_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/screens/leagues/create_league_dialog.dart';
import 'package:premier_league/screens/leagues/starter_team_reveal_screen.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';

class LeagueHubScreen extends StatefulWidget {
  const LeagueHubScreen({super.key});

  @override
  State<LeagueHubScreen> createState() => _LeagueHubScreenState();
}

class _LeagueHubScreenState extends State<LeagueHubScreen> {
  Future<void> _createLeague() async {
    final created = await showCreateLeagueDialog(context);
    if (created == null || !mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StarterTeamRevealScreen(
          leagueId: created.leagueId,
          startingBudget: created.startingBudget,
          leagueName: created.leagueName,
        ),
      ),
    );

    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataManagement = Provider.of<DataManagement>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ligen-Hub'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Liga gründen',
            onPressed: _createLeague,
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: dataManagement.supabaseService.getPublicLeagues(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Center(child: Text('Fehler beim Laden der Ligen.'));
          }

          final publicLeagues = snapshot.data!;
          if (publicLeagues.isEmpty) {
            return const Center(
              child: Text(
                'Aktuell gibt es keine öffentlichen Ligen, denen du beitreten kannst.',
              ),
            );
          }

          return ListView.builder(
            itemCount: publicLeagues.length,
            itemBuilder: (context, index) {
              final league = publicLeagues[index];
              return ListTile(
                title: Text(league['name']),
                subtitle: Text(
                  'Startbudget: ${(league['starting_budget'] / 1000000).round()} Mio. €',
                ),
                trailing: ElevatedButton(
                  child: const Text('Beitreten'),
                  onPressed: () async {
                    try {
                      await dataManagement.supabaseService.joinLeague(
                        league['id'],
                      );

                      if (!mounted) return;
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StarterTeamRevealScreen(
                            leagueId: league['id'],
                            startingBudget:
                                (league['starting_budget'] as num).toDouble(),
                            leagueName: league['name'],
                          ),
                        ),
                      );

                      if (result != null && mounted) {
                        Navigator.of(context).pop(result);
                      }
                    } catch (error) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(error.toString()),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
