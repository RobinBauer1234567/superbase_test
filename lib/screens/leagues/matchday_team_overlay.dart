// lib/screens/leagues/matchday_team_overlay.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/utils/color_helper.dart';

class MatchdayTeamOverlay extends StatefulWidget {
  final int leagueId;
  final String userId;
  final String userName;
  final int round;

  const MatchdayTeamOverlay({
    super.key,
    required this.leagueId,
    required this.userId,
    required this.userName,
    required this.round,
  });

  @override
  State<MatchdayTeamOverlay> createState() => _MatchdayTeamOverlayState();
}

class _MatchdayTeamOverlayState extends State<MatchdayTeamOverlay> {
  bool _isLoading = true;
  bool _isListView = false;

  Map<String, dynamic>? _currentMatchdayData;
  Map<String, List<String>> _allFormations = {};
  String _teamFormation = '4-4-2';
  List<PlayerInfo> _teamFieldPlayers = [];
  List<PlayerInfo> _teamSubstitutePlayers = [];
  List<int> _teamFrozenIds = [];

  @override
  void initState() {
    super.initState();
    _loadTeamData();
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
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

  Future<void> _loadTeamData() async {
    try {
      final dataManagement = context.read<DataManagement>();
      final seasonId = dataManagement.seasonId;

      _allFormations = await dataManagement.supabaseService.fetchFormationsFromDb();

      final teamData = await dataManagement.supabaseService.fetchMatchdayData(
        widget.leagueId,
        seasonId,
        widget.round,
        userId: widget.userId,
      );

      if (mounted) {
        setState(() {
          _currentMatchdayData = teamData;
          _parseTeamDataForPitch(teamData);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Fehler beim Laden des Overlays: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _parseTeamDataForPitch(Map<String, dynamic> matchdayData) {
    final pointsData = matchdayData['points_data'] ?? {};
    final playersData = matchdayData['players'] as List<dynamic>? ?? [];

    _teamFormation = pointsData['formation'] ?? '4-4-2';
    List<String> positions = _allFormations[_teamFormation] ?? List.filled(11, 'POS');

    List<PlayerInfo> field = List.generate(11, (index) {
      if (index == 0) return const PlayerInfo(id: -1, name: "TW", position: "TW", rating: 0, goals: 0, assists: 0, ownGoals: 0);
      return PlayerInfo(id: -1 - index, name: positions[index], position: positions[index], rating: 0, goals: 0, assists: 0, ownGoals: 0);
    });

    List<PlayerInfo> bench = [];
    List<int> frozenIds = [];

    for (var pd in playersData) {
      final spieler = pd['spieler'];
      if (spieler == null) continue;

      final int pId = _toInt(spieler['id']);
      final int fIndex = _toInt(pd['formation_index'], fallback: 99);
      final int rating = _toInt(pd['points'], fallback: 0);

      final bool playerLocked = pd['is_locked'] ?? false;
      if (playerLocked) frozenIds.add(pId);

      final team = spieler['team'];
      final analytics = spieler['spieler_analytics'];
      int mw = 0; int totalSeasonPoints = 0; int matchesPlayed = 0;

      if (analytics is Map) {
        mw = _toInt(analytics['marktwert']);
        matchesPlayed = _toInt(analytics['anzahl_spiele']);
        final stats = analytics['gesamtstatistiken'];
        if (stats is Map) totalSeasonPoints = _toInt(stats['gesamtpunkte']);
      } else if (analytics is List && analytics.isNotEmpty) {
        mw = _toInt(analytics[0]['marktwert']);
        matchesPlayed = _toInt(analytics[0]['anzahl_spiele']);
        final stats = analytics[0]['gesamtstatistiken'];
        if (stats is Map) totalSeasonPoints = _toInt(stats['gesamtpunkte']);
      }

      final playerInfo = PlayerInfo(
        id: pId,
        name: (spieler['name'] ?? 'Unbekannt').toString(),
        position: spieler['position'] ?? 'N/A',
        profileImageUrl: spieler['profilbild_url'],
        rating: rating,
        totalSeasonPoints: totalSeasonPoints,
        matchCount: matchesPlayed,
        goals: 0, assists: 0, ownGoals: 0,
        teamImageUrl: team != null ? team['image_url'] : null,
        marketValue: mw,
        teamName: team != null ? team['name'] : null,
      );

      if (fIndex >= 0 && fIndex <= 10) field[fIndex] = playerInfo;
      else bench.add(playerInfo);
    }

    bench.sort((a, b) => _getPositionOrder(a.position).compareTo(_getPositionOrder(b.position)));

    _teamFieldPlayers = field;
    _teamSubstitutePlayers = bench;
    _teamFrozenIds = frozenIds;
  }
  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    bool hasTeam = _currentMatchdayData != null && _currentMatchdayData!['players'] != null && (_currentMatchdayData!['players'] as List).isNotEmpty;

    final int totalPoints = _currentMatchdayData?['points_data']?['total_points'] ?? 0;
    // NEU: Farbe basierend auf den Punkten berechnen
    final pointsColor = getColorForRating(totalPoints, 2500);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.white,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16.0, right: 8.0, top: 16.0, bottom: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.userName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text("Spieltag ${widget.round}", style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),

                  // --- NEU: Punkte-Pille im Ranking-Design ---
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: pointsColor.withOpacity(0.1),
                      border: Border.all(color: pointsColor.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("PUNKTE", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: pointsColor)),
                        Text('$totalPoints', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: pointsColor)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  Card(
                    elevation: 2,
                    shadowColor: Colors.black12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    margin: EdgeInsets.zero,
                    child: IconButton(
                      icon: Icon(_isListView ? Icons.sports_soccer : Icons.list_alt),
                      color: primaryColor,
                      onPressed: () => setState(() => _isListView = !_isListView),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
            ),
            const Divider(height: 1),
// ... (Rest bleibt gleich)
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : !hasTeam
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sports_soccer, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text('Kein Team aufgestellt.', style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              )
                  : _isListView
                  ? ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: _buildTeamPlayerList(),
              )
                  : MatchFormationDisplay(
                homeFormation: _teamFormation,
                homePlayers: _teamFieldPlayers,
                homeColor: primaryColor,
                substitutes: _teamSubstitutePlayers,
                frozenPlayerIds: _teamFrozenIds,
                requiredPositions: _allFormations[_teamFormation] ?? [],
                currentRound: widget.round,
                displayMode: AvatarDisplayMode.matchday,
                isReadOnly: true,
                onPlayerTap: (playerId, radius) {
                  if (playerId > 0) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: playerId)));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTeamPlayerList() {
    final players = List<Map<String, dynamic>>.from(_currentMatchdayData!['players']);
    players.sort((a, b) => (a['formation_index'] as int).compareTo(b['formation_index'] as int));

    final startingXI = players.where((p) => (p['formation_index'] as int) <= 10).toList();
    final bench = players.where((p) => (p['formation_index'] as int) > 10).toList();

    List<Widget> items = [];
    if (startingXI.isNotEmpty) {
      items.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text("Startelf", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey))));
      items.addAll(startingXI.map((p) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _buildPlayerCard(p))));
    }
    if (bench.isNotEmpty) {
      items.add(const Padding(padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8), child: Text("Bank", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey))));
      items.addAll(bench.map((p) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _buildPlayerCard(p))));
    }
    return items;
  }

  Widget _buildPlayerCard(Map<String, dynamic> playerData) {
    final spieler = playerData['spieler'] ?? {};
    final avatarUrl = spieler['profilbild_url'] ?? '';
    final int playerId = _toInt(spieler['id']);

    // --- NEU: Logik für noch nicht gestartete Spiele ---
    final bool isLocked = playerData['is_locked'] == true;
    final int points = playerData['points'] ?? 0;

    // Wenn gelockt -> normale Farbe. Wenn nicht -> Grau.
    final Color pointsColor = isLocked ? getColorForRating(points, 250) : Colors.grey;
    final String pointsText = isLocked ? '$points' : '-';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: Colors.grey.shade200,
          backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
          child: avatarUrl.isEmpty ? Icon(Icons.person, color: Colors.grey.shade400) : null,
        ),
        title: Text(spieler['name'] ?? 'Unbekannt', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(spieler['position'] ?? 'N/A', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            // Grauer Hintergrund und Rand, wenn das Spiel noch nicht gestartet ist
              color: isLocked ? pointsColor.withOpacity(0.1) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isLocked ? pointsColor.withOpacity(0.3) : Colors.grey.shade300)
          ),
          child: Text(
              pointsText,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isLocked ? pointsColor : Colors.grey.shade600
              )
          ),
        ),
        onTap: () {
          if (playerId > 0) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: playerId)));
          }
        },
      ),
    );
  }
}