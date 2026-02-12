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
  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final seasonId = dataManagement.seasonId;
    final service = dataManagement.supabaseService;
    final seasonIdStr = seasonId.toString();

    var formations = await service.fetchFormationsFromDb();
    final savedFormationName = await service.fetchUserFormation(
      widget.leagueId,
    );

    final playersRaw = await service.fetchUserLeaguePlayers(widget.leagueId);

    List<PlayerInfo> field = List.generate(
      11,
      (index) => _createPlaceholder(index),
    );
    List<PlayerInfo> bench = [];

    // 3. Spieler verteilen
    for (var p in playersRaw) {
      int rating = 0;
      try {
        final dynamic stats = p['gesamtstatistiken'];
        dynamic seasonStats;

        if (stats is Map) {
          if (stats.containsKey(seasonIdStr)) {
            seasonStats = stats[seasonIdStr];
          } else if (stats.containsKey(seasonId)) {
            seasonStats = stats[seasonId];
          }
        } else if (stats is List) {
          seasonStats = stats.firstWhere(
            (e) =>
                (e is Map &&
                    (e['season_id']?.toString() == seasonIdStr ||
                        e['season_id'] == seasonId)),
            orElse: () => null,
          );
        }

        if (seasonStats != null && seasonStats is Map) {
          rating = seasonStats['gesamtpunkte'] ?? 0;
        }
      } catch (e) {
        debugPrint("Fehler bei Punkteberechnung für ${p['name']}: $e");
      }

      final playerInfo = PlayerInfo(
        id: p['id'],
        name: p['name'],
        position: p['position'] ?? 'N/A',
        profileImageUrl: p['profilbild_url'],
        rating: rating,
        goals: 0,
        assists: 0,
        ownGoals: 0,
        maxRating: 2500,
        teamImageUrl: p['team_image_url'],
        marketValue: p['marktwert'],
        teamName: p['team_name'],
      );

      // WICHTIG: Prüfen, wo der Spieler hin soll
      final int fIndex = p['formation_index'] ?? 99;

      if (fIndex >= 0 && fIndex <= 10) {
        // Spieler gehört auf das Feld an Position fIndex
        field[fIndex] = playerInfo;
      } else {
        // Spieler gehört auf die Bank
        bench.add(playerInfo);
      }
    }


    if (mounted) {
      setState(() {
        _allFormations = formations;

        // Gespeicherte Formation setzen (wenn gültig)
        if (savedFormationName != null &&
            _allFormations.containsKey(savedFormationName)) {
          _selectedFormationName = savedFormationName;
        } else if (_allFormations.isNotEmpty) {
          _selectedFormationName = _allFormations.keys.first;
        }

        _fieldPlayers = field;
        _substitutePlayers = bench;

        // Einmal Platzhalter aktualisieren, damit die Namen (IV, ST) zur Formation passen
        // Aber NICHT die Spieler überschreiben, die wir gerade gesetzt haben!
        _updatePlaceholderNames();

        _isLoading = false;
      });
    }
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

    // Sortieren nach Punkten (Top-Team Style)
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
      // Split "IV, RV" -> ["IV", "RV"]
      p.position.split(',').forEach((pos) => positions.add(pos.trim()));
    }
    final sortedList = positions.toList()..sort();
    return sortedList;
  }

  void _updatePlaceholderNames() {
    final positions = _allFormations[_selectedFormationName];
    if (positions == null || positions.length != 11) return;

    for (int i = 0; i < 11; i++) {
      // Wenn es ein Platzhalter ist (ID < 0), aktualisieren wir seine Rolle
      if (_fieldPlayers[i].id < 0) {
        _fieldPlayers[i] = PlayerInfo(
          id: _fieldPlayers[i].id, // ID beibehalten
          name: positions[i], // Neuer Name aus Formation (z.B. "IV")
          position: positions[i], // Neue Position
          rating: 0,
          goals: 0,
          assists: 0,
          ownGoals: 0,
          profileImageUrl: null,
        );
      }
    }
  }

  PlayerInfo _createPlaceholder(int index) {
    // Simpel: Index 0 ist TW, Rest Feld
    if (index == 0)
      return const PlayerInfo(
        id: -1,
        name: "TW",
        position: "TW",
        rating: 0,
        goals: 0,
        assists: 0,
        ownGoals: 0,
      );
    return PlayerInfo(
      id: -1 - index,
      name: "POS",
      position: "Feld",
      rating: 0,
      goals: 0,
      assists: 0,
      ownGoals: 0,
    );
  }


  void _handlePlayerTap(int playerId, double radius) {
    if (playerId < 0) {
      final placeholder = _fieldPlayers.firstWhere(
        (p) => p.id == playerId,
        orElse:
            () => const PlayerInfo(
              id: -999,
              name: "?",
              position: "",
              rating: 0,
              goals: 0,
              assists: 0,
              ownGoals: 0,
            ),
      );

      if (placeholder.id != -999) {
        // HIER: Aufruf der neuen Dialog-Funktion
        _showAvailablePlayersDialog(placeholder, radius);
      }
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlayerScreen(playerId: playerId),
        ),
      );
    }
  }

  void _showAvailablePlayersDialog(PlayerInfo placeholder, double sourceRadius,) {
    final String requiredPos = placeholder.position.toUpperCase();

    // Filter-Logik (unverändert)
    final availablePlayers =
        _substitutePlayers.where((p) {
          final String playerPos = p.position.toUpperCase();
          return playerPos == requiredPos || playerPos.contains(requiredPos);
        }).toList();

    availablePlayers.sort((a, b) => b.rating.compareTo(a.rating));

    // Dialog anzeigen
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Dialog Widget sorgt für das "Kästchen" in der Mitte
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
          ), // Runde Ecken
          elevation: 10,
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.all(20), // Abstand zum Bildschirmrand
          child: Container(
            // Begrenzung der Höhe, damit es nicht den ganzen Screen füllt, wenn die Liste lang ist
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
              maxWidth: 400, // Maximale Breite (gut für Tablets)
            ),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min, // WICHTIG: Schrumpft auf Inhaltgröße
              children: [
                // --- Header im Dialog ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "POSITION",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade500,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          placeholder.name, // z.B. "IV"
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    // Schließen Button (X)
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.grey.shade400),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                Divider(height: 1, color: Colors.grey.shade200),
                const SizedBox(height: 16),

                // --- Liste der Spieler ---
                Flexible(
                  // Flexible macht die Liste scrollbar innerhalb des Dialogs
                  child:
                      availablePlayers.isEmpty
                          ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32.0),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.person_off_rounded,
                                  size: 48,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  "Keine passenden Spieler",
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                          : ListView.separated(
                            shrinkWrap:
                                true, // WICHTIG für dynamische Höhe bei wenigen Items
                            itemCount: availablePlayers.length,
                            separatorBuilder:
                                (ctx, i) => const SizedBox(height: 12),
                            itemBuilder: (ctx, index) {
                              final player = availablePlayers[index];
                              return _buildPlayerDialogItem(
                                player,
                                placeholder,
                                sourceRadius,
                              );
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

  Widget _buildPlayerDialogItem(PlayerInfo player, PlayerInfo placeholder, double radius,) {
    return InkWell(
      onTap: () {
        _swapPlayer(placeholder, player);
        Navigator.pop(context); // Dialog schließen
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50, // Leichter Kontrast zum weißen Dialog
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Avatar (Größe dynamisch vom Feld übernommen)
            Hero(
              tag: 'player_${player.id}_dialog',
              child: PlayerAvatar(
                player: player,
                teamColor: Theme.of(context).primaryColor,
                radius: radius, // Größe vom Feld!
              ),
            ),
            const SizedBox(width: 16),

            // Infos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // Kleines Badge für Position
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.blueGrey.shade100),
                        ),
                        child: Text(
                          player.position,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${player.rating} Pkt",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Einwechseln Icon
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ],
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

  Future<void> _saveLineupToDb() async {
    final service = Provider.of<DataManagement>(context, listen: false).supabaseService;

    // 1. Formation speichern
    await service.updateUserFormation(widget.leagueId, _selectedFormationName);

    // 2. Aufstellung speichern
    List<Map<String, dynamic>> updates = [];

    // Feldspieler (Index 0-10)
    for (int i = 0; i < _fieldPlayers.length; i++) {
      final p = _fieldPlayers[i];
      if (p.id > 0) { // Nur echte Spieler
        updates.add({'player_id': p.id, 'index': i});
      }
    }

    // Bankspieler (Index 11+)
    for (int i = 0; i < _substitutePlayers.length; i++) {
      final p = _substitutePlayers[i];
      updates.add({'player_id': p.id, 'index': 11 + i});
    }

    await service.saveTeamLineup(widget.leagueId, updates);
    print("Aufstellung & Formation gespeichert.");
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


// Diese Methode generiert die Platzhalter basierend auf der aktuellen Formation
  void _generateFieldPlaceholders() {
    // Hole die Positions-Liste (z.B. ["TW", "RV", "IV", ...])
    final positions = _allFormations[_selectedFormationName];

    // Sicherheitscheck
    if (positions == null || positions.length != 11) {
      print("Warnung: Keine oder ungültige Formation für $_selectedFormationName gefunden.");
      return;
    }

    List<PlayerInfo> newField = [];
    for (int i = 0; i < 11; i++) {
      newField.add(PlayerInfo(
        id: -1 - i, // WICHTIG: Negative IDs von -1 bis -11 für die Platzhalter
        name: positions[i], // Name ist die Position (z.B. "IV")
        position: positions[i], // Position für die Logik
        rating: 0,
        goals: 0,
        assists: 0,
        ownGoals: 0,
        profileImageUrl: null,
      ));
    }

    setState(() {
      _fieldPlayers = newField;
    });
  }
  void _handlePlayerDrop(PlayerInfo fieldSlot, PlayerInfo incomingPlayer) {
    setState(() {
      bool cameFromBench = false;
      int sourceFieldIndex = -1;

      // 1. Herkunft ermitteln
      if (_substitutePlayers.any((p) => p.id == incomingPlayer.id)) {
        cameFromBench = true;
        _substitutePlayers.removeWhere((p) => p.id == incomingPlayer.id);
      } else {
        sourceFieldIndex = _fieldPlayers.indexWhere((p) => p.id == incomingPlayer.id);
        if (sourceFieldIndex == -1) return;
      }

      // 2. Ziel ermitteln
      final int targetIndex = _fieldPlayers.indexWhere((p) => p.id == fieldSlot.id);
      if (targetIndex == -1) return;

      // --- BUGFIX: Self-Drop verhindern ---
      // Wenn der Spieler auf sich selbst fallen gelassen wird -> Nichts tun!
      if (!cameFromBench && sourceFieldIndex == targetIndex) {
        return;
      }

      // 3. Aktion ausführen
      if (cameFromBench) {
        // Bank -> Feld (Einwechseln)
        if (fieldSlot.id > 0) {
          _substitutePlayers.add(fieldSlot);
          _sortBench();
        }
        _fieldPlayers[targetIndex] = incomingPlayer;

      } else {
        // Feld -> Feld (Verschieben)

        // a) Spieler auf neuen Platz
        _fieldPlayers[targetIndex] = incomingPlayer;

        // b) Alten Platz leeren (Placeholder wiederherstellen)
        final List<String> positions = _allFormations[_selectedFormationName] ?? [];
        if (sourceFieldIndex < positions.length) {
          final String roleName = positions[sourceFieldIndex];
          _fieldPlayers[sourceFieldIndex] = PlayerInfo(
              id: -1 - sourceFieldIndex,
              name: roleName,
              position: roleName,
              rating: 0, goals: 0, assists: 0, ownGoals: 0, profileImageUrl: null
          );
        }

        // c) Verdrängten Spieler auf die Bank (falls einer da war)
        if (fieldSlot.id > 0) {
          _substitutePlayers.add(fieldSlot);
          _sortBench();
        }
      }
    });

    _saveLineupToDb();
  }
  // 2. Drop auf die Bank
  void _handleMoveToBench(PlayerInfo player) {
    setState(() {
      // Index auf dem Feld finden
      final int index = _fieldPlayers.indexWhere((p) => p.id == player.id);

      if (index != -1) {
        // Spieler vom Feld entfernen (durch Placeholder ersetzen)
        final List<String> positions = _allFormations[_selectedFormationName] ?? [];
        if (index < positions.length) {
          final String roleName = positions[index];
          _fieldPlayers[index] = PlayerInfo(
              id: -1 - index,
              name: roleName,
              position: roleName,
              rating: 0, goals: 0, assists: 0, ownGoals: 0, profileImageUrl: null
          );
        }

        // Spieler auf die Bank setzen (wenn nicht schon da, was bei Drag von Bank->Bank passieren könnte)
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
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            items: sortedFormationKeys.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text('Formation: $value', style: const TextStyle(fontWeight: FontWeight.bold)),
              );
            }).toList(),
            onChanged: (String? newValue) {
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
        // Team Filter
        Expanded(
          child: Card(
            elevation: 2,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _filterTeam,
                  hint: const Text("Team", style: TextStyle(fontSize: 13)),
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  items: [
                    const DropdownMenuItem(value: null, child: Text("Alle Teams")),
                    ...teams.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (val) => setState(() => _filterTeam = val),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Position Filter
        Expanded(
          child: Card(
            elevation: 2,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _filterPosition,
                  hint: const Text("Pos", style: TextStyle(fontSize: 13)),
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  items: [
                    const DropdownMenuItem(value: null, child: Text("Alle Pos")),
                    ...positions.map((p) => DropdownMenuItem(value: p, child: Text(p))),
                  ],
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
    final primaryColor = Theme.of(context).primaryColor; // Farbe holen

    if (players.isEmpty) {
      return const Center(child: Text("Keine Spieler gefunden"));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final player = players[index];
        return PlayerListItem(
          rank: index + 1,
          profileImageUrl: player.profileImageUrl,
          playerName: player.name,
          teamImageUrl: player.teamImageUrl,
          marketValue: player.marketValue,
          score: player.rating,
          maxScore: player.maxRating,

          // NEUE FELDER ÜBERGEBEN
          position: player.position,
          id: player.id,
          goals: player.goals,
          assists: player.assists,
          ownGoals: player.ownGoals,
          teamColor: primaryColor, // Teamfarbe für den Avatar-Rand

          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: player.id)));
          },
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final primaryColor = Theme.of(context).primaryColor;
    final List<String> currentRequiredPositions = _allFormations[_selectedFormationName] ?? [];

    return Column(
      children: [
        // --- HEADER ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              // Wenn Liste: Zeige Filter (Team, Pos)
              // Wenn Feld: Zeige Formation Dropdown
              Expanded(
                child: _isListView ? _buildFilterBar() : _buildFormationDropdown(),
              ),

              const SizedBox(width: 8),

              // Toggle Button
              Card(
                elevation: 2,
                shadowColor: Colors.black12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: EdgeInsets.zero,
                child: IconButton(
                  icon: Icon(_isListView ? Icons.sports_soccer : Icons.list_alt),
                  color: primaryColor,
                  tooltip: _isListView ? "Spielfeldansicht" : "Listenansicht",
                  onPressed: () {
                    setState(() {
                      _isListView = !_isListView;
                      // Filter beim Wechseln resetten? Optional:
                      // _filterTeam = null; _filterPosition = null;
                    });
                  },
                ),
              ),
            ],
          ),
        ),

        // --- BODY ---
        Expanded(
          child: _isListView
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
          ),
        ),
      ],
    );
  }
}
