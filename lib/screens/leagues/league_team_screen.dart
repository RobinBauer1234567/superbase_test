// lib/screens/leagues/league_team_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/utils/color_helper.dart'; // Für die Rating-Farben
import 'package:premier_league/screens/screenelements/player_list_item.dart';

class LeagueTeamScreen extends StatefulWidget {
  final int leagueId;

  const LeagueTeamScreen({super.key, required this.leagueId});

  @override
  State<LeagueTeamScreen> createState() => _LeagueTeamScreenState();
}

class _LeagueTeamScreenState extends State<LeagueTeamScreen> {
  bool _isLoading = true;
  bool _isListView = false;

  Map<String, List<String>> _allFormations = {};
  String _selectedFormationName = '4-4-2';

  List<PlayerInfo> _fieldPlayers = [];
  List<PlayerInfo> _substitutePlayers = [];
  String? _filterTeam;
  String? _filterPosition;

  // --- SPIELTAG, PUNKTE & LOCK VARIABLEN ---
  bool _isFormationLocked = false;
  List<int> _frozenPlayerIds = [];
  int _selectedRound = 1;
  int _latestActiveRound = 1;
  int _matchdayPoints = 0;
  bool _isViewingHistory = false;
  // --------------------------------

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  int _getMarktwert(dynamic playerMap) {
    if (playerMap == null) return 0;
    final analytics = playerMap['spieler_analytics'];
    if (analytics is List && analytics.isNotEmpty) {
      return _toInt(analytics[0]['marktwert']);
    } else if (analytics is Map) {
      return _toInt(analytics['marktwert']);
    }
    return 0;
  }

  Map<String, dynamic> _getStats(dynamic playerMap) {
    if (playerMap == null) return <String, dynamic>{};
    final analytics = playerMap['spieler_analytics'];
    final stats = analytics is Map ? analytics['gesamtstatistiken'] : null;
    if (stats is Map<String, dynamic>) return stats;
    if (stats is Map) return Map<String, dynamic>.from(stats);
    return <String, dynamic>{};
  }

  @override
  void initState() {
    super.initState();
    _initMatchdayData();
  }

  // --- Initialisierung beim Starten des Screens ---
  Future<void> _initMatchdayData() async {
    setState(() => _isLoading = true);
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final seasonId = dataManagement.seasonId;

    // Aktuellen Spieltag abfragen (z.B. 27)
    final currentRound = await dataManagement.supabaseService.getCurrentRound(seasonId);

    _latestActiveRound = currentRound;
    _selectedRound = currentRound;
    _isViewingHistory = false;

    // Daten für diesen Spieltag laden
    await _loadDataForRound(_selectedRound);
  }

  // --- Wechseln zwischen den Spieltagen (Historie) ---
  Future<void> _changeRound(int newRound) async {
    if (newRound < 1 || newRound > _latestActiveRound) return;

    setState(() {
      _selectedRound = newRound;
      _isViewingHistory = newRound != _latestActiveRound;
    });

    await _loadDataForRound(newRound);
  }

