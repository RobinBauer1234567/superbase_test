// lib/screens/premier_league/top_team_screen.dart
import 'package:flutter/material.dart';
import 'package:premier_league/data_service.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/screenelements/player_list_item.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';

class TopTeamScreen extends StatefulWidget {
  const TopTeamScreen({super.key});

  @override
  _TopTeamScreenState createState() => _TopTeamScreenState();
}

class _TopTeamScreenState extends State<TopTeamScreen> {
  // View State
  bool _showGesamt = true;
  bool _isLoading = true;
  bool _showFormation = false;
  bool _isCalculatingFormation = false;

  // Data
  List<Map<String, dynamic>> _topPlayers = [];
  List<Map<String, dynamic>> _teams = [];
  List<String> _positions = [];
  Map<String, dynamic>? _bestFormation;
  Map<String, List<String>> _allFormations = {};
  String? _selectedFormationName;

  // Filter & Selection
  int? _selectedSpieltag;
  List<int> _spieltage = [];
  int? _selectedTeamId;
  String? _selectedPosition;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initialize();
  }

  Future<void> _initialize() async {
    await _fetchFilterData();
    await _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    if (_showGesamt) {
      await _fetchGesamtStats();
    } else {
      if (_selectedSpieltag != null) {
        await _fetchSpieltagStats();
      }
    }
    if (_showFormation) {
      await _calculateInitialBestFormation();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _fetchFilterData() async {
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final seasonId = dataManagement.seasonId;

    final teamsResponse = await Supabase.instance.client
        .from('season_teams')
        .select('team:team(id, name, image_url)')
        .eq('season_id', seasonId);
    if (teamsResponse.isNotEmpty) {
      _teams =
          teamsResponse.map((e) => e['team'] as Map<String, dynamic>).toList();
      _teams.sort((a, b) => a['name'].compareTo(b['name']));
    }

    final spieltageResponse = await Supabase.instance.client
        .from('spieltag')
        .select('round')
        .eq('season_id', seasonId)
        .neq('status', 'nicht gestartet');
    if (spieltageResponse.isNotEmpty) {
      _spieltage =
      spieltageResponse.map<int>((e) => e['round'] as int).toList()..sort();
      _selectedSpieltag = _spieltage.isNotEmpty ? _spieltage.last : null;
    }

    final positionsResponse =
    await Supabase.instance.client.from('spieler').select('position');
    final positionSet = <String>{};
    for (var player in positionsResponse) {
      if (player['position'] != null) {
        player['position']
            .toString()
            .split(',')
            .forEach((p) => positionSet.add(p.trim()));
      }
    }
    _positions = positionSet.toList()..sort();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _fetchGesamtStats() async {
    setState(() => _isLoading = true);
    try {
      final dataManagement = Provider.of<DataManagement>(context, listen: false);
      final dynamic rawSeasonId = dataManagement.seasonId;
      final String seasonIdStr = rawSeasonId.toString();
      final int? seasonIdInt = int.tryParse(seasonIdStr);

      var query = Supabase.instance.client
          .from('spieler')
          .select('id, name, profilbild_url, position, spieler_analytics(marktwert, gesamtstatistiken, season_id), season_players!inner(season_id, team:team(id, name, image_url))')
          .eq('season_players.season_id', seasonIdInt ?? rawSeasonId);

      final teamId = _selectedTeamId;
      if (teamId != null) {
        query = query.eq('season_players.team_id', teamId);
      }

      final response = await query;
      List<Map<String, dynamic>> topPlayersList = [];
      final String? selectedPosition = _selectedPosition?.toLowerCase();

      for (var player in response) {
        try {
          final analyticsRaw = player['spieler_analytics'];
          Map<String, dynamic>? analytics;
          if (analyticsRaw is List) {
            analytics = analyticsRaw.cast<Map<String, dynamic>>().firstWhere(
              (a) => a['season_id'] == seasonIdInt,
              orElse: () => <String, dynamic>{},
            );
          } else if (analyticsRaw is Map) {
            analytics = Map<String, dynamic>.from(analyticsRaw);
          }

          final dynamic stats = analytics?['gesamtstatistiken'];
          final dynamic seasonStats = stats is Map ? stats : null;

          final dynamic seasonPlayers = player['season_players'];
          dynamic team;
          if (seasonPlayers is List && seasonPlayers.isNotEmpty) {
            team = seasonPlayers[0]?['team'];
          } else if (seasonPlayers is Map) {
            team = seasonPlayers['team'];
          }

          if (seasonStats == null || team == null) {
            continue;
          }

          if (selectedPosition != null && selectedPosition.isNotEmpty) {
            final dynamic rawPos = player['position'];
            String playerPosStr = '';
            if (rawPos is String) {
              playerPosStr = rawPos.toLowerCase();
            } else if (rawPos is List) {
              playerPosStr = rawPos.map((e) => e.toString()).join(',').toLowerCase();
            } else {
              playerPosStr = rawPos?.toString().toLowerCase() ?? '';
            }

            if (!playerPosStr.contains(selectedPosition)) {
              continue;
            }
          }

          final totalPunkte = (seasonStats is Map) ? (seasonStats['gesamtpunkte'] ?? 0) : 0;

          topPlayersList.add({
            'id': player['id'],
            'name': player['name'],
            'profilbild_url': player['profilbild_url'],
            'team_image_url': team['image_url'],
            'marktwert': (analytics?['marktwert'] as num?)?.toInt(),
            'total_punkte': (totalPunkte as num).toInt(),
            'position': player['position'],
          });
        } catch (e) {
          print('⚠️ Fehler beim Verarbeiten eines Spielers in _fetchGesamtStats: $e');
          continue;
        }
      }

      topPlayersList.sort((a, b) => (b['total_punkte'] as num).compareTo(a['total_punkte'] as num));

      if (mounted) {
        setState(() {
          _topPlayers = topPlayersList.take(50).toList();
        });
      }
    } catch (e, st) {
      print('❌ Fehler in _fetchGesamtStats: $e\n$st');
      if (mounted) {
        setState(() {
          _topPlayers = [];
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchSpieltagStats() async {
    setState(() => _isLoading = true);
    try {
      final spieltag = _selectedSpieltag;
      if (spieltag == null) return;

      final dataManagement = Provider.of<DataManagement>(context, listen: false);
      final seasonId = dataManagement.seasonId;

      var query = Supabase.instance.client
          .from('matchrating')
          .select('punkte, spieler:spieler!inner(id, name, profilbild_url, position, spieler_analytics(marktwert, season_id)), spiel!inner(round, season_id)')
          .eq('spiel.round', spieltag)
          .eq('spiel.season_id', seasonId);

      final response = await query;

      final playerTeamQueryIds = response
          .where((r) => r['spieler'] != null)
          .map<int>((r) => r['spieler']['id'] as int)
          .toSet()
          .toList();

      Map<int, dynamic> playerTeamMap = {};
      if (playerTeamQueryIds.isNotEmpty) {
        final teamResponse = await Supabase.instance.client
            .from('season_players')
            .select('player_id, team:team(id, image_url)')
            .eq('season_id', seasonId)
            .inFilter('player_id', playerTeamQueryIds);

        playerTeamMap = {
          for (var item in teamResponse) item['player_id']: item['team']
        };
      }

      final String? selectedPosition = _selectedPosition?.toLowerCase();

      List<Map<String, dynamic>> topPlayersList = [];
      for (var rating in response) {
        final player = rating['spieler'];
        if (player == null) continue;

        if (selectedPosition != null && selectedPosition.isNotEmpty) {
          final playerPos = (player['position'] ?? '').toString().toLowerCase();
          if (!playerPos.contains(selectedPosition)) continue;
        }

        final team = playerTeamMap[player['id']];
        if (team == null) continue;

        final teamId = _selectedTeamId;
        if (teamId != null && team['id'] != teamId) continue;

        topPlayersList.add({
          'id': player['id'],
          'name': player['name'],
          'profilbild_url': player['profilbild_url'],
          'team_image_url': team['image_url'],
          'marktwert': (() { final a = player['spieler_analytics']; if (a is List) { final f = a.cast<Map<String,dynamic>>().firstWhere((x)=>x['season_id']==seasonId, orElse: ()=> <String,dynamic>{}); return (f['marktwert'] as num?)?.toInt(); } return (a is Map ? (a['marktwert'] as num?)?.toInt() : null); })(),
          'total_punkte': (rating['punkte'] as num?)?.toInt() ?? 0,
          'position': player['position'],
        });
      }

      topPlayersList.sort((a, b) => b['total_punkte'].compareTo(a['total_punkte']));

      if (mounted) {
        setState(() {
          _topPlayers = topPlayersList.take(50).toList();
        });
      }
    } catch (e, st) {
      print('Fehler in _fetchSpieltagStats: $e\n$st');
      if (mounted) setState(() => _topPlayers = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _calculateInitialBestFormation() async {
    setState(() => _isCalculatingFormation = true);
    SupabaseService supabaseService = SupabaseService();
    final formations = await supabaseService.fetchFormationsFromDb();
    _allFormations = formations;

    Map<String, dynamic>? bestFormation;
    int maxScore = 0;
    String? bestFormationName;

    formations.forEach((formationName, positions) {
      List<Map<String, dynamic>> currentFormation = [];
      int currentScore = 0;
      List<int> usedPlayerIds = [];

      for (var pos in positions) {
        final bestPlayerForPos = _topPlayers.firstWhere(
              (p) =>
          !usedPlayerIds.contains(p['id']) &&
              (p['position'] as String).contains(pos),
          orElse: () => {},
        );

        if (bestPlayerForPos.isNotEmpty) {
          currentFormation.add(bestPlayerForPos);
          currentScore += bestPlayerForPos['total_punkte'] as int;
          usedPlayerIds.add(bestPlayerForPos['id']);
        }
      }

      if (currentFormation.length == 11 && currentScore > maxScore) {
        maxScore = currentScore;
        bestFormationName = formationName;
        bestFormation = {
          'name': formationName,
          'players': currentFormation,
          'score': maxScore,
        };
      }
    });

    setState(() {
      _bestFormation = bestFormation;
      _selectedFormationName = bestFormationName;
      _isCalculatingFormation = false;
    });
  }

  void _calculateTeamForSelectedFormation(String formationName) {
    setState(() => _isCalculatingFormation = true);

    final positions = _allFormations[formationName];
    if (positions == null) {
      setState(() {
        _bestFormation = null;
        _isCalculatingFormation = false;
      });
      return;
    }

    List<Map<String, dynamic>> currentFormation = [];
    int currentScore = 0;
    List<int> usedPlayerIds = [];

    for (var pos in positions) {
      final bestPlayerForPos = _topPlayers.firstWhere(
            (p) =>
        !usedPlayerIds.contains(p['id']) &&
            (p['position'] as String).contains(pos),
        orElse: () => {},
      );

      if (bestPlayerForPos.isNotEmpty) {
        currentFormation.add(bestPlayerForPos);
        currentScore += bestPlayerForPos['total_punkte'] as int;
        usedPlayerIds.add(bestPlayerForPos['id']);
      }
    }

    Map<String, dynamic>? newFormation;
    if (currentFormation.length == 11) {
      newFormation = {
        'name': formationName,
        'players': currentFormation,
        'score': currentScore,
      };
    }

    setState(() {
      _bestFormation = newFormation;
      _selectedFormationName = formationName;
      _isCalculatingFormation = false;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _showFormation
              ? _buildFormationView()
              : _buildPlayerListView(),
        ),
      ],
    );
  }

  // --- FIX 1: Filter Bar mit ScrollView ---
  Widget _buildFilterBar() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        // SingleChildScrollView verhindert Overflow auf kleinen Screens
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min, // Nimmt nur so viel Platz wie nötig
            children: [
              ToggleButtons(
                constraints: const BoxConstraints(minHeight: 36.0, minWidth: 60.0),
                isSelected: [_showGesamt, !_showGesamt],
                onPressed: (index) {
                  if (index == 0 && !_showGesamt) {
                    setState(() => _showGesamt = true);
                    _fetchData();
                  } else if (index == 1 && _showGesamt) {
                    setState(() => _showGesamt = false);
                    _fetchData();
                  } else if (index == 1 && !_showGesamt) {
                    _showSpieltagDropdown(context);
                  }
                },
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text('Gesamt'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      children: [
                        const Text('Spieltag'),
                        if (!_showGesamt)
                          const Icon(Icons.arrow_drop_down, size: 16),
                      ],
                    ),
                  ),
                ],
              ),

              // Spacer durch festen Abstand ersetzt, da Spacer in ScrollView nicht geht
              const SizedBox(width: 16),

              _buildDropdownFilter<int?>(
                value: _selectedTeamId,
                hint: 'Team',
                items: [
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('Alle Teams')),
                  ..._teams.map((team) => DropdownMenuItem<int?>(
                    value: team['id'],
                    child: Text(team['name']),
                  )),
                ],
                onChanged: _showFormation ? null : (value) {
                  setState(() => _selectedTeamId = value);
                  _fetchData();
                },
              ),
              const SizedBox(width: 8),
              _buildDropdownFilter<String?>(
                value: _selectedPosition,
                hint: 'Position',
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Alle Positionen')),
                  ..._positions.map((pos) => DropdownMenuItem<String?>(
                    value: pos,
                    child: Text(pos),
                  )),
                ],
                onChanged: _showFormation ? null : (value) {
                  setState(() => _selectedPosition = value);
                  _fetchData();
                },
              ),
              IconButton(
                icon: Icon(_showFormation ? Icons.list : Icons.sports_soccer),
                tooltip: _showFormation ? "Listenansicht" : "Feldansicht",
                onPressed: () {
                  final newShowFormation = !_showFormation;
                  setState(() {
                    _showFormation = newShowFormation;
                    if (newShowFormation) {
                      // Reset Filter für Formation
                      if (_selectedTeamId != null || _selectedPosition != null) {
                        _selectedTeamId = null;
                        _selectedPosition = null;
                        _fetchData();
                      } else {
                        _calculateInitialBestFormation();
                      }
                    }
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownFilter<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        hint: Text(hint, style: const TextStyle(fontSize: 12)),
        items: items,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 12, color: Colors.black),
      ),
    );
  }

  void _showSpieltagDropdown(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return ListView.builder(
          itemCount: _spieltage.length,
          itemBuilder: (BuildContext context, int index) {
            final spieltag = _spieltage.reversed.toList()[index];
            return ListTile(
              title: Text('Spieltag $spieltag'),
              onTap: () {
                setState(() {
                  _selectedSpieltag = spieltag;
                });
                _fetchData();
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPlayerListView() {
    if (_topPlayers.isEmpty) {
      return const Center(
        child: Text(
            "Keine Spieler für diesen Filter gefunden.",
            style: TextStyle(color: Colors.grey, fontSize: 16)
        ),
      );
    }
    return ListView.builder(
      itemCount: _topPlayers.length,
      itemBuilder: (context, index) {
        final player = _topPlayers[index];
        return PlayerListItem(
          rank: index + 1,
          profileImageUrl: player['profilbild_url'],
          playerName: player['name'],
          teamImageUrl: player['team_image_url'],
          marketValue: player['marktwert'],
          score: player['total_punkte'],
          maxScore: _showGesamt ? (_spieltage.length * 250 * 0.5).toInt() : 250,

          // Neue Felder für PlayerListItem (falls benötigt)
          position: player['position'] ?? '',
          id: player['id'],

          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PlayerScreen(playerId: player['id']),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFormationView() {
    if (_isCalculatingFormation) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_bestFormation == null || _selectedFormationName == null) {
      return const Center(
        child: Text("Keine gültige Formation gefunden."),
      );
    }

    final players = (_bestFormation!['players'] as List)
        .map((p) => PlayerInfo(
      id: p['id'],
      name: p['name'],
      position: p['position'],
      profileImageUrl: p['profilbild_url'],
      rating: p['total_punkte'],
      maxRating: _showGesamt? (_spieltage.length*250*0.8).toInt(): 250,
      goals: 0,
      assists: 0,
      ownGoals: 0,
    ))
        .toList();

    return LayoutBuilder(builder: (context, constraints) {
      final sortedFormationKeys = _allFormations.keys.toList()..sort();

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              children: [
                DropdownButton<String>(
                  value: _selectedFormationName,
                  isExpanded: true,
                  items: sortedFormationKeys.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text('Formation: $value'),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null && newValue != _selectedFormationName) {
                      _calculateTeamForSelectedFormation(newValue);
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: MatchFormationDisplay(
              homeFormation: _selectedFormationName!,
              homePlayers: players,
              homeColor: Colors.blue,
              onPlayerTap: (playerId, radius) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PlayerScreen(playerId: playerId),
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}