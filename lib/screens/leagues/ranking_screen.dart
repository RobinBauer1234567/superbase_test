// lib/screens/leagues/ranking_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/utils/color_helper.dart';

// Enum für den Spieltags-Status
enum MatchdayPhase { before, inProgress, after }

class RankingScreen extends StatefulWidget {
  final int leagueId;

  const RankingScreen({super.key, required this.leagueId});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  // Startwert ist erstmal unwichtig, da er in _initializeData sofort überschrieben wird
  bool _isOverallRanking = true;
  int _selectedRound = 1;
  int _currentRound = 1;
  int _latestActiveRound = 38;

  List<Map<String, dynamic>> _rankingData = [];
  List<Map<String, dynamic>> _allSpieltageData = [];
  bool _isLoading = true;
  int? _currentUserRank;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final service = dataManagement.supabaseService;
    final seasonId = dataManagement.seasonId;

    try {
      _currentRound = await service.getCurrentRound(seasonId);
      _selectedRound = _currentRound;

      // Alle Spieltage laden, um Datum und Max-Runde zu bestimmen
      _allSpieltageData = List<Map<String, dynamic>>.from(
        await service.fetchAllSpieltage(seasonId),
      );
      if (_allSpieltageData.isNotEmpty) {
        int maxRound = 1;
        for (var item in _allSpieltageData) {
          final r = int.tryParse(item['round'].toString()) ?? 1;
          if (r > maxRound) maxRound = r;
        }
        _latestActiveRound = maxRound;
      }

      // --- NEU: Start-Ansicht dynamisch festlegen ---
      final currentPhase = _getMatchdayPhase(_currentRound);
      if (currentPhase == MatchdayPhase.inProgress) {
        // Spieltag läuft -> Zeige als erstes direkt die Live-Spieltags-Punkte
        _isOverallRanking = false;
      } else {
        // Spieltag ist noch nicht gestartet oder schon beendet -> Zeige Gesamt
        _isOverallRanking = true;
      }
      // ----------------------------------------------

      await _loadRanking();
    } catch (e) {
      print('Fehler bei der Initialisierung des Rankings: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  MatchdayPhase _getMatchdayPhase(int round) {
    final roundData = _allSpieltageData.firstWhere(
      (e) => e['round'] == round || e['round'] == round.toString(),
      orElse: () => <String, dynamic>{},
    );

    if (roundData.isEmpty) return MatchdayPhase.after;

    final startStr = roundData['matchday_start']?.toString();
    final endStr = roundData['matchday_end']?.toString();

    if (startStr == null || endStr == null) return MatchdayPhase.inProgress;

    final start = DateTime.tryParse(startStr)?.toUtc();
    final end = DateTime.tryParse(endStr)?.toUtc();

    if (start == null || end == null) return MatchdayPhase.inProgress;

    final now = DateTime.now().toUtc();
    if (now.isBefore(start)) return MatchdayPhase.before;
    if (now.isAfter(end)) return MatchdayPhase.after;
    return MatchdayPhase.inProgress;
  }

  Future<void> _loadRanking() async {
    setState(() => _isLoading = true);
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final service = dataManagement.supabaseService;
    final userId = service.supabase.auth.currentUser?.id;

    try {
      if (_isOverallRanking) {
        _rankingData = await service.fetchOverallRanking(widget.leagueId);
      } else {
        _rankingData = await service.fetchMatchdayRanking(
          widget.leagueId,
          _selectedRound,
        );
      }

      _currentUserRank = null;
      for (int i = 0; i < _rankingData.length; i++) {
        if (_rankingData[i]['user_id']?.toString() == userId) {
          _currentUserRank = i + 1;
          break;
        }
      }
    } catch (e) {
      print('Fehler beim Laden der Rangliste: $e');
      _rankingData = [];
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Widget _buildMatchdaySelector() {
    final primaryColor = Theme.of(context).primaryColor;

    // --- NEU: Prüfen, ob wir gerade auf dem aktuellen Spieltag sind ---
    final bool isCurrentRound = _selectedRound == _currentRound;
    final bool highlightCurrent = !_isOverallRanking && isCurrentRound;

    // 1. Platzierung berechnen (für Gesamt-Ansicht)
    String rankText = "-";
    Color rankColor = Colors.grey;
    if (_currentUserRank != null) {
      rankText = "Platz $_currentUserRank";
      if (_currentUserRank == 1) {
        rankColor = Colors.amber.shade600;
      } else if (_currentUserRank! <= 3) {
        rankColor = Colors.blueGrey;
      } else {
        rankColor = primaryColor;
      }
    }

    // 2. Spieltags-Status berechnen (für Spieltag-Ansicht)
    final phase = _getMatchdayPhase(_selectedRound);
    String phaseText;
    if (phase == MatchdayPhase.before) {
      phaseText = 'nicht gestartet';
    } else if (phase == MatchdayPhase.inProgress) {
      phaseText = 'läuft';
    } else {
      phaseText = 'beendet';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // --- LINKE SEITE: Zwingend 45% des verfügbaren Platzes ---
          Expanded(
            flex: 50, // Definiert das feste Verhältnis
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed:
                        (_isOverallRanking || _selectedRound <= 1)
                            ? null
                            : () {
                              setState(() => _selectedRound--);
                              _loadRanking();
                            },
                    color:
                        (_isOverallRanking || _selectedRound <= 1)
                            ? Colors.grey.shade300
                            : primaryColor,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),

                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isOverallRanking = !_isOverallRanking;
                      });
                      _loadRanking();
                    },
                    child: Container(
                      width: 150,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      // --- NEU: Dynamische Umrandung und Hintergrundfarbe ---
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              highlightCurrent
                                  ? Colors.green.shade300
                                  : Colors.grey.shade300,
                          width: highlightCurrent ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isOverallRanking
                                ? "Gesamt"
                                : "Spieltag $_selectedRound",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.swap_horiz,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed:
                        (_isOverallRanking ||
                                _selectedRound >= _latestActiveRound)
                            ? null
                            : () {
                              setState(() => _selectedRound++);
                              _loadRanking();
                            },
                    color:
                        (_isOverallRanking ||
                                _selectedRound >= _latestActiveRound)
                            ? Colors.grey.shade300
                            : primaryColor,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            flex:
                50, // Gibt der rechten Seite minimal mehr Raum für die Filter/Ansichten
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 115,
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        phaseText,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),

                  Container(
                    width: 120,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: rankColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.emoji_events, size: 16, color: rankColor),
                          const SizedBox(width: 4),
                          Text(
                            rankText,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: rankColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final currentUserId =
        Provider.of<DataManagement>(
          context,
          listen: false,
        ).supabaseService.supabase.auth.currentUser?.id;

    final int maxScore =
        _isOverallRanking ? (_currentRound * 2500).toInt() : 2500;

    return Scaffold(
      backgroundColor:
          Colors.grey.shade100, // Hintergrund an Transfermarkt angepasst
      body: Column(
        children: [
          _buildMatchdaySelector(),

          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _rankingData.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.leaderboard_outlined,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Noch keine Punkte vorhanden.',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ), // Padding wie im Transfermarkt
                      itemCount: _rankingData.length,
                      itemBuilder: (context, index) {
                        final user = _rankingData[index];
                        final bool isCurrentUser =
                            user['user_id']?.toString() == currentUserId;

                        final String displayName =
                            user['username']?.toString() ??
                            user['manager_team_name']?.toString() ??
                            'Manager';
                        final String avatarUrl =
                            user['avatar_url']?.toString() ?? '';
                        final int points =
                            (user['total_points'] as num?)?.toInt() ?? 0;

                        final Color pointsColor = getColorForRating(
                          points,
                          maxScore < 1 ? 1 : maxScore,
                        );

                        // Farbschema für Top 3 analog zum ActivityFeed (Akzentfarben)
                        Color rankAccentColor = Colors.grey;
                        if (index == 0)
                          rankAccentColor = Colors.amber;
                        else if (index == 1)
                          rankAccentColor = Colors.blueGrey;
                        else if (index == 2)
                          rankAccentColor = Colors.brown;

                        return Card(
                          elevation: 1, // Einheitlich zum Transfermarkt
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                // 1. PLATZIERUNG IM FARBIGEN CONTAINER (Analog zum ActivityFeed Icon)
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: rankAccentColor.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: rankAccentColor,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),

                                // 2. PROFILBILD
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.grey.shade200,
                                  backgroundImage:
                                      avatarUrl.isNotEmpty
                                          ? NetworkImage(avatarUrl)
                                          : null,
                                  child:
                                      avatarUrl.isEmpty
                                          ? Icon(
                                            Icons.person,
                                            color: Colors.grey.shade400,
                                            size: 24,
                                          )
                                          : null,
                                ),
                                const SizedBox(width: 16),

                                // 3. NAME & STATUS
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName,
                                        style: TextStyle(
                                          fontWeight:
                                              isCurrentUser
                                                  ? FontWeight.bold
                                                  : FontWeight.w600,
                                          fontSize: 15,
                                          color:
                                              isCurrentUser
                                                  ? primaryColor
                                                  : Colors.black87,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (isCurrentUser)
                                        Text(
                                          "Das bist du",
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                                // 4. PUNKTE-PILLE (Design aus dem Transfermarkt übernommen)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: pointsColor.withOpacity(0.1),
                                    border: Border.all(
                                      color: pointsColor.withOpacity(0.3),
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        "PUNKTE",
                                        style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                          color: pointsColor,
                                        ),
                                      ),
                                      Text(
                                        '$points',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: pointsColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