  // --- DIE NEUE "SINGLE SOURCE OF TRUTH" LADE-LOGIK ---
  Future<void> _loadDataForRound(int round) async {
    setState(() => _isLoading = true);
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final service = dataManagement.supabaseService;
    final seasonId = dataManagement.seasonId;
    final userId = service.supabase.auth.currentUser!.id;

    try {
      // 1. Alle verfügbaren Formations-Varianten laden
      var formations = await service.fetchFormationsFromDb();

      // 2. Kader des Users aus der Datenbank holen (Liefert standardmäßig alle auf die Bank/Index 99)
      final playersRaw = await service.fetchUserLeaguePlayers(widget.leagueId);

      // 3. Den Snapshot / Zustand für exakt diese Runde abfragen
      final state = await service.fetchMatchdayState(
        userId: userId,
        leagueId: widget.leagueId,
        seasonId: seasonId,
        round: round,
      );

      // 4. Die für diese Runde gespeicherte Formation abfragen
      String? savedFormationName = await service.fetchUserFormation(widget.leagueId, seasonId, round);

      // --- DATEN VERARBEITEN ---
      final frozenPlayersFull = state['frozen_players_full'] as List<dynamic>? ?? [];
      final bool isLocked = state['is_formation_locked'] ?? false;
      final List<int> frozenIds = List<int>.from(state['frozen_player_ids'] ?? []);

      int totalPts = 0;
      List<PlayerInfo> field = List.generate(11, (index) => _createPlaceholder(index));
      List<PlayerInfo> bench = [];
      Set<int> processedPlayerIds = {};

      // Snapshot als leicht abrufbare Map aufbereiten
      Map<int, Map<String, dynamic>> snapshotMap = {};
      for (var fp in frozenPlayersFull) {
        snapshotMap[fp['player_id']] = fp;
        totalPts += _toInt(fp['points']);
      }

      // A) AKTUELLE KADERSPIELER VERTEILEN
      for (var p in playersRaw) {
        final int pId = _toInt(p['id'], fallback: -9999);
        processedPlayerIds.add(pId);

        int rating = 0;
        int fIndex = 99; // Standardmäßig Bank

        // Falls der Spieler einen Snapshot-Eintrag für diesen Spieltag hat, übernimmt dieser die Kontrolle!
        if (snapshotMap.containsKey(pId)) {
          final snapData = snapshotMap[pId]!;
          fIndex = _toInt(snapData['formation_index'], fallback: 99);
          rating = _toInt(snapData['points']);
        } else {
          // Falls er keinen hat (z.B. neu gekauft), nehmen wir die regulären Live-Punkte
          try {
            final stats = _getStats(p);
            rating = _toInt(stats['gesamtpunkte']);
          } catch (e) {}
        }

        final playerInfo = PlayerInfo(
          id: pId,
          name: (p['name'] ?? 'Unbekannt').toString(),
          position: p['position'] ?? 'N/A',
          profileImageUrl: p['profilbild_url'],
          rating: rating,
          goals: 0, assists: 0, ownGoals: 0,
          maxRating: 2500,
          teamImageUrl: p['team_image_url'],
          marketValue: _getMarktwert(p),
          teamName: p['team_name'],
        );

        if (fIndex >= 0 && fIndex <= 10) {
          field[fIndex] = playerInfo;
        } else {
          bench.add(playerInfo);
        }
      }

      // B) GEISTER-SPIELER (Verkauft, aber noch im Snapshot der Historie)
      for (var pId in snapshotMap.keys) {
        if (!processedPlayerIds.contains(pId)) {
          final snapData = snapshotMap[pId]!;
          final spielerInfo = snapData['spieler'];
          if (spielerInfo == null) continue;

          final missingPlayer = PlayerInfo(
            id: pId,
            name: "${spielerInfo['name']} (Verkauft)", // Markierung
            position: spielerInfo['position'] ?? 'N/A',
            profileImageUrl: spielerInfo['profilbild_url'],
            rating: _toInt(snapData['points']),
            goals: 0, assists: 0, ownGoals: 0,
          );

          final int fIndex = _toInt(snapData['formation_index'], fallback: 99);
          if (fIndex >= 0 && fIndex <= 10) {
            field[fIndex] = missingPlayer;
          } else {
            bench.add(missingPlayer);
          }
        }
      }

      bench.sort((a, b) => _getPositionOrder(a.position).compareTo(_getPositionOrder(b.position)));

      if (mounted) {
        setState(() {
          _allFormations = formations;

          if (savedFormationName != null && _allFormations.containsKey(savedFormationName)) {
            _selectedFormationName = savedFormationName;
          } else if (_allFormations.isNotEmpty) {
            _selectedFormationName = '4-4-2'; // Standard-Fallback
          }

          _fieldPlayers = field;
          _substitutePlayers = bench;

          // In der Historie ist IMMER alles komplett gesperrt
          _isFormationLocked = isLocked || _isViewingHistory;
          _frozenPlayerIds = frozenIds;
          _matchdayPoints = totalPts;

          _updatePlaceholderNames();
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Fehler beim Laden der Aufstellung: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- SPEICHERN (Nur noch direkt für den aktuellen Spieltag) ---
  Future<void> _saveLineupToDb() async {
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final service = dataManagement.supabaseService;
    final seasonId = dataManagement.seasonId;

    List<Map<String, dynamic>> updates = [];

    for (int i = 0; i < _fieldPlayers.length; i++) {
      if (_fieldPlayers[i].id > 0) {
        updates.add({'player_id': _fieldPlayers[i].id, 'index': i});
      }
    }

    for (int i = 0; i < _substitutePlayers.length; i++) {
      updates.add({'player_id': _substitutePlayers[i].id, 'index': 11 + i});
    }

    // Übergibt nun auch seasonId und Runde an deine neue Methode
    await service.saveTeamLineup(
        widget.leagueId,
        seasonId,
        _selectedRound,
        _selectedFormationName,
        updates
    );
    print("Aufstellung & Formation für Runde $_selectedRound gespeichert.");
  }

  List<PlayerInfo> _getFilteredPlayers() {
    List<PlayerInfo> allPlayers = [
      ..._fieldPlayers.where((p) => p.id > 0),
      ..._substitutePlayers
    ];

    if (_filterTeam != null) {
      allPlayers = allPlayers.where((p) => p.teamName == _filterTeam).toList();
    }
    if (_filterPosition != null) {
      allPlayers = allPlayers.where((p) => p.position.contains(_filterPosition!)).toList();
    }

    allPlayers.sort((a, b) => b.rating.compareTo(a.rating));
    return allPlayers;
  }

  List<String> _getAvailableTeams() {
    final all = [..._fieldPlayers.where((p) => p.id > 0), ..._substitutePlayers];
    final teams = all.map((p) => p.teamName).whereType<String>().toSet().toList();
    teams.sort();
    return teams;
  }

  List<String> _getAvailablePositions() {
    final all = [..._fieldPlayers.where((p) => p.id > 0), ..._substitutePlayers];
    final positions = <String>{};
    for (var p in all) {
      p.position.split(',').forEach((pos) => positions.add(pos.trim()));
    }
    final sortedList = positions.toList()..sort();
    return sortedList;
  }

  void _updatePlaceholderNames() {
    final positions = _allFormations[_selectedFormationName];
    if (positions == null || positions.length != 11) return;

    for (int i = 0; i < 11; i++) {
      if (_fieldPlayers[i].id < 0) {
        _fieldPlayers[i] = PlayerInfo(
          id: _fieldPlayers[i].id,
          name: positions[i],
          position: positions[i],
          rating: 0, goals: 0, assists: 0, ownGoals: 0,
          profileImageUrl: null,
        );
      }
    }
  }

  PlayerInfo _createPlaceholder(int index) {
    if (index == 0) return const PlayerInfo(id: -1, name: "TW", position: "TW", rating: 0, goals: 0, assists: 0, ownGoals: 0);
    return PlayerInfo(id: -1 - index, name: "POS", position: "Feld", rating: 0, goals: 0, assists: 0, ownGoals: 0);
  }

  void _handlePlayerTap(int playerId, double radius) {
    if (playerId < 0) {
      if (_isViewingHistory) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Historische Aufstellungen können nicht bearbeitet werden."),
          backgroundColor: Colors.red,
        ));
        return;
      }

      final placeholder = _fieldPlayers.firstWhere(
            (p) => p.id == playerId,
        orElse: () => const PlayerInfo(id: -999, name: "?", position: "", rating: 0, goals: 0, assists: 0, ownGoals: 0),
      );

      if (placeholder.id != -999) {
        _showAvailablePlayersDialog(placeholder, radius);
      }
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (context) => PlayerScreen(playerId: playerId)));
    }
  }

