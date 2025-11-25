// lib/screens/leagues/starter_team_reveal_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/screens/leagues/league_detail_screen.dart';
import 'package:premier_league/screens/screenelements/player_list_item.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';

class StarterTeamRevealScreen extends StatefulWidget {
  final int leagueId;
  final double startingBudget;
  final String leagueName; // Optional, für den Titel

  const StarterTeamRevealScreen({
    super.key,
    required this.leagueId,
    required this.startingBudget,
    this.leagueName = "Neue Liga",
  });

  @override
  State<StarterTeamRevealScreen> createState() => _StarterTeamRevealScreenState();
}

class _StarterTeamRevealScreenState extends State<StarterTeamRevealScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _players = [];
  int _totalTeamValue = 0;

  // State für den Reveal-Prozess
  int _currentPlayerIndex = 0;
  bool _showSummary = false;

  @override
  void initState() {
    super.initState();
    _loadTeam();
  }

  Future<void> _loadTeam() async {
    final dataManagement = Provider.of<DataManagement>(context, listen: false);

    // Kurzes Delay, damit der Übergang nicht zu abrupt ist
    await Future.delayed(const Duration(milliseconds: 500));

    final players = await dataManagement.supabaseService.fetchUserLeaguePlayers(widget.leagueId);

    int totalVal = 0;
    for(var p in players) {
      totalVal += (p['marktwert'] as int?) ?? 0;
    }

    if (mounted) {
      setState(() {
        _players = players;
        _totalTeamValue = totalVal;
        _isLoading = false;
        // Falls keine Spieler da sind (z.B. Startspieler = 0), direkt zur Zusammenfassung
        if (_players.isEmpty) {
          _showSummary = true;
        }
      });
    }
  }

  String _formatMoney(num amount) {
    final formatter = NumberFormat.decimalPattern('de_DE');
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)} Mio. €';
    }
    return '${formatter.format(amount)} €';
  }

  void _nextPlayer() {
    if (_currentPlayerIndex < _players.length - 1) {
      setState(() {
        _currentPlayerIndex++;
      });
    } else {
      setState(() {
        _showSummary = true;
      });
    }
  }

  void _skipReveal() {
    setState(() {
      _showSummary = true;
    });
  }

  void _finishAndGoToLeague() {
    Navigator.of(context).pop(widget.leagueId);
  }  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_showSummary ? "Dein Kader" : "Spieler ${_currentPlayerIndex + 1} von ${_players.length}"),
        actions: [
          if (!_showSummary && !_isLoading)
            TextButton(
              onPressed: _skipReveal,
              child: const Text("Überspringen", style: TextStyle(color: Colors.white)),
            )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _showSummary
          ? _buildSummaryView()
          : _buildSingleRevealView(),
    );
  }

  // --- ANSICHT 1: Einzelner Spieler (Karte) ---
  Widget _buildSingleRevealView() {
    final player = _players[_currentPlayerIndex];
    final progress = (_currentPlayerIndex + 1) / _players.length;

    return Column(
      children: [
        LinearProgressIndicator(value: progress, minHeight: 6),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Wir nutzen AnimatedSwitcher für einen sanften Übergang zwischen Spielern
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return ScaleTransition(scale: animation, child: child);
                      },
                      child: Container(
                        key: ValueKey<int>(player['id']), // Wichtig für Animation
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.2),
                              spreadRadius: 2,
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Team Logo Hintergrund (optional)
                            if (player['team_image_url'] != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: Image.network(player['team_image_url'], height: 40, width: 40),
                              ),

                            // Profilbild
                            CircleAvatar(
                              radius: 60,
                              backgroundColor: Colors.grey.shade100,
                              backgroundImage: player['profilbild_url'] != null
                                  ? NetworkImage(player['profilbild_url'])
                                  : null,
                              child: player['profilbild_url'] == null
                                  ? const Icon(Icons.person, size: 60, color: Colors.grey)
                                  : null,
                            ),
                            const SizedBox(height: 16),

                            // Name
                            Text(
                              player['name'],
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),

                            // Position
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                player['position'] ?? 'N/A',
                                style: TextStyle(
                                  color: Theme.of(context).primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Marktwert
                            const Text("Marktwert", style: TextStyle(color: Colors.grey)),
                            Text(
                              _formatMoney(player['marktwert'] ?? 0),
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Bottom Button Area
        Container(
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _nextPlayer,
            child: Text(
              _currentPlayerIndex < _players.length - 1 ? "Nächster Spieler" : "Zum Kader",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  // --- ANSICHT 2: Gesamtkader Liste (Wie TeamScreen) ---
  Widget _buildSummaryView() {
    return Column(
      children: [
        // Info Header
        Container(
          color: Theme.of(context).cardColor,
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryStat("Budget", _formatMoney(widget.startingBudget)),
              _buildSummaryStat("Teamwert", _formatMoney(_totalTeamValue)),
            ],
          ),
        ),
        const Divider(height: 1),

        // Liste der Spieler (Wiederverwendung von PlayerListItem)
        Expanded(
          child: ListView.builder(
            itemCount: _players.length,
            itemBuilder: (context, index) {
              final player = _players[index];
              return PlayerListItem(
                rank: index + 1,
                profileImageUrl: player['profilbild_url'],
                playerName: player['name'],
                // teamImageUrl null setzen, damit Marktwert angezeigt wird (Logik aus deinem vorherigen Request)
                teamImageUrl: null,
                marketValue: player['marktwert'],
                score: 0, // Startpunkte sind 0
                maxScore: 100, // Dummy MaxScore
                onTap: () {
                  // Hier könnte man zum PlayerDetailScreen navigieren, aber im Reveal vielleicht noch nicht nötig
                },
              );
            },
          ),
        ),

        // Abschluss Button
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green, // Grün für "Start" / "Los geht's"
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _finishAndGoToLeague,
              child: const Text(
                "LIGA BETRETEN",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
      ],
    );
  }
}