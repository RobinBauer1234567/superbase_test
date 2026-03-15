import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/utils/color_helper.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'package:premier_league/screens/premier_league/matches_screen.dart';

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

      await dataManagement.updateRatingsForSingleGame(spielId, status);

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
      final spielId = currentSpielData['id'];


      int versuch = 0;
      const maxVersuche = 3;

      while (versuch < maxVersuche) {
        versuch++;

        final seasonId = currentSpielData['season_id'];

        final response = await Supabase.instance.client
            .from('matchrating')
            .select(
            '*, spieler!inner(*, is_active, season_players!inner(team_id, season_id, is_active))')
            .eq('spiel_id', spielId)
            .eq('spieler.is_active', true)
            .eq('spieler.season_players.season_id', seasonId)
            .eq('spieler.season_players.is_active', true);

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

    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar(
                expandedHeight: 200, // Höhe für die MatchCard
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
                    const expandedHeight = 200.0;

                    var fade = 1.0;
                    if (expandedHeight > collapsedHeight) {
                      fade = (constraints.maxHeight - collapsedHeight) / (expandedHeight - collapsedHeight);
                      fade = fade.clamp(0.0, 1.0);
                    }

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // --- EXPANDED STATE (MatchCard) ---
                        Positioned(
                          top: safeAreaTop + 40,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            ignoring: fade < 0.5,
                            child: Opacity(
                              opacity: fade,
                              child: Center(
                                child: MatchCard(
                                  spiel: currentSpielData,
                                  onRefresh: _loadMatchData,
                                ),
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
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 16.0),
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
          physics: const NeverScrollableScrollPhysics(), // Verhindert seitliches Wischen beim Drag&Drop
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
                            child: Column(
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
                                                      PlayerScreen(
                                                          playerId: playerId),
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
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeInOut,
                                  height: benchHeight,
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: _expandedBench == 'home'
                                        ? _buildSubstitutesContent(
                                            homeSubstitutes, homeColor)
                                        : _expandedBench == 'away'
                                            ? _buildSubstitutesContent(
                                                awaySubstitutes, awayColor)
                                            : const SizedBox.shrink(),
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
                                                    Icon(_expandedBench ==
                                                            'home'
                                                        ? Icons
                                                            .keyboard_arrow_down
                                                        : Icons
                                                            .keyboard_arrow_up),
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
                                                    Icon(_expandedBench ==
                                                            'away'
                                                        ? Icons
                                                            .keyboard_arrow_down
                                                        : Icons
                                                            .keyboard_arrow_up),
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

    // Chronologische Reihenfolge (früheste Minute zuerst)
    final sortedIncidents = List.from(incidents)
      ..sort((a, b) {
        final aTime = (a['time'] as num?)?.toInt() ?? 0;
        final bTime = (b['time'] as num?)?.toInt() ?? 0;
        return aTime.compareTo(bTime);
      });

    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          final incident = sortedIncidents[index];
          final isHome = incident['isHome'] ?? true;
          final time = incident['time'] ?? '';
          final type = incident['incidentType'] ?? '';
          final incidentClass = incident['incidentClass'] ?? '';

          IconData icon = Icons.info_outline;
          Color iconColor = Colors.grey;
          String text = '';
          bool isNeutralEvent = false;

          if (type == 'goal') {
            icon = Icons.sports_soccer;
            iconColor = const Color(0xFF2E7D32);
            text = incident['player']?['name'] ?? 'Eigentor/Unbekannt';
          } else if (type == 'card') {
            icon = Icons.style;
            iconColor = incidentClass == 'yellow' ? Colors.amber : Colors.red;
            text = incident['player']?['name'] ?? 'Unbekannt';
          } else if (type == 'substitution') {
            icon = Icons.sync;
            iconColor = Colors.green;
            text = '${incident['playerIn']?['shortName'] ?? '-'} für ${incident['playerOut']?['shortName'] ?? '-'}';
          } else if (type == 'period') {
            icon = Icons.timer;
            iconColor = Colors.black;
            text = incident['text'] == 'HT'
                ? 'Halbzeit'
                : 'Spielende ${incident['homeScore']} : ${incident['awayScore']}';
            isNeutralEvent = true;
          } else {
            return const SizedBox
                .shrink(); // Versteckt unwichtige Events wie Verletzungszeit
          }

          final eventLine = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          );

          Widget sideAlignedEvent = const SizedBox.shrink();

          if (isNeutralEvent) {
            sideAlignedEvent = Center(child: eventLine);
          } else if (isHome) {
            sideAlignedEvent = Align(
              alignment: Alignment.centerLeft,
              child: eventLine,
            );
          } else {
            sideAlignedEvent = Align(
              alignment: Alignment.centerRight,
              child: eventLine,
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$time\'',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                sideAlignedEvent,
                const Divider(height: 14),
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
