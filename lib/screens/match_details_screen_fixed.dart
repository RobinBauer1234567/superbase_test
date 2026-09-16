import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/screens/screenelements/match_screen/match_preview_tab.dart';
import 'package:premier_league/utils/color_helper.dart';
import 'package:premier_league/utils/match_time_helper.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GameScreen extends StatefulWidget {
  final dynamic spiel;

  const GameScreen({super.key, required this.spiel});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;

  late Map<String, dynamic> currentSpielData;
  late final TabController _tabController;
  RealtimeChannel? _matchChannel;

  List<PlayerInfo> homePlayers = [];
  List<PlayerInfo> homeSubstitutes = [];
  List<PlayerInfo> awayPlayers = [];
  List<PlayerInfo> awaySubstitutes = [];

  bool isLoading = true;
  bool _didLoad = false;
  double playerAvatarRadiusOnField = 20.0;

  @override
  void initState() {
    super.initState();
    currentSpielData = widget.spiel is Map
        ? Map<String, dynamic>.from(widget.spiel as Map)
        : <String, dynamic>{};
    _tabController = TabController(
      length: 3,
      initialIndex: _isPreMatchStatus(currentSpielData['status']) ? 0 : 2,
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoad) return;
    _didLoad = true;
    _loadMatchData();
  }

  @override
  void dispose() {
    if (_matchChannel != null) {
      _supabase.removeChannel(_matchChannel!);
    }
    _tabController.dispose();
    super.dispose();
  }

  bool _isPreMatchStatus(dynamic value) {
    final status = (value ?? '').toString().toLowerCase();
    return status == 'not started' ||
        status == 'nicht gestartet' ||
        status == 'postponed';
  }

  bool _isFinishedStatus(dynamic value) {
    final status = (value ?? '').toString().toLowerCase();
    return status == 'final' ||
        status == 'beendet' ||
        status == 'finished' ||
        status == 'ended';
  }

  bool _boolValue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  int _intValue(dynamic value, {int fallback = 0}) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Color? _hexToColor(dynamic value) {
    final hexString = value?.toString();
    if (hexString == null || hexString.isEmpty) return null;
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMatchData() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final spielId = currentSpielData['id'];
      final seasonId = _intValue(currentSpielData['season_id'], fallback: -1);
      final status = currentSpielData['status'];
      if (spielId == null || seasonId < 0) {
        throw StateError('Spiel-ID oder Saison-ID fehlt.');
      }

      final season = await _supabase
          .from('season')
          .select('is_active')
          .eq('id', seasonId)
          .maybeSingle();

      if (_boolValue(season?['is_active'])) {
        final dataManagement = Provider.of<DataManagement>(context, listen: false);
        await dataManagement.updateRatingsForSingleGame(
          spielId,
          status,
          seasonId,
        );
      }

      final updatedSpiel = await _supabase
          .from('spiel')
          .select(
            'id, datum, heimteam_id, auswärtsteam_id, ergebnis, status, round, season_id, '
            'incidents, hometeam_formation, awayteam_formation, '
            'home_color_primary, home_color_number, away_color_primary, away_color_number, '
            'home_goalkeeper_color_primary, away_goalkeeper_color_primary',
          )
          .eq('id', spielId)
          .single();

      if (!mounted) return;
      setState(() {
        currentSpielData = {
          ...currentSpielData,
          ...Map<String, dynamic>.from(updatedSpiel),
        };
      });

      await _fetchSpieler();
      _subscribeToMatchChanges();
    } catch (e, stackTrace) {
      debugPrint('Fehler beim Laden der Match-Details: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _subscribeToMatchChanges() {
    final matchId = currentSpielData['id'];
    if (matchId == null) return;

    if (_matchChannel != null) {
      _supabase.removeChannel(_matchChannel!);
    }

    _matchChannel = _supabase
        .channel('match-detail-fixed:$matchId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'spiel',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: matchId,
          ),
          callback: (payload) {
            if (!mounted) return;
            setState(() {
              currentSpielData = {
                ...currentSpielData,
                ...Map<String, dynamic>.from(payload.newRecord),
              };
            });
          },
        )
        .subscribe();
  }

  Future<void> _fetchSpieler() async {
    final heimTeamId = currentSpielData['heimteam_id'];
    final auswaertsTeamId = currentSpielData['auswärtsteam_id'];
    final spielId = currentSpielData['id'];
    final seasonId = currentSpielData['season_id'];

    final finalHomePlayers = <PlayerInfo>[];
    final finalHomeSubstitutes = <PlayerInfo>[];
    final finalAwayPlayers = <PlayerInfo>[];
    final finalAwaySubstitutes = <PlayerInfo>[];

    try {
      final response = await _supabase
          .from('matchrating')
          .select(
            '*, spieler!inner(*, is_active, season_players!inner(team_id, season_id))',
          )
          .eq('spiel_id', spielId)
          .eq('spieler.season_players.season_id', seasonId)
          .filter(
            'spieler.season_players.team_id',
            'in',
            '($heimTeamId, $auswaertsTeamId)',
          );

      final ratingsData = List<dynamic>.from(response as List);
      final homeRatings = <Map<String, dynamic>>[];
      final awayRatings = <Map<String, dynamic>>[];

      for (final entry in ratingsData) {
        if (entry is! Map) continue;
        final row = Map<String, dynamic>.from(entry);
        final spieler = row['spieler'];
        if (spieler is! Map) continue;

        final seasonPlayers = spieler['season_players'];
        if (seasonPlayers is! List || seasonPlayers.isEmpty) continue;
        final seasonPlayer = seasonPlayers.first;
        if (seasonPlayer is! Map) continue;
        final playerTeamId = seasonPlayer['team_id'];
        if (playerTeamId == null) continue;

        final processed = <String, dynamic>{
          'id': spieler['id'],
          'name': spieler['name'],
          'profilbild_url': spieler['profilbild_url'],
          'team_id': playerTeamId,
          'matchrating': row,
        };

        if (playerTeamId == heimTeamId) {
          homeRatings.add(processed);
        } else if (playerTeamId == auswaertsTeamId) {
          awayRatings.add(processed);
        }
      }

      int sortByIndex(Map<String, dynamic> a, Map<String, dynamic> b) {
        final aIndex = _intValue(a['matchrating']?['formationsindex'], fallback: 99);
        final bIndex = _intValue(b['matchrating']?['formationsindex'], fallback: 99);
        return aIndex.compareTo(bIndex);
      }

      homeRatings.sort(sortByIndex);
      awayRatings.sort(sortByIndex);

      PlayerInfo mapToInfo(Map<String, dynamic> row) {
        final rawRating = row['matchrating'];
        final matchrating = rawRating is Map
            ? Map<String, dynamic>.from(rawRating)
            : <String, dynamic>{};
        final rawStats = matchrating['statistics'];
        final stats = rawStats is Map
            ? Map<String, dynamic>.from(rawStats)
            : <String, dynamic>{};

        return PlayerInfo(
          id: _intValue(row['id'], fallback: -1),
          name: row['name']?.toString() ?? 'Unbekannt',
          position: matchrating['match_position']?.toString() ?? 'N/A',
          rating: _intValue(matchrating['punkte']),
          profileImageUrl: row['profilbild_url']?.toString(),
          goals: _intValue(stats['goals']),
          assists: _intValue(stats['assists']),
          ownGoals: _intValue(stats['ownGoals']),
        );
      }

      for (final row in homeRatings) {
        final index = _intValue(row['matchrating']?['formationsindex'], fallback: 99);
        (index < 11 ? finalHomePlayers : finalHomeSubstitutes).add(mapToInfo(row));
      }
      for (final row in awayRatings) {
        final index = _intValue(row['matchrating']?['formationsindex'], fallback: 99);
        (index < 11 ? finalAwayPlayers : finalAwaySubstitutes).add(mapToInfo(row));
      }
    } catch (e, stackTrace) {
      debugPrint('Fehler beim Laden der Spieler: $e');
      debugPrintStack(stackTrace: stackTrace);
    }

    if (!mounted) return;
    setState(() {
      homePlayers = finalHomePlayers;
      homeSubstitutes = finalHomeSubstitutes;
      awayPlayers = finalAwayPlayers;
      awaySubstitutes = finalAwaySubstitutes;
      isLoading = false;
    });
  }

  DateTime _matchDateTime() {
    return MatchTimeHelper.parseToLocal(currentSpielData['datum']) ?? DateTime.now();
  }

  int _minute(dynamic value) => _intValue(value, fallback: -1);

  int _addedTime(dynamic value) {
    final parsed = _intValue(value);
    return parsed > 0 && parsed <= 30 ? parsed : 0;
  }

  String _incidentTime(dynamic incident) {
    if (incident is! Map) return '';
    final minute = _minute(incident['time']);
    final added = _addedTime(incident['addedTime']);
    if (minute < 0) return '';
    return added > 0 ? "$minute'+$added" : "$minute'";
  }

  List<Map<String, dynamic>> get _incidents {
    final raw = currentSpielData['incidents'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _playerName(dynamic player) {
    if (player is! Map) return 'Unbekannt';
    return (player['shortName'] ?? player['name'] ?? 'Unbekannt').toString();
  }

  Widget _teamLogo(dynamic team, double size) {
    final url = team is Map ? team['image_url']?.toString() ?? '' : '';
    if (url.isEmpty) return Icon(Icons.shield_outlined, size: size);
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(Icons.shield_outlined, size: size),
    );
  }

  Widget _buildHeaderSummary() {
    final heimTeam = currentSpielData['heimteam'] ?? const {};
    final auswaertsTeam = currentSpielData['auswaertsteam'] ?? const {};
    final ergebnis = currentSpielData['ergebnis']?.toString() ?? '- : -';
    final status = currentSpielData['status']?.toString() ?? '';
    final isNotStarted = _isPreMatchStatus(status);
    final datum = _matchDateTime();
    final goals = _incidents
        .where((event) => event['incidentType']?.toString() == 'goal')
        .toList()
      ..sort((a, b) {
        final minuteCompare = _minute(a['time']).compareTo(_minute(b['time']));
        return minuteCompare != 0
            ? minuteCompare
            : _addedTime(a['addedTime']).compareTo(_addedTime(b['addedTime']));
      });

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${currentSpielData['round'] ?? '-'} . Spieltag  •  ${DateFormat('dd.MM.yyyy • HH:mm').format(datum)}',
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
                    _teamLogo(heimTeam, 34),
                    const SizedBox(height: 4),
                    Text(
                      heimTeam is Map
                          ? heimTeam['name']?.toString() ?? 'Heim'
                          : 'Heim',
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
                      isNotStarted
                          ? 'Anstoß ${DateFormat('HH:mm').format(datum)}'
                          : status,
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _teamLogo(auswaertsTeam, 34),
                    const SizedBox(height: 4),
                    Text(
                      auswaertsTeam is Map
                          ? auswaertsTeam['name']?.toString() ?? 'Auswärts'
                          : 'Auswärts',
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
          if (goals.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...goals.map((goal) {
              final isHome = _boolValue(goal['isHome']);
              final incidentClass = goal['incidentClass']?.toString() ?? '';
              final suffix = incidentClass == 'ownGoal'
                  ? ' (ET.)'
                  : incidentClass == 'penalty'
                      ? ' (E.)'
                      : '';
              final text =
                  '${_playerName(goal['player'])}$suffix ${_incidentTime(goal)}';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isHome ? text : '',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.sports_soccer, size: 13),
                    ),
                    Expanded(
                      child: Text(
                        isHome ? '' : text,
                        textAlign: TextAlign.left,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heimTeam = currentSpielData['heimteam'] ?? const {};
    final auswaertsTeam = currentSpielData['auswaertsteam'] ?? const {};
    final ergebnis = currentSpielData['ergebnis']?.toString() ?? '- : -';
    final status = currentSpielData['status']?.toString() ?? '';
    final isNotStarted = _isPreMatchStatus(status);

    final goalCount = _incidents
        .where((event) => event['incidentType']?.toString() == 'goal')
        .length;
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
                          tooltip: 'Aktualisieren',
                          onPressed: _loadMatchData,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                      flexibleSpace: LayoutBuilder(
                        builder: (context, constraints) {
                          final safeAreaTop = MediaQuery.of(context).padding.top;
                          const collapsedBottomHeight = kTextTabBarHeight;
                          final collapsedHeight =
                              kToolbarHeight + collapsedBottomHeight + safeAreaTop;

                          var fade = 1.0;
                          if (expandedAppBarHeight > collapsedHeight) {
                            fade = (constraints.maxHeight - collapsedHeight) /
                                (expandedAppBarHeight - collapsedHeight);
                            fade = fade.clamp(0.0, 1.0);
                          }

                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned(
                                top: safeAreaTop + 18,
                                left: 0,
                                right: 0,
                                child: IgnorePointer(
                                  ignoring: fade < 0.5,
                                  child: Opacity(
                                    opacity: fade,
                                    child: _buildHeaderSummary(),
                                  ),
                                ),
                              ),
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
                                        _teamLogo(heimTeam, 24),
                                        const SizedBox(width: 12),
                                        Text(
                                          isNotStarted ? '- : -' : ergebnis,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        _teamLogo(auswaertsTeam, 24),
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
                        tabs: const [
                          Tab(text: 'Vorschau'),
                          Tab(text: 'Spielfeld'),
                          Tab(text: 'Verlauf'),
                        ],
                      ),
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: [
                  Builder(
                    builder: (context) => CustomScrollView(
                      key: const PageStorageKey<String>('matchPreviewTabFixed'),
                      slivers: [
                        SliverOverlapInjector(
                          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                        ),
                        SliverFillRemaining(
                          hasScrollBody: true,
                          child: MatchPreviewTab(match: currentSpielData),
                        ),
                      ],
                    ),
                  ),
                  Builder(builder: _buildPitchTab),
                  Builder(builder: _buildEventsTab),
                ],
              ),
            ),
    );
  }

  Widget _buildPitchTab(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    playerAvatarRadiusOnField = mediaQuery.size.height / 40;

    final homeColor =
        _hexToColor(currentSpielData['home_color_primary']) ?? Colors.blue.shade700;
    final homeGkColor = _hexToColor(currentSpielData['home_goalkeeper_color_primary']) ??
        Colors.orange.shade700;
    final awayColor =
        _hexToColor(currentSpielData['away_color_primary']) ?? Colors.red.shade700;
    final awayGkColor = _hexToColor(currentSpielData['away_goalkeeper_color_primary']) ??
        Colors.orange.shade700;
    final homeFormation =
        currentSpielData['hometeam_formation']?.toString() ?? 'N/A';
    final awayFormation =
        currentSpielData['awayteam_formation']?.toString() ?? 'N/A';

    const appBarHeightCollapsed = kToolbarHeight + kTextTabBarHeight;
    final collapsedViewportHeight = math.max(
      300.0,
      mediaQuery.size.height -
          mediaQuery.padding.top -
          appBarHeightCollapsed,
    );

    return CustomScrollView(
      key: const PageStorageKey<String>('gamePitchTabFixed'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: collapsedViewportHeight,
            child: homePlayers.length >= 11 && awayPlayers.length >= 11
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
                      isReadOnly: true,
                      onPlayerTap: (playerId, radius) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlayerScreen(
                              seasonId:
                                  _intValue(currentSpielData['season_id']),
                              playerId: playerId,
                            ),
                          ),
                        );
                      },
                    ),
                  )
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Die vollständige Aufstellung ist noch nicht verfügbar.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
          ),
        ),
        if (homeSubstitutes.isNotEmpty)
          _buildBenchSliver(
            title: 'Bank Heim',
            players: homeSubstitutes,
            teamColor: homeColor,
          ),
        if (awaySubstitutes.isNotEmpty)
          _buildBenchSliver(
            title: 'Bank Auswärts',
            players: awaySubstitutes,
            teamColor: awayColor,
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  SliverToBoxAdapter _buildBenchSliver({
    required String title,
    required List<PlayerInfo> players,
    required Color teamColor,
  }) {
    final isPlayed = _isFinishedStatus(currentSpielData['status']);
    return SliverToBoxAdapter(
      child: Card(
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ...players.map((player) {
              final isGoalkeeper =
                  player.position.toUpperCase().contains('TW') ||
                      player.position.toUpperCase().contains('GK');
              final ratingColor = isPlayed
                  ? getColorForRating(player.rating, 250)
                  : Colors.grey;
              return ListTile(
                dense: true,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      seasonId: _intValue(currentSpielData['season_id']),
                      playerId: player.id,
                    ),
                  ),
                ),
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isGoalkeeper ? Colors.orange.shade700 : teamColor,
                    ),
                    image: player.profileImageUrl != null &&
                            player.profileImageUrl!.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(player.profileImageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: player.profileImageUrl == null ||
                          player.profileImageUrl!.isEmpty
                      ? const Icon(Icons.person, size: 22)
                      : null,
                ),
                title: Text(
                  player.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  isPlayed ? player.rating.toString() : '-',
                  style: TextStyle(
                    color: ratingColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsTab(BuildContext context) {
    final incidents = List<Map<String, dynamic>>.from(_incidents)
      ..sort((a, b) => _eventSortKey(a).compareTo(_eventSortKey(b)));

    return CustomScrollView(
      key: const PageStorageKey<String>('gameEventsTabFixed'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        if (incidents.isEmpty)
          const SliverFillRemaining(
            child: Center(child: Text('Noch keine Ereignisse verfügbar.')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 28),
            sliver: SliverList.builder(
              itemCount: incidents.length,
              itemBuilder: (context, index) => _buildEventRow(incidents[index]),
            ),
          ),
      ],
    );
  }

  int _eventSortKey(Map<String, dynamic> incident) {
    final type = incident['incidentType']?.toString() ?? '';
    if (type == 'period') {
      final text = incident['text']?.toString() ?? '';
      return text == 'HT' ? 4599 : 9999;
    }
    final minute = math.max(0, _minute(incident['time']));
    return minute * 100 + _addedTime(incident['addedTime']);
  }

  Widget _buildEventRow(Map<String, dynamic> incident) {
    final type = incident['incidentType']?.toString() ?? '';
    final incidentClass = incident['incidentClass']?.toString() ?? '';
    final isHome = _boolValue(incident['isHome']);
    final time = _incidentTime(incident);

    if (type == 'period') {
      final label = incident['text']?.toString() == 'HT' ? 'Halbzeit' : 'Spielende';
      return _neutralEvent(time, Icons.timer_outlined, label);
    }

    if (type == 'varDecision') {
      final label = switch (incidentClass) {
        'goalAwarded' => 'VAR: Tor bestätigt',
        'goalNotAwarded' => 'VAR: Tor aberkannt',
        'penaltyAwarded' => 'VAR: Elfmeter',
        'penaltyNotAwarded' => 'VAR: Kein Elfmeter',
        'cardUpgrade' => 'VAR: Karte angepasst',
        _ => 'VAR-Entscheidung',
      };
      return _neutralEvent(time, Icons.fact_check_outlined, label);
    }

    IconData icon;
    Color color;
    String title;
    String? subtitle;

    switch (type) {
      case 'goal':
        icon = Icons.sports_soccer;
        color = Colors.green.shade700;
        final suffix = incidentClass == 'ownGoal'
            ? ' · Eigentor'
            : incidentClass == 'penalty'
                ? ' · Elfmeter'
                : '';
        title = '${_playerName(incident['player'])}$suffix';
        final assist = incident['assist1'];
        subtitle = assist is Map ? 'Assist: ${_playerName(assist)}' : null;
        break;
      case 'card':
        icon = Icons.crop_portrait;
        color = incidentClass == 'yellow'
            ? Colors.amber.shade700
            : Colors.red.shade700;
        title = _playerName(incident['player']);
        subtitle = incidentClass == 'yellowRed'
            ? 'Gelb-Rote Karte'
            : incidentClass == 'red'
                ? 'Rote Karte'
                : 'Gelbe Karte';
        break;
      case 'substitution':
        icon = Icons.swap_horiz;
        color = Colors.green.shade700;
        title = '${_playerName(incident['playerIn'])} kommt';
        subtitle = '${_playerName(incident['playerOut'])} geht';
        break;
      case 'inGamePenalty':
        icon = Icons.cancel_outlined;
        color = Colors.red.shade700;
        title = _playerName(incident['player']);
        subtitle = 'Elfmeter verschossen';
        break;
      default:
        return const SizedBox.shrink();
    }

    final card = _eventCard(
      icon: icon,
      color: color,
      title: title,
      subtitle: subtitle,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: isHome ? card : const SizedBox.shrink()),
          SizedBox(
            width: 58,
            child: Text(
              time,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(child: !isHome ? card : const SizedBox.shrink()),
        ],
      ),
    );
  }

  Widget _neutralEvent(String time, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(time, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Icon(icon, size: 17),
              const SizedBox(width: 6),
              Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventCard({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
