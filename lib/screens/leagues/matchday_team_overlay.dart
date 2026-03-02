// lib/screens/leagues/matchday_team_overlay.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/screens/screenelements/matchday_team_shared.dart';
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
    final parsedData = parseMatchdayTeamData(matchdayData, _allFormations);
    _teamFormation = parsedData.formation;
    _teamFieldPlayers = parsedData.fieldPlayers;
    _teamSubstitutePlayers = parsedData.substitutePlayers;
    _teamFrozenIds = parsedData.frozenPlayerIds;
  }
  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    bool hasTeam = _currentMatchdayData != null && _currentMatchdayData!['players'] != null && (_currentMatchdayData!['players'] as List).isNotEmpty;

    final int totalPoints = _currentMatchdayData?['points_data']?['total_points'] ?? 0;
    final bool isLocked = _currentMatchdayData?['points_data']?['is_locked'] == true;
    final pointsColor = isLocked ? getColorForRating(totalPoints, 2500) : Colors.grey;
    final pointsText = isLocked ? '$totalPoints' : '-';

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
                        Text(pointsText, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: pointsColor)),
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
    return buildTeamPlayerListSections(
      context,
      _currentMatchdayData!,
      onPlayerTap: (playerId) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: playerId)));
      },
    );
  }
}
