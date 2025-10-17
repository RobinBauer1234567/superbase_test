// lib/screens/premier_league/top_team_screen.dart
import 'package:flutter/material.dart';
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
  bool _showFormation = false; // Neu: Umschalter für die Ansicht

  // Data
  List<Map<String, dynamic>> _topPlayers = [];
  List<Map<String, dynamic>> _teams = [];
  List<String> _positions = [];
  Map<String, dynamic>? _bestFormation; // Neu: Speichert die beste Elf

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
      _calculateBestFormation();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _fetchFilterData() async {
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final seasonId = dataManagement.seasonId;

    // Teams für die aktuelle Saison abrufen
    final teamsResponse = await Supabase.instance.client
        .from('season_teams')
        .select('team:team(id, name, image_url)')
        .eq('season_id', seasonId);
    if (teamsResponse.isNotEmpty) {
      _teams =
          teamsResponse.map((e) => e['team'] as Map<String, dynamic>).toList();
      _teams.sort((a, b) => a['name'].compareTo(b['name']));
    }

    // Gespielte Spieltage abrufen
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

    // Alle einzigartigen Positionen abrufen
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
      // seasonId kann int oder String sein - normalisiere beides
      final dynamic rawSeasonId = dataManagement.seasonId;
      final String seasonIdStr = rawSeasonId.toString();
      final int? seasonIdInt = int.tryParse(seasonIdStr);

      var query = Supabase.instance.client
          .from('spieler')
          .select('id, name, profilbild_url, position, gesamtstatistiken, season_players!inner(team:team(id, name, image_url))')
          .eq('season_players.season_id', '$seasonIdInt');

      final teamId = _selectedTeamId;
      if (teamId != null) {
        query = query.eq('season_players.team_id', teamId);
      }

      // Serverseitiges ilike entfernen — clientseitig filtern
      final response = await query;
      print('🧾 _fetchGesamtStats: DB Einträge erhalten: ${response.length}');

      List<Map<String, dynamic>> topPlayersList = [];
      final String? selectedPosition = _selectedPosition?.toLowerCase();

      for (var player in response) {
        try {
          final dynamic stats = player['gesamtstatistiken'];
          // Robust: finde seasonStats in verschiedenen möglichen Strukturen
          dynamic seasonStats;

          if (stats is Map) {
            // JSON decode -> keys sind meistens Strings, aber wir prüfen beides
            if (stats.containsKey(seasonIdStr)) {
              seasonStats = stats[seasonIdStr];
            } else if (seasonIdInt != null && stats.containsKey(seasonIdInt)) {
              seasonStats = stats[seasonIdInt];
            } else {
              // Fallback: suche erste passende Map-Entry dessen key numeric mit seasonId übereinstimmt
              for (var k in stats.keys) {
                if (k.toString() == seasonIdStr) {
                  seasonStats = stats[k];
                  break;
                }
              }
            }
          } else if (stats is List) {
            // evtl. Liste mit Objekten, die season_id enthalten
            seasonStats = stats.firstWhere(
                  (e) => (e is Map && (e['season_id']?.toString() == seasonIdStr || e['season_id'] == seasonIdInt)),
              orElse: () => null,
            );
          }

          // seasonPlayers robust auslesen
          final dynamic seasonPlayers = player['season_players'];
          dynamic team;
          if (seasonPlayers is List && seasonPlayers.isNotEmpty) {
            team = seasonPlayers[0]?['team'];
          } else if (seasonPlayers is Map) {
            team = seasonPlayers['team'];
          }

          // Wenn keine seasonStats oder kein Team -> skip
          if (seasonStats == null || team == null) {
            // optional: kurze Debug-Info nur für die Fälle, die gefiltert werden
            // print('⚠️ skipping player ${player['id']} — seasonStats: ${seasonStats==null}, team: ${team==null}');
            continue;
          }

          // Clientseitiges Positionsfilter: handle String OR List
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
            'total_punkte': totalPunkte,
            'position': player['position'],
          });
        } catch (e) {
          // Einzelne Spieler können fehlschlagen — skip, aber weiter verarbeiten
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

      print('✅ _fetchGesamtStats: Gefilterte Spieler: ${_topPlayers.length}');
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
          .select('punkte, spieler:spieler!inner(id, name, profilbild_url, position), spiel!inner(round, season_id)')
          .eq('spiel.round', spieltag)
          .eq('spiel.season_id', seasonId);

      // Kein serverseitiges ilike auf 'spieler.position' — filtere in Dart
      final response = await query;

      // Spieler-IDs sammeln
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

        // Clientseitiges Positionsfilter
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
          'total_punkte': rating['punkte'],
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

  // Neue Methode zur Berechnung der besten Formation
  void _calculateBestFormation() {
    final formations = {
      '4-4-2': ['TW', 'LV', 'IV', 'IV', 'RV', 'LM', 'ZM', 'ZM', 'RM', 'ST', 'ST'],
      '4-3-3': ['TW', 'IV', 'IV', 'LV', 'RV', 'ZM', 'ZM', 'ZM', 'LA', 'RA', 'ST'],
      '3-5-2': ['TW', 'IV', 'IV', 'IV', 'ZM', 'ZM', 'LM', 'RM', 'ZOM', 'ST', 'ST'],
      '4-2-3-1': ['TW', 'IV', 'IV', 'LV', 'RV', 'ZDM', 'ZDM', 'LM', 'RM', 'ZOM', 'ST'],
    };

    Map<String, dynamic>? bestFormation;
    int maxScore = 0;

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
        bestFormation = {
          'name': formationName,
          'players': currentFormation,
          'score': maxScore,
        };
      }
    });

    setState(() {
      _bestFormation = bestFormation;
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

  Widget _buildPlayerListView() {
    return ListView.builder(
      itemCount: _topPlayers.length,
      itemBuilder: (context, index) {
        final player = _topPlayers[index];
        return PlayerListItem(
          rank: index + 1,
          profileImageUrl: player['profilbild_url'],
          playerName: player['name'],
          teamImageUrl: player['team_image_url'],
          score: player['total_punkte'],
          maxScore: _showGesamt ? (_spieltage.length * 250 * 0.8).toInt() : 250,
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
    if (_bestFormation == null) {
      return const Center(
        child: Text("Keine gültige Formation gefunden."),
      );
    }

    final formationName = _bestFormation!['name'] as String;
    final players = (_bestFormation!['players'] as List)
        .map((p) => PlayerInfo(
      id: p['id'],
      name: p['name'],
      position: p['position'],
      profileImageUrl: p['profilbild_url'],
      rating: p['total_punkte'],
      goals: 0, // Diese Daten sind hier nicht verfügbar
      assists: 0,
      ownGoals: 0,
    ))
        .toList();

    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Beste Formation: $formationName (Gesamtpunkte: ${_bestFormation!['score']})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          // Hier wird jetzt das neue, flexible Widget verwendet
          MatchFormationDisplay(
            homeFormation: formationName,
            homePlayers: players,
            homeColor: Colors.blue, // Oder eine andere gewünschte Farbe
            onPlayerTap: (playerId) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlayerScreen(playerId: playerId),
                ),
              );
            },
          ),
        ],
      ),
    );  }


  Widget _buildFilterBar() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Row(
          children: [
            // Gesamt/Spieltag Buttons
            ToggleButtons(
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
            const Spacer(),
            // Team Filter
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
              onChanged: (value) {
                setState(() => _selectedTeamId = value);
                _fetchData();
              },
            ),
            const SizedBox(width: 8),
            // Positions Filter
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
              onChanged: (value) {
                setState(() => _selectedPosition = value);
                _fetchData();
              },
            ),
            IconButton(
              icon: Icon(_showFormation ? Icons.list : Icons.sports_soccer),
              onPressed: () {
                setState(() {
                  _showFormation = !_showFormation;
                });
                if (_showFormation) {
                  _calculateBestFormation();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownFilter<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
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
}