// lib/screens/leagues/league_team_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';

class LeagueTeamScreen extends StatefulWidget {
  final int leagueId;

  const LeagueTeamScreen({super.key, required this.leagueId});

  @override
  State<LeagueTeamScreen> createState() => _LeagueTeamScreenState();
}

class _LeagueTeamScreenState extends State<LeagueTeamScreen> {
  bool _isLoading = true;

  Map<String, List<String>> _allFormations = {};
  String _selectedFormationName = '4-4-2';

  List<PlayerInfo> _fieldPlayers = [];
  List<PlayerInfo> _substitutePlayers = [];

  @override
  void initState() {
    super.initState();
    _loadFormations();
  }

  Future<void> _loadFormations() async {
    setState(() => _isLoading = true);
    final dataManagement = Provider.of<DataManagement>(context, listen: false);

    var formations = await dataManagement.supabaseService.fetchFormationsFromDb();
    if (formations.isEmpty) {
      formations = {
        '4-4-2': ['1','4','4','2'],
        '4-3-3': ['1','4','3','3'],
        '3-5-2': ['1','3','5','2'],
      };
    }

    if (mounted) {
      setState(() {
        _allFormations = formations;
        if (!_allFormations.containsKey(_selectedFormationName) && _allFormations.isNotEmpty) {
          _selectedFormationName = _allFormations.keys.first;
        }
        _generatePlaceholders();
        _isLoading = false;
      });
    }
  }

  void _generatePlaceholders() {
    List<PlayerInfo> field = [];
    List<PlayerInfo> bench = [];

    // Torwart & Feldspieler
    field.add(const PlayerInfo(id: -1, name: "Torwart", position: "TW", rating: 0, goals: 0, assists: 0, ownGoals: 0, profileImageUrl: null));
    for (int i = 1; i <= 10; i++) {
      field.add(PlayerInfo(id: -1 - i, name: "Feldspieler", position: "Feld", rating: 0, goals: 0, assists: 0, ownGoals: 0, profileImageUrl: null));
    }

    // Ersatzbank
    for (int i = 1; i <= 7; i++) {
      bench.add(PlayerInfo(id: -20 - i, name: "Bank $i", position: "SUB", rating: 0, goals: 0, assists: 0, ownGoals: 0, profileImageUrl: null));
    }

    setState(() {
      _fieldPlayers = field;
      _substitutePlayers = bench;
    });
  }

  void _handlePlayerTap(int playerId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Platzhalter ID: $playerId angetippt.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final sortedFormationKeys = _allFormations.keys.toList()..sort();
    final primaryColor = Theme.of(context).primaryColor;

    return Column(
      children: [
        // --- Dropdown ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedFormationName,
                  isExpanded: true,
                  items: sortedFormationKeys.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text('Formation: $value', style: const TextStyle(fontWeight: FontWeight.bold)),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) setState(() => _selectedFormationName = newValue);
                  },
                ),
              ),
            ),
          ),
        ),

        // --- Kombiniertes Spielfeld + Bank ---
        Expanded(
          child: MatchFormationDisplay(
            homeFormation: _selectedFormationName,
            homePlayers: _fieldPlayers,
            homeColor: primaryColor,
            onPlayerTap: _handlePlayerTap,
            substitutes: _substitutePlayers, // ✅ Hier übergeben wir einfach die Bank
          ),
        ),
      ],
    );
  }
}