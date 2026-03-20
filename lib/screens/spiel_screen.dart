import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/screenelements/match_screen/matchrating_screen.dart';
import 'package:premier_league/utils/color_helper.dart';
import 'package:premier_league/utils/match_time_helper.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

class GameScreen extends StatefulWidget {
  final dynamic spiel;
  const GameScreen({super.key, required this.spiel});
  @override
  State<GameScreen> createState() => _GameScreenState();
}
class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin { // <-- NEU: Mixin hinzugefügt
  List<PlayerInfo> homePlayers = [];
  List<PlayerInfo> homeSubstitutes = [];
  List<PlayerInfo> awayPlayers = [];
  List<PlayerInfo> awaySubstitutes = [];
  bool isLoading = true;
  bool _isInit = true;
  String? _expandedBench;
  double playerAvatarRadiusOnField = 20.0;
  late Map<String, dynamic> currentSpielData;

  late final TabController _tabController; // <-- NEU: TabController

  @override
  void initState() {
    super.initState();
    currentSpielData = Map<String, dynamic>.from(widget.spiel);
    _tabController = TabController(length: 2, vsync: this); // <-- NEU: Initialisierung
  }

  @override
  void dispose() {
    _tabController.dispose(); // <-- NEU: Aufräumen
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      _loadMatchData();
      _isInit = false;
    }
  }

  Color? hexToColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return null;
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      return null;
    }
  }

  Future<void> _loadMatchData() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final dataManagement = Provider.of<DataManagement>(
          context, listen: false);
      final spielId = currentSpielData['id'];
      final status = currentSpielData['status'];
      final seasonId = context.watch<TournamentViewModel>().currentSeasonId ?? 0;
      await dataManagement.updateRatingsForSingleGame(spielId, status, seasonId);

      final updatedSpiel = await Supabase.instance.client
          .from('spiel')
          .select('hometeam_formation, awayteam_formation')
          .eq('id', spielId)
          .single();

      if (mounted) {
        setState(() {
          currentSpielData['hometeam_formation'] =
          updatedSpiel['hometeam_formation'];
          currentSpielData['awayteam_formation'] =
          updatedSpiel['awayteam_formation'];
        });
      }

      await fetchSpieler();
    } catch (e) {
      print("❌ Fehler in _loadMatchData: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> fetchSpieler() async {
    if (!mounted) return;

    List<PlayerInfo> finalHomePlayers = [];
    List<PlayerInfo> finalHomeSubstitutes = [];
    List<PlayerInfo> finalAwayPlayers = [];
    List<PlayerInfo> finalAwaySubstitutes = [];

    try {
      final heimTeamId = currentSpielData['heimteam_id'];
      final auswaertsTeamId = currentSpielData['auswärtsteam_id']; // NEU hinzugefügt
      final spielId = currentSpielData['id'];
      final seasonId = currentSpielData['season_id'];

      int versuch = 0;
      const maxVersuche = 3;

      while (versuch < maxVersuche) {
        versuch++;

        final response = await Supabase.instance.client
            .from('matchrating')
            .select('*, spieler!inner(*, is_active, season_players!inner(team_id, season_id))')
            .eq('spiel_id', spielId)
            .eq('spieler.is_active', true)
            .eq('spieler.season_players.season_id', seasonId)
            .filter('spieler.season_players.team_id', 'in', '($heimTeamId, $auswaertsTeamId)');


        final List<dynamic> ratingsData = response as List<dynamic>;

        List<Map<String, dynamic>> homeRatings = [];
        List<Map<String, dynamic>> awayRatings = [];

        for (var entry in ratingsData) {
          final spieler = entry['spieler'];
          if (spieler == null) continue;

          final seasonPlayersRaw = spieler['season_players'];
          int? playerTeamId;
          if (seasonPlayersRaw is List && seasonPlayersRaw.isNotEmpty) {
            final seasonPlayer = Map<String, dynamic>.from(
                seasonPlayersRaw.first as Map);
            playerTeamId = seasonPlayer['team_id'] as int?;
          }
          if (playerTeamId == null) continue;

          final processedPlayer = {
            'id': spieler['id'],
            'name': spieler['name'],
            'profilbild_url': spieler['profilbild_url'],
            'team_id': playerTeamId,
            'matchrating': entry
          };

          if (playerTeamId == heimTeamId) {
            homeRatings.add(processedPlayer);
          } else {
            awayRatings.add(processedPlayer);
          }
        }

        int sortByIndex(Map<String, dynamic> a, Map<String, dynamic> b) {
          final idxA = a['matchrating']['formationsindex'] ?? 99;
          final idxB = b['matchrating']['formationsindex'] ?? 99;
          return idxA.compareTo(idxB);
        }
        homeRatings.sort(sortByIndex);
        awayRatings.sort(sortByIndex);


        int homeStarters = homeRatings
            .where((p) => (p['matchrating']['formationsindex'] ?? 99) < 11)
            .length;
        int awayStarters = awayRatings
            .where((p) => (p['matchrating']['formationsindex'] ?? 99) < 11)
            .length;

        if (homeStarters >= 10 && awayStarters >= 10) {
          PlayerInfo mapToInfo(Map<String, dynamic> p) {
            final mr = p['matchrating'];
            final stats = mr['statistics'] ?? {};
            return PlayerInfo(
              id: p['id'],
              name: p['name'],
              position: mr['match_position'] ?? 'N/A',
              rating: mr['punkte'],
              profileImageUrl: p['profilbild_url'],
              goals: (stats['goals'] as int?) ?? 0,
              assists: (stats['assists'] as int?) ?? 0,
              ownGoals: (stats['ownGoals'] as int?) ?? 0,
            );
          }

          finalHomePlayers =
              homeRatings.where((p) => p['matchrating']['formationsindex'] < 11)
                  .map(mapToInfo)
                  .toList();
          finalHomeSubstitutes =
              homeRatings.where((p) => p['matchrating']['formationsindex'] >=
                  11).map(mapToInfo).toList();
          finalAwayPlayers =
              awayRatings.where((p) => p['matchrating']['formationsindex'] < 11)
                  .map(mapToInfo)
                  .toList();
          finalAwaySubstitutes =
              awayRatings.where((p) => p['matchrating']['formationsindex'] >=
                  11).map(mapToInfo).toList();

          break;
        }

        if (versuch < maxVersuche) {
          await Future.delayed(Duration(milliseconds: 500 * versuch));
        }
      }

      if (!mounted) return;
      setState(() {
        homePlayers = finalHomePlayers;
        homeSubstitutes = finalHomeSubstitutes;
        awayPlayers = finalAwayPlayers;
        awaySubstitutes = finalAwaySubstitutes;
        isLoading = false;
      });
    } catch (e) {
      print("❌ Fehler: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Widget _buildSubstitutesContent(List<PlayerInfo> substitutes,
      Color teamColor) {
    final String status = (currentSpielData['status'] ?? '')
        .toString()
        .toLowerCase();
    final bool isPlayed = status == 'final';

    return Card(
      margin: EdgeInsets.zero,
      child: ListView.builder(
        itemCount: substitutes.length,
        itemBuilder: (context, index) {
          final player = substitutes[index];
          return SubstitutePlayerRow(
            player: player,
            teamColor: teamColor,
            avatarRadius: playerAvatarRadiusOnField,
            isPlayed: isPlayed,
            onTap: () =>
                Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => PlayerScreen(playerId: player.id)),
            ),
          );
        },
      ),
    );
  }

  DateTime _matchDateTime() {
    try {
      return MatchTimeHelper.parseToLocal(currentSpielData['datum']) ?? DateTime.now();
    } catch (_) {
      return DateTime.now();
    }
  }

  int _headerMinute(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? -1;
  }

  int _headerAddedTime(dynamic value) {
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '') ?? 0;
    return (parsed > 0 && parsed <= 30) ? parsed : 0;
  }

  String _headerIncidentMinute(dynamic incident) {
    final minute = _headerMinute(incident['time']);
    final added = _headerAddedTime(incident['addedTime']);
    if (minute < 0) return "";
    if (added > 0) return "$minute'+$added";
    return "$minute'";
  }

  String _playerNameFromIncident(dynamic incident) {
    final player = incident['player'];
    final fullName =
        (player?['name'] ?? player?['shortName'] ?? 'Unbekannt').toString().trim();
    if (fullName.isEmpty) return 'Unbekannt';
    return fullName;
  }

  String? _playerImageFromIncident(dynamic incident) {
    final dynamic player = incident['player'];
    final int? playerId = player?['id'] as int?;

    final candidateFields = [
      player?['profileImage'],
      player?['profile_image'],
      player?['profilePicture'],
      player?['profile_picture'],
      player?['profilbild_url'],
      player?['image_url'],
    ];

    for (final value in candidateFields) {
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    if (playerId != null) {
      final allPlayers = [
        ...homePlayers,
        ...homeSubstitutes,
        ...awayPlayers,
        ...awaySubstitutes,
      ];
      for (final playerInfo in allPlayers) {
        if (playerInfo.id == playerId) {
          final image = playerInfo.profileImageUrl;
          if (image != null && image.trim().isNotEmpty) {
            return image.trim();
          }
        }
      }
    }

    return null;
  }

  Widget _buildGoalLine({required dynamic incident, required bool isHome, bool showCenterBall = false}) {
    final minute = _headerIncidentMinute(incident);
    final playerName = _playerNameFromIncident(incident);
    final playerImage = _playerImageFromIncident(incident);

    final avatar = CircleAvatar(
      radius: 9,
      backgroundColor: Colors.grey.shade300,
      backgroundImage: playerImage != null ? NetworkImage(playerImage) : null,
      child: playerImage != null
          ? null
          : const Icon(Icons.person, size: 11, color: Colors.black54),
    );

    final text = Flexible(
      child: Text(
        '$playerName $minute',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: isHome ? TextAlign.right : TextAlign.left,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: isHome
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        text,
                        const SizedBox(width: 6),
                        avatar,
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          showCenterBall
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.sports_soccer, size: 14, color: Colors.green.shade700),
                )
              : const SizedBox(width: 22),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: !isHome
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        avatar,
                        const SizedBox(width: 6),
                        text,
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSummary({
    required dynamic heimTeam,
    required dynamic auswaertsTeam,
    required String ergebnis,
    required bool isNotStarted,
    required String status,
    required List<dynamic> incidents,
  }) {
    final datum = _matchDateTime();
    final datumsString = DateFormat('dd.MM.yyyy').format(datum);
    final uhrzeit = DateFormat('HH:mm').format(datum);

    final goalIncidents = incidents.where((incident) => incident['incidentType'] == 'goal').toList()
      ..sort((a, b) {
        final minuteCmp = _headerMinute(a['time']).compareTo(_headerMinute(b['time']));
        if (minuteCmp != 0) return minuteCmp;
        return _headerAddedTime(a['addedTime']).compareTo(_headerAddedTime(b['addedTime']));
      });

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$datumsString • $uhrzeit',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.network(heimTeam['image_url'] ?? '', width: 34, height: 34, errorBuilder: (c, e, s) => const Icon(Icons.shield, size: 28)),
                    const SizedBox(height: 4),
                    Text(
                      heimTeam['name'] ?? '...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isNotStarted ? '- : -' : ergebnis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isNotStarted ? 'Anstoß $uhrzeit' : status,
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.network(auswaertsTeam['image_url'] ?? '', width: 34, height: 34, errorBuilder: (c, e, s) => const Icon(Icons.shield, size: 28)),
                    const SizedBox(height: 4),
                    Text(
                      auswaertsTeam['name'] ?? '...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (goalIncidents.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...goalIncidents.asMap().entries.map((entry) => _buildGoalLine(
              incident: entry.value,
              isHome: entry.value['isHome'] == true,
              showCenterBall: entry.key == 0,
            )),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heimTeam = currentSpielData['heimteam'] ?? {};
    final auswaertsTeam = currentSpielData['auswaertsteam'] ?? {};
    final ergebnis = currentSpielData['ergebnis'] ?? '- : -';
    final status = (currentSpielData['status'] ?? 'unbekannt').toString();

    final isNotStarted = status.toLowerCase() == 'not started' || status.toLowerCase() == 'nicht gestartet' || status.toLowerCase() == 'postponed';

    // Echte Farben aus der Datenbank laden (oder Fallback nutzen)
    final homeColor = hexToColor(currentSpielData['home_color_primary']) ?? Colors.blue.shade700;
    final homeGkColor = hexToColor(currentSpielData['home_goalkeeper_color_primary']) ?? Colors.orange.shade700;
    final awayColor = hexToColor(currentSpielData['away_color_primary']) ?? Colors.red.shade700;
    final awayGkColor = hexToColor(currentSpielData['away_goalkeeper_color_primary']) ?? Colors.orange.shade700;

    final homeFormation = currentSpielData['hometeam_formation'] ?? 'N/A';
    final awayFormation = currentSpielData['awayteam_formation'] ?? 'N/A';
    List<dynamic> incidents = currentSpielData['incidents'] ?? [];

    final goalCount = incidents.where((incident) => incident['incidentType'] == 'goal').length;
    final expandedAppBarHeight =
        (164.0 + (goalCount * 18.0)).clamp(196.0, 328.0).toDouble();

    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar(
                expandedHeight: expandedAppBarHeight,
                pinned: true,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                elevation: 1,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      await _loadMatchData();
                    },
                  ),
                ],
                flexibleSpace: LayoutBuilder(
                  builder: (context, constraints) {
                    final safeAreaTop = MediaQuery.of(context).padding.top;
                    const collapsedBottomHeight =
                        kTextTabBarHeight; // Höhe der TabBar
                    final collapsedHeight = kToolbarHeight + collapsedBottomHeight + safeAreaTop;
                    final expandedHeight = expandedAppBarHeight;

                    var fade = 1.0;
                    if (expandedHeight > collapsedHeight) {
                      fade = (constraints.maxHeight - collapsedHeight) / (expandedHeight - collapsedHeight);
                      fade = fade.clamp(0.0, 1.0);
                    }

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // --- EXPANDED STATE (Spielkopf ohne MatchCard-Layout) ---
                        Positioned(
                          top: safeAreaTop + 18,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            ignoring: fade < 0.5,
                            child: Opacity(
                              opacity: fade,
                              child: _buildHeaderSummary(
                                heimTeam: heimTeam,
                                auswaertsTeam: auswaertsTeam,
                                ergebnis: ergebnis,
                                isNotStarted: isNotStarted,
                                status: status,
                                incidents: incidents,
                              ),
                            ),
                          ),
                        ),
                        // --- COLLAPSED STATE (Nur Wappen & Ergebnis) ---
                        Positioned(
                          top: safeAreaTop,
                          left: 48,
                          right: 48,
                          height: kToolbarHeight,
                          child: IgnorePointer(
                            ignoring: fade > 0.5,
                            child: Opacity(
                              opacity: 1.0 - fade,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.network(heimTeam['image_url'] ?? '', width: 24, height: 24, errorBuilder: (c,e,s) => const Icon(Icons.shield, size: 24), fit: BoxFit.contain),
                                  const SizedBox(width: 12),
                                  Text(isNotStarted ? '- : -' : ergebnis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 12),
                                  Image.network(auswaertsTeam['image_url'] ?? '', width: 24, height: 24, errorBuilder: (c,e,s) => const Icon(Icons.shield, size: 24), fit: BoxFit.contain),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                bottom: TabBar(
                  controller: _tabController,
                  isScrollable: false,
                  tabs: const [
                    Tab(text: "Spielfeld"),
                    Tab(text: "Verlauf"),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          physics: const PageScrollPhysics(),
          children: [
            // TAB 1: DAS SPIELFELD
            Builder(
                builder: (context) {
                  final mediaQuery = MediaQuery.of(context);
                  final screenHeight = mediaQuery.size.height;
                  playerAvatarRadiusOnField = screenHeight / 40;

                  const benchToggleHeight = 48.0;
                  const appBarHeightCollapsed =
                      kToolbarHeight + kTextTabBarHeight;
                  final collapsedViewportHeight = math.max(
                    300.0,
                    screenHeight - mediaQuery.padding.top - appBarHeightCollapsed,
                  );

                  final visibleSubstitutes = _expandedBench == 'home'
                      ? homeSubstitutes
                      : _expandedBench == 'away'
                          ? awaySubstitutes
                          : <PlayerInfo>[];

                  final desiredBenchHeight =
                      visibleSubstitutes.length * (playerAvatarRadiusOnField * 2.1);
                  final maxBenchHeight = math.max(
                    120.0,
                    collapsedViewportHeight * 0.42,
                  );
                  final benchHeight = _expandedBench == null
                      ? 0.0
                      : math.min(maxBenchHeight, desiredBenchHeight);

                  return CustomScrollView(
                      key: const PageStorageKey<String>('gamePitchTab'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: collapsedViewportHeight,
                            child: Stack(
                              children: [
                                Column(
                                  children: [
                                    Expanded(
                                      child: (homePlayers.length >= 11 && awayPlayers.length >= 11)
                                          ? Center(
                                              child: MatchFormationDisplay(
                                                homeFormation: homeFormation,
                                                homePlayers: homePlayers,
                                                homeColor: homeColor,
                                                homeGoalkeeperColor: homeGkColor,
                                                awayFormation: awayFormation,
                                                awayPlayers: awayPlayers,
                                                awayColor: awayColor,
                                                awayGoalkeeperColor: awayGkColor,
                                                onPlayerTap: (playerId, radius) {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          PlayerScreen(playerId: playerId),
                                                    ),
                                                  );
                                                },
                                              ),
                                            )
                                          : const Center(
                                              child: Text(
                                                "Nicht genügend Spielerdaten für die Formationsanzeige.",
                                              ),
                                            ),
                                    ),
                                    SizedBox(
                                      height: benchToggleHeight,
                                      child: Row(
                                        children: [
                                          if (homeSubstitutes.isNotEmpty)
                                            Expanded(
                                              child: GestureDetector(
                                                onTap: () => setState(() =>
                                                    _expandedBench =
                                                        (_expandedBench == 'home')
                                                            ? null
                                                            : 'home'),
                                                child: Card(
                                                  margin: EdgeInsets.zero,
                                                  elevation: 4,
                                                  child: Container(
                                                    alignment: Alignment.center,
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment.center,
                                                      children: [
                                                        const Text(
                                                          "Bank Heim",
                                                          style: TextStyle(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight.bold),
                                                        ),
                                                        Icon(_expandedBench == 'home'
                                                            ? Icons.keyboard_arrow_down
                                                            : Icons.keyboard_arrow_up),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (awaySubstitutes.isNotEmpty)
                                            Expanded(
                                              child: GestureDetector(
                                                onTap: () => setState(() =>
                                                    _expandedBench =
                                                        (_expandedBench == 'away')
                                                            ? null
                                                            : 'away'),
                                                child: Card(
                                                  margin: EdgeInsets.zero,
                                                  elevation: 4,
                                                  child: Container(
                                                    alignment: Alignment.center,
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment.center,
                                                      children: [
                                                        const Text(
                                                          "Bank Auswärts",
                                                          style: TextStyle(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight.bold),
                                                        ),
                                                        Icon(_expandedBench == 'away'
                                                            ? Icons.keyboard_arrow_down
                                                            : Icons.keyboard_arrow_up),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: benchToggleHeight,
                                  child: IgnorePointer(
                                    ignoring: _expandedBench == null,
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      curve: Curves.easeInOut,
                                      height: benchHeight,
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 200),
                                        child: _expandedBench == 'home'
                                            ? _buildSubstitutesContent(homeSubstitutes, homeColor)
                                            : _expandedBench == 'away'
                                                ? _buildSubstitutesContent(awaySubstitutes, awayColor)
                                                : const SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ]
                  );
                }
            ),

            // TAB 2: DER SPIELVERLAUF
            Builder(
                builder: (context) {
                  return CustomScrollView(
                      key: const PageStorageKey<String>('gameIncidentsTab'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
                        SliverPadding(
                          padding: const EdgeInsets.all(8.0),
                          sliver: _buildIncidentsTimeline(incidents),
                        )
                      ]
                  );
                }
            ),
          ],
        ),
      ),
    );
  }
  // Die neue Incidents-Timeline (jetzt als Sliver, passend zum ScrollView)
  Widget _buildIncidentsTimeline(List<dynamic> incidents) {
    if (incidents.isEmpty) {
      return const SliverFillRemaining(
        child: Center(child: Text("Noch keine Ereignisse verfügbar.")),
      );
    }

    int _toMinute(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? -1;
    }

    int _toAddedTime(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    int _sanitizeAddedTime(dynamic value) {
      final parsed = _toAddedTime(value);
      return (parsed > 0 && parsed <= 30) ? parsed : 0;
    }

    String _lastName(dynamic player) {
      final fullName = (player?['name'] ?? player?['shortName'] ?? '').toString().trim();
      if (fullName.isEmpty) return 'Unbekannt';
      final parts = fullName.split(RegExp(r'\s+'));
      return parts.isNotEmpty ? parts.last : fullName;
    }

    PlayerInfo? _findPlayerInfoById(int? playerId) {
      if (playerId == null) return null;
      final allPlayers = [...homePlayers, ...homeSubstitutes, ...awayPlayers, ...awaySubstitutes];
      for (final player in allPlayers) {
        if (player.id == playerId) return player;
      }
      return null;
    }

    Map<String, dynamic>? _findMatchStatsByPlayerId(int? playerId) {
      if (playerId == null) return null;
      final allPlayers = [...homePlayers, ...homeSubstitutes, ...awayPlayers, ...awaySubstitutes];
      for (final player in allPlayers) {
        if (player.id == playerId) {
          return {
            'goals': player.goals,
            'assists': player.assists,
            'ownGoals': player.ownGoals,
          };
        }
      }
      return null;
    }

    void _openRadarOverlayForPlayer(dynamic player) {
      final playerId = player?['id'] as int?;
      if (playerId == null) return;

      final playerInfo = _findPlayerInfoById(playerId);
      final stats = _findMatchStatsByPlayerId(playerId) ?? {};

      if (playerInfo == null || stats.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Spieldaten für diesen Spieler verfügbar.')),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return MatchRatingScreen(
            playerInfo: playerInfo,
            matchStatistics: stats,
          );
        },
      );
    }

    Widget _buildPlayerChip(
      dynamic player, {
      required double nameFontSize,
    }) {
      final playerId = player?['id'] as int?;
      final lastName = _lastName(player);
      final fallback = lastName.isNotEmpty ? lastName.characters.first.toUpperCase() : '?';
      final playerInfo = _findPlayerInfoById(playerId);
      final imageUrl = playerInfo?.profileImageUrl;

      return InkWell(
        borderRadius: BorderRadius.circular(50),
        onTap: playerId == null ? null : () => _openRadarOverlayForPlayer(player),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: Colors.grey.shade300,
                foregroundImage: (imageUrl != null && imageUrl.isNotEmpty)
                    ? NetworkImage(imageUrl)
                    : null,
                child: Text(
                  fallback,
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  lastName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: nameFontSize,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    int _periodEndMinute(String marker) {
      int bestBase = marker == 'HT' ? 45 : 90;
      int bestAdded = 0;

      for (final dynamic incident in incidents) {
        if (incident['incidentType'] == 'period') continue;

        final minute = _toMinute(incident['time']);
        final added = _sanitizeAddedTime(incident['addedTime']);

        final isFirstHalf = marker == 'HT' && minute <= 45;
        final isSecondHalf = marker != 'HT' && minute >= 90;
        if (!isFirstHalf && !isSecondHalf) continue;

        if (minute > bestBase || (minute == bestBase && added > bestAdded)) {
          bestBase = minute;
          bestAdded = added;
        }
      }

      return bestBase * 100 + bestAdded;
    }

    String _formatIncidentTime(dynamic incident) {
      final type = incident['incidentType']?.toString() ?? '';
      if (type == 'period') {
        final marker = incident['text']?.toString() ?? '';
        final endValue = _periodEndMinute(marker);
        final minute = endValue ~/ 100;
        final added = endValue % 100;
        if (added > 0) return "$minute'+$added";
        return "$minute'";
      }

      final minute = _toMinute(incident['time']);
      final addedTime = _sanitizeAddedTime(incident['addedTime']);
      if (minute < 0) return '';
      if (addedTime > 0) return "$minute'+$addedTime";
      return "$minute'";
    }

    int _sortOrderForIncident(dynamic incident) {
      final type = incident['incidentType']?.toString() ?? '';
      if (type == 'period') {
        final marker = incident['text']?.toString() ?? '';
        final endValue = _periodEndMinute(marker);
        // Abpfiff IMMER nach allen Events in der Halbzeit (auch Nachspielzeit)
        return endValue + 99;
      }

      final minute = _toMinute(incident['time']);
      final addedTime = _sanitizeAddedTime(incident['addedTime']);
      return minute * 100 + addedTime;
    }

    final sortedIncidents = List.from(incidents)
      ..sort((a, b) => _sortOrderForIncident(a).compareTo(_sortOrderForIncident(b)));

    final screenWidth = MediaQuery.of(context).size.width;
    final timelineFontSize = (screenWidth * 0.033).clamp(11.5, 13.5).toDouble();

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final incident = sortedIncidents[index];
          final isHome = incident['isHome'];
          final formattedTime = _formatIncidentTime(incident);
          final type = incident['incidentType'] ?? '';
          final incidentClass = incident['incidentClass'] ?? '';

          IconData icon = Icons.info_outline;
          Color iconColor = Colors.black54;
          String neutralText = '';
          bool isNeutral = false;

          if (type == 'goal') {
            icon = Icons.sports_soccer;
            iconColor = Colors.green.shade700;
          } else if (type == 'card') {
            icon = Icons.crop_portrait;
            iconColor = incidentClass == 'yellow' ? Colors.amber : Colors.red;
          } else if (type == 'substitution') {
            icon = Icons.swap_horiz;
            iconColor = Colors.green;
          } else if (type == 'period') {
            icon = Icons.timer;
            iconColor = Colors.black;
            neutralText = incident['text'] == 'HT' ? 'Halbzeit' : 'Spielende';
            isNeutral = true;
          } else {
            return const SizedBox.shrink();
          }

          final Widget eventLine;
          if (type == 'substitution') {
            eventLine = Row(
              children: [
                Expanded(
                  child: Align(
                    alignment:
                        isHome == true ? Alignment.centerLeft : Alignment.centerRight,
                    child: _buildPlayerChip(
                      incident['playerIn'],
                      nameFontSize: timelineFontSize,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 4),
                Expanded(
                  child: Align(
                    alignment:
                        isHome == true ? Alignment.centerLeft : Alignment.centerRight,
                    child: _buildPlayerChip(
                      incident['playerOut'],
                      nameFontSize: timelineFontSize,
                    ),
                  ),
                ),
              ],
            );
          } else {
            eventLine = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isNeutral) ...[
                  _buildPlayerChip(
                    incident['player'],
                    nameFontSize: timelineFontSize,
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(icon, color: iconColor, size: 18),
                if (isNeutral) const SizedBox(width: 6),
                if (isNeutral)
                  Flexible(
                    child: Text(
                      neutralText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: timelineFontSize,
                      ),
                    ),
                  ),
              ],
            );
          }

          if (isNeutral) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formattedTime,
                      style: TextStyle(
                        fontSize: timelineFontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(width: 8),
                    eventLine,
                  ],
                ),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              top: 6,
              bottom: 6,
              left: isHome == true ? 8 : 0,
              right: isHome == false ? 0 : 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: isHome == true ? eventLine : const SizedBox.shrink(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    formattedTime,
                    style: TextStyle(
                      fontSize: timelineFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment:
                        isHome == false ? Alignment.centerRight : Alignment.centerLeft,
                    child: isHome == false ? eventLine : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          );
        },
        childCount: sortedIncidents.length,
      ),
    );
  }


// NEU: Das Widget für den Spielverlauf
}

/// Widget für eine einzelne Spieler-Zeile auf der Ersatzbank
class SubstitutePlayerRow extends StatelessWidget {
  final PlayerInfo player;
  final Color teamColor;
  final double avatarRadius;
  final VoidCallback onTap;
  final bool isPlayed;

  const SubstitutePlayerRow({
    super.key,
    required this.player,
    required this.teamColor,
    required this.avatarRadius,
    required this.onTap,
    this.isPlayed = true,
  });


  Widget _buildEventIcon(IconData icon, Color color, int count) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      child: Icon(icon, color: color, size: avatarRadius * 0.8),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isGoalkeeper = player.position.toUpperCase() == 'TW' || player.position.toUpperCase() == 'G';
    // Dynamische Schriftgrößen
    final double titleFontSize = avatarRadius * 0.8;
    final double ratingFontSize = avatarRadius * 0.8;

    final Color ratingColor = isPlayed ? getColorForRating(player.rating, 250) : Colors.grey;
    final String ratingText = isPlayed ? player.rating.toString() : '-';

    return ListTile(
      dense: true,
      onTap: onTap,
      // Die Höhe der Zeile passt sich jetzt an die Größe des Avatars an
      visualDensity: VisualDensity(vertical: avatarRadius / 50 ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16.0, // Horizontaler Abstand bleibt fest
        vertical: 0, // Vertikaler Abstand ist jetzt dynamisch
      ),
      leading: Container(
        width: avatarRadius * 2,
        height: avatarRadius * 2,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          shape: BoxShape.circle,
          border: Border.all(
            color: isGoalkeeper ? Colors.orange.shade700 : teamColor,
            width: 1,
          ),
          image: player.profileImageUrl != null
              ? DecorationImage(
            image: NetworkImage(player.profileImageUrl!),
            fit: BoxFit.cover, // WICHTIG: Verhindert das Abschneiden
          )
              : null,
        ),
        child: player.profileImageUrl == null
            ? Icon(Icons.person, color: Colors.white, size: avatarRadius * 1.2)
            : null,
      ),
      title: Row(
        children: [
          Text(player.name, style: TextStyle(fontSize: titleFontSize)),
          const SizedBox(width: 8),
          _buildEventIcon(Icons.sports_soccer, Colors.black, player.goals),
          _buildEventIcon(Icons.assistant, Colors.blue, player.assists),
          _buildEventIcon(Icons.sports_soccer, Colors.red, player.ownGoals),
        ],
      ),
      trailing: Container(
        padding: EdgeInsets.symmetric(horizontal: avatarRadius * 0.3, vertical: avatarRadius * 0.1),
        decoration: BoxDecoration(
          color: ratingColor.withOpacity(0.1),
          border: Border.all(color: ratingColor.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          ratingText,
          style: TextStyle(
            color: ratingColor,
            fontSize: ratingFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
