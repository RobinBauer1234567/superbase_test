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
  int _overallTeamPoints = 0;
  bool _isViewingHistory = false;
  int _currentRound = 1;
  DateTime? _matchdayStart;
  DateTime? _matchdayEnd;
  final Map<int, Map<String, dynamic>> _matchdayMetaByRound = {};
  // --------------------------------

  MatchdayPhase get _matchdayPhase {
    final now = DateTime.now().toUtc();
    final start = _matchdayStart;
    final end = _matchdayEnd;

    if (start == null || end == null) return MatchdayPhase.inProgress;
    if (now.isBefore(start)) return MatchdayPhase.before;
    if (now.isAfter(end)) return MatchdayPhase.after;
    return MatchdayPhase.inProgress;
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  @override
  void initState() {
    super.initState();
    _initMatchdayData();
  }

  // --- Initialisierung beim Starten des Screens ---
// --- Initialisierung beim Starten des Screens ---
  Future<void> _initMatchdayData() async {
    setState(() => _isLoading = true);
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final seasonId = dataManagement.seasonId;

    // 1. Aktuellen Spieltag abfragen (hier starten wir standardmäßig)
    final currentRound = await dataManagement.supabaseService.getCurrentRound(seasonId);
    _currentRound = currentRound;

    // 2. NEU: Alle Spieltage abfragen, um das Maximum (z.B. 38) zu finden.
    // Dadurch darf der User auch nach rechts klicken, um für die Zukunft aufzustellen!
    final allSpieltage = await dataManagement.supabaseService.fetchAllSpieltage(seasonId);
    for (final dynamic item in allSpieltage) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item as Map);
      final round = _toInt(row['round'], fallback: -1);
      if (round > 0) {
        _matchdayMetaByRound[round] = row;
      }
    }

    final allRounds = _matchdayMetaByRound.keys.toList();
    int maxRound = currentRound;
    if (allRounds.isNotEmpty) {
      maxRound = allRounds.reduce((curr, next) => curr > next ? curr : next);
    }

    // Das absolute Limit ist nun das Saisonende, nicht mehr das aktuelle Wochenende!
    _latestActiveRound = maxRound;
    _selectedRound = currentRound;
    _isViewingHistory = false;

    // Daten für den aktuellen Spieltag laden
    await _loadDataForRound(_selectedRound);
  }
  // --- Wechseln zwischen den Spieltagen (Historie) ---
  // --- Wechseln zwischen den Spieltagen (Historie) ---
  Future<void> _changeRound(int newRound) async {
    if (newRound < 1 || newRound > _latestActiveRound) return;

    setState(() {
      _selectedRound = newRound;
      // WICHTIG: Weg mit der pauschalen Sperre! Wir vertrauen ab jetzt
      // zu 100% auf das 'is_locked' aus der Datenbank.
      _isViewingHistory = false;
    });

    await _loadDataForRound(newRound);
  }

  // --- DIE NEUE, SAUBERE LADE-LOGIK ---
  Future<void> _loadDataForRound(int round) async {
    setState(() => _isLoading = true);
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final service = dataManagement.supabaseService;
    final seasonId = dataManagement.seasonId;

    try {
      // 1. Alle verfügbaren Formations-Varianten laden
      var formations = await service.fetchFormationsFromDb();

      // 2. Snapshot abrufen ODER ERSTELLEN (Die Magie passiert hier im RPC!)
      final matchdayData = await service.fetchMatchdayData(
          widget.leagueId,
          seasonId,
          round
      );

      if (matchdayData.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return; // Kein Snapshot erstellbar / abrufbar
      }

      final pointsData = matchdayData['points_data'] ?? {};
      final playersData = matchdayData['players'] as List<dynamic>? ?? [];

      final roundMeta = _matchdayMetaByRound[round] ?? <String, dynamic>{};
      final DateTime? matchdayStart = DateTime.tryParse(
        (roundMeta['matchday_start'] ?? '').toString(),
      )?.toUtc();
      final DateTime? matchdayEnd = DateTime.tryParse(
        (roundMeta['matchday_end'] ?? '').toString(),
      )?.toUtc();

      // --- DATEN VERARBEITEN ---
      String? savedFormationName = pointsData['formation'];
      bool isLocked = pointsData['is_locked'] ?? false;
      int totalPts = pointsData['total_points'] ?? 0;

      List<PlayerInfo> field = List.generate(11, (index) => _createPlaceholder(index));
      List<PlayerInfo> bench = [];
      List<int> frozenIds = [];

      for (var pd in playersData) {
        final spieler = pd['spieler'];
        if (spieler == null) continue;

        final int pId = _toInt(spieler['id'], fallback: -9999);
        final int fIndex = _toInt(pd['formation_index'], fallback: 99);
        final int rating = _toInt(pd['points'], fallback: 0);

        // Spieler ist gelockt, wenn er selbst in der DB gelockt ist,
        // der Spieltag gesperrt ist oder wir die Historie anschauen.
        final bool playerLocked = pd['is_locked'] ?? false;
        if (playerLocked || _isViewingHistory) {
          frozenIds.add(pId);
        }

        final team = spieler['team'];
        final analytics = spieler['spieler_analytics'];

        int mw = 0;
        if (analytics is Map) {
          mw = _toInt(analytics['marktwert']);
        } else if (analytics is List && analytics.isNotEmpty) {
          mw = _toInt(analytics[0]['marktwert']);
        }

        final playerInfo = PlayerInfo(
          id: pId,
          name: (spieler['name'] ?? 'Unbekannt').toString(),
          position: spieler['position'] ?? 'N/A',
          profileImageUrl: spieler['profilbild_url'],
          rating: rating,
          goals: 0, assists: 0, ownGoals: 0,
          maxRating: 2500,
          teamImageUrl: team != null ? team['image_url'] : null,
          marketValue: mw,
          teamName: team != null ? team['name'] : null,
        );

        if (fIndex >= 0 && fIndex <= 10) {
          field[fIndex] = playerInfo;
        } else {
          bench.add(playerInfo);
        }
      }

      bench.sort((a, b) => _getPositionOrder(a.position).compareTo(_getPositionOrder(b.position)));

      if (mounted) {
        int teamTotalPoints = _overallTeamPoints;
        try {
          final ranking = await service.fetchOverallRanking(widget.leagueId);
          final userId = service.supabase.auth.currentUser?.id;
          if (userId != null) {
            final currentUserRow = ranking.cast<Map<String, dynamic>?>().firstWhere(
                  (row) => row?['user_id']?.toString() == userId,
                  orElse: () => null,
                );
            if (currentUserRow != null) {
              teamTotalPoints = _toInt(currentUserRow['total_points']);
            }
          }
        } catch (_) {
          // Fallback: Bisherigen Wert behalten.
        }

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
          _overallTeamPoints = teamTotalPoints;
          _matchdayStart = matchdayStart;
          _matchdayEnd = matchdayEnd;

          _updatePlaceholderNames();
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Fehler beim Laden der Aufstellung: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- SPEICHERN ---
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
    final phase = _matchdayPhase;
    final bool isCurrentRound = _selectedRound == _currentRound;
    final bool showOverallPoints = phase == MatchdayPhase.before;
    final int displayedPoints = showOverallPoints ? _overallTeamPoints : _matchdayPoints;
    final String pointsLabel = showOverallPoints ? 'Gesamt' : 'Spieltag';
    final Color pointsColor = showOverallPoints
        ? Theme.of(context).primaryColor
        : getColorForRating(displayedPoints, 2500);
    final String phaseLabel = switch (phase) {
      MatchdayPhase.before => 'Vor Matchday-Start',
      MatchdayPhase.inProgress => 'Matchday läuft',
      MatchdayPhase.after => 'Matchday beendet',
    };

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
              if (isCurrentRound)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.green.shade400),
                  ),
                  child: const Text(
                    'AKTUELL',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _selectedRound < _latestActiveRound ? () => _changeRound(_selectedRound + 1) : null,
                color: _selectedRound < _latestActiveRound ? Theme.of(context).primaryColor : Colors.grey,
              ),
            ],
          ),
          Row(
            children: [
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  phaseLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                    fontSize: 12,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: pointsColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "$displayedPoints Pkt · $pointsLabel",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: pointsColor,
                  ),
                ),
              ),
            ],
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

enum MatchdayPhase {
  before,
  inProgress,
  after,
}