  void _showAvailablePlayersDialog(PlayerInfo placeholder, double sourceRadius) {
    if (_isViewingHistory) return;

    final String requiredPos = placeholder.position.toUpperCase();
    final availablePlayers = _substitutePlayers.where((p) {
      final String playerPos = p.position.toUpperCase();
      return playerPos == requiredPos || playerPos.contains(requiredPos);
    }).toList();

    availablePlayers.sort((a, b) => b.rating.compareTo(a.rating));

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
          elevation: 10,
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7, maxWidth: 400),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("POSITION", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1.0)),
                        const SizedBox(height: 2),
                        Text(placeholder.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                      ],
                    ),
                    IconButton(icon: Icon(Icons.close, color: Colors.grey.shade400), onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: Colors.grey.shade200),
                const SizedBox(height: 16),
                Flexible(
                  child: availablePlayers.isEmpty
                      ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32.0),
                    child: Column(
                      children: [
                        Icon(Icons.person_off_rounded, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text("Keine passenden Spieler", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  )
                      : ListView.separated(
                    shrinkWrap: true,
                    itemCount: availablePlayers.length,
                    separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                    itemBuilder: (ctx, index) {
                      return _buildPlayerDialogItem(availablePlayers[index], placeholder, sourceRadius);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayerDialogItem(PlayerInfo player, PlayerInfo placeholder, double radius) {
    final bool isFrozen = _frozenPlayerIds.contains(player.id);

    return InkWell(
      onTap: () {
        if (isFrozen) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Spieler kann nicht hinzugefügt werden, weil er bereits gespielt hat."),
            backgroundColor: Colors.red,
          ));
        } else {
          _swapPlayer(placeholder, player);
          Navigator.pop(context);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: isFrozen ? Colors.grey.shade300 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.all(12),
        child: Opacity(
          opacity: isFrozen ? 0.5 : 1.0,
          child: Row(
            children: [
              Hero(
                tag: 'player_${player.id}_dialog',
                child: PlayerAvatar(
                  player: player,
                  teamColor: Theme.of(context).primaryColor,
                  radius: radius,
                  isLocked: isFrozen,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(player.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.blueGrey.shade100),
                          ),
                          child: Text(player.position, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700)),
                        ),
                        const SizedBox(width: 8),
                        Text("${player.rating} Pkt", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                isFrozen ? Icons.lock : Icons.arrow_forward_ios_rounded,
                size: isFrozen ? 20 : 16,
                color: isFrozen ? Colors.red.shade400 : Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _swapPlayer(PlayerInfo placeholder, PlayerInfo newPlayer) {
    setState(() {
      _substitutePlayers.removeWhere((p) => p.id == newPlayer.id);
      final index = _fieldPlayers.indexWhere((p) => p.id == placeholder.id);
      if (index != -1) {
        _fieldPlayers[index] = newPlayer;
        if (placeholder.id > 0) {
          _substitutePlayers.add(placeholder);
          _substitutePlayers.sort((a, b) => _getPositionOrder(a.position).compareTo(_getPositionOrder(b.position)));
        }
      }
    });
    _saveLineupToDb();
  }

  int _getPositionOrder(String? position) {
    if (position == null) return 99;
    final pos = position.toUpperCase();
    if (pos.contains('GK') || pos.contains('TW')) return 0;
    if (pos.contains('IV') || pos.contains('RV') || pos.contains('LV')) return 2;
    if (pos.contains('ZDM') || pos.contains('ZM') || pos.contains('ZOM')) return 3;
    if (pos.contains('ST') || pos.contains('RF') || pos.contains('LF')) return 4;
    return 5;
  }

  void _generateFieldPlaceholders() {
    final positions = _allFormations[_selectedFormationName];
    if (positions == null || positions.length != 11) return;
    List<PlayerInfo> newField = [];
    for (int i = 0; i < 11; i++) {
      newField.add(PlayerInfo(id: -1 - i, name: positions[i], position: positions[i], rating: 0, goals: 0, assists: 0, ownGoals: 0, profileImageUrl: null));
    }
    setState(() { _fieldPlayers = newField; });
  }

  void _handlePlayerDrop(PlayerInfo fieldSlot, PlayerInfo incomingPlayer) {
    if (_isViewingHistory) return;

    if (_frozenPlayerIds.contains(fieldSlot.id) || _frozenPlayerIds.contains(incomingPlayer.id)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Spieler ist gelockt und kann nicht getauscht werden!"), backgroundColor: Colors.red));
      return;
    }

    setState(() {
      bool cameFromBench = false;
      int sourceFieldIndex = -1;

      if (_substitutePlayers.any((p) => p.id == incomingPlayer.id)) {
        cameFromBench = true;
        _substitutePlayers.removeWhere((p) => p.id == incomingPlayer.id);
      } else {
        sourceFieldIndex = _fieldPlayers.indexWhere((p) => p.id == incomingPlayer.id);
        if (sourceFieldIndex == -1) return;
      }

      final int targetIndex = _fieldPlayers.indexWhere((p) => p.id == fieldSlot.id);
      if (targetIndex == -1) return;
      if (!cameFromBench && sourceFieldIndex == targetIndex) return;

      if (cameFromBench) {
        if (fieldSlot.id > 0) {
          _substitutePlayers.add(fieldSlot);
          _sortBench();
        }
        _fieldPlayers[targetIndex] = incomingPlayer;
      } else {
        _fieldPlayers[targetIndex] = incomingPlayer;
        final List<String> positions = _allFormations[_selectedFormationName] ?? [];
        if (sourceFieldIndex < positions.length) {
          final String roleName = positions[sourceFieldIndex];
          _fieldPlayers[sourceFieldIndex] = PlayerInfo(id: -1 - sourceFieldIndex, name: roleName, position: roleName, rating: 0, goals: 0, assists: 0, ownGoals: 0, profileImageUrl: null);
        }
        if (fieldSlot.id > 0) {
          _substitutePlayers.add(fieldSlot);
          _sortBench();
        }
      }
    });
    _saveLineupToDb();
  }

  void _handleMoveToBench(PlayerInfo player) {
    if (_isViewingHistory) return;

    if (_frozenPlayerIds.contains(player.id)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Spieler spielt bereits und kann nicht auf die Bank!"), backgroundColor: Colors.red));
      return;
    }

    setState(() {
      final int index = _fieldPlayers.indexWhere((p) => p.id == player.id);
      if (index != -1) {
        final List<String> positions = _allFormations[_selectedFormationName] ?? [];
        if (index < positions.length) {
          final String roleName = positions[index];
          _fieldPlayers[index] = PlayerInfo(id: -1 - index, name: roleName, position: roleName, rating: 0, goals: 0, assists: 0, ownGoals: 0, profileImageUrl: null);
        }
        if (!_substitutePlayers.any((p) => p.id == player.id)) {
          _substitutePlayers.add(player);
          _sortBench();
        }
      }
    });
    _saveLineupToDb();
  }

  void _sortBench() {
    _substitutePlayers.sort((a, b) => _getPositionOrder(a.position).compareTo(_getPositionOrder(b.position)));
  }

  // --- UI: SPIELTAGS-SELECTOR ---
  Widget _buildMatchdaySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _selectedRound > 1 ? () => _changeRound(_selectedRound - 1) : null,
                color: _selectedRound > 1 ? Theme.of(context).primaryColor : Colors.grey,
              ),
              Text(
                "Spieltag $_selectedRound",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _selectedRound < _latestActiveRound ? () => _changeRound(_selectedRound + 1) : null,
                color: _selectedRound < _latestActiveRound ? Theme.of(context).primaryColor : Colors.grey,
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "$_matchdayPoints Pkt",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormationDropdown() {
    final sortedFormationKeys = _allFormations.keys.toList()..sort();
    return Card(
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedFormationName,
            isExpanded: true,
            icon: Icon(
              _isFormationLocked ? Icons.lock : Icons.keyboard_arrow_down_rounded,
              color: _isFormationLocked ? Colors.red : null,
            ),
            onChanged: _isFormationLocked ? null : (String? newValue) {
              if (newValue != null && newValue != _selectedFormationName) {
                setState(() {
                  _selectedFormationName = newValue;
                  for (var player in _fieldPlayers) {
                    if (player.id > 0) _substitutePlayers.add(player);
                  }
                  _substitutePlayers.sort((a, b) => _getPositionOrder(a.position).compareTo(_getPositionOrder(b.position)));
                  _generateFieldPlaceholders();
                });
                _saveLineupToDb();
              }
            },
            items: sortedFormationKeys.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text('Formation: $value', style: TextStyle(fontWeight: FontWeight.bold, color: _isFormationLocked ? Colors.grey : Colors.black)),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    final teams = _getAvailableTeams();
    final positions = _getAvailablePositions();

    return Row(
      children: [
        Expanded(
          child: Card(
            elevation: 2, shadowColor: Colors.black12, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _filterTeam, hint: const Text("Team", style: TextStyle(fontSize: 13)), isExpanded: true, icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  items: [const DropdownMenuItem(value: null, child: Text("Alle Teams")), ...teams.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)))],
                  onChanged: (val) => setState(() => _filterTeam = val),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            elevation: 2, shadowColor: Colors.black12, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _filterPosition, hint: const Text("Pos", style: TextStyle(fontSize: 13)), isExpanded: true, icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  items: [const DropdownMenuItem(value: null, child: Text("Alle Pos")), ...positions.map((p) => DropdownMenuItem(value: p, child: Text(p)))],
                  onChanged: (val) => setState(() => _filterPosition = val),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTeamListView() {
    final players = _getFilteredPlayers();
    final primaryColor = Theme.of(context).primaryColor;
    if (players.isEmpty) return const Center(child: Text("Keine Spieler gefunden"));

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final player = players[index];
        return PlayerListItem(
          rank: index + 1, profileImageUrl: player.profileImageUrl, playerName: player.name, teamImageUrl: player.teamImageUrl,
          marketValue: player.marketValue, score: player.rating, maxScore: player.maxRating, position: player.position,
          id: player.id, goals: player.goals, assists: player.assists, ownGoals: player.ownGoals, teamColor: primaryColor,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: player.id))),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _fieldPlayers.isEmpty) return const Center(child: CircularProgressIndicator());
    final primaryColor = Theme.of(context).primaryColor;
    final List<String> currentRequiredPositions = _allFormations[_selectedFormationName] ?? [];

    return Column(
      children: [
        _buildMatchdaySelector(),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(child: _isListView ? _buildFilterBar() : _buildFormationDropdown()),
              const SizedBox(width: 8),
              Card(
                elevation: 2, shadowColor: Colors.black12, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), margin: EdgeInsets.zero,
                child: IconButton(
                  icon: Icon(_isListView ? Icons.sports_soccer : Icons.list_alt), color: primaryColor, tooltip: _isListView ? "Spielfeldansicht" : "Listenansicht",
                  onPressed: () => setState(() => _isListView = !_isListView),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _isListView
              ? _buildTeamListView()
              : MatchFormationDisplay(
            homeFormation: _selectedFormationName,
            homePlayers: _fieldPlayers,
            homeColor: primaryColor,
            onPlayerTap: _handlePlayerTap,
            substitutes: _substitutePlayers,
            onPlayerDrop: _handlePlayerDrop,
            onMoveToBench: _handleMoveToBench,
            requiredPositions: currentRequiredPositions,
            frozenPlayerIds: _frozenPlayerIds,
          ),
        ),
      ],
    );
  }
}