import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/screens/screenelements/match_screen/match_preview_tab.dart';
import 'package:premier_league/screens/screenelements/match_screen/matchrating_screen.dart';
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
  double playerAvatarRadiusOnField = 20;

  @override
  void initState() {
    super.initState();
    currentSpielData = Map<String, dynamic>.from(widget.spiel as Map);
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

  Color? _hexToColor(String? hexString) {
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
      final seasonId = currentSpielData['season_id'] as int;
      final status = currentSpielData['status'];

      final season = await _supabase
          .from('season')
          .select('is_active')
          .eq('id', seasonId)
          .single();

      if (season['is_active'] == true) {
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
    } catch (e) {
      debugPrint('Fehler beim Laden der Match-Details: $e');
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
        .channel('match-detail:$matchId')
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
        final row = Map<String, dynamic>.from(entry as Map);
        final spieler = row['spieler'];
        if (spieler is! Map) continue;

        final seasonPlayers = spieler['season_players'];
        if (seasonPlayers is! List || seasonPlayers.isEmpty) continue;
        final seasonPlayer = Map<String, dynamic>.from(seasonPlayers.first as Map);
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
        final aIndex = (a['matchrating']['formationsindex'] as num?)?.toInt() ?? 99;
        final bIndex = (b['matchrating']['formationsindex'] as num?)?.toInt() ?? 99;
        return aIndex.compareTo(bIndex);
      }

      homeRatings.sort(sortByIndex);
      awayRatings.sort(sortByIndex);

      PlayerInfo mapToInfo(Map<String, dynamic> row) {
        final matchrating = Map<String, dynamic>.from(row['matchrating'] as Map);
        final stats = matchrating['statistics'] is Map
            ? Map<String, dynamic>.from(matchrating['statistics'] as Map)
            : <String, dynamic>{};
        return PlayerInfo(
          id: row['id'],
          name: row['name']?.toString() ?? 'Unbekannt',
          position: matchrating['match_position']?.toString() ?? 'N/A',
          rating: matchrating['punkte'],
          profileImageUrl: row['profilbild_url']?.toString(),
          goals: (stats['goals'] as num?)?.toInt() ?? 0,
          assists: (stats['assists'] as num?)?.toInt() ?? 0,
          ownGoals: (stats['ownGoals'] as num?)?.toInt() ?? 0,
        );
      }

      for (final row in homeRatings) {
        final index = (row['matchrating']['formationsindex'] as num?)?.toInt() ?? 99;
        (index < 11 ? finalHomePlayers : finalHomeSubstitutes).add(mapToInfo(row));
      }
      for (final row in awayRatings) {
        final index = (row['matchrating']['formationsindex'] as num?)?.toInt() ?? 99;
        (index < 11 ? finalAwayPlayers : finalAwaySubstitutes).add(mapToInfo(row));
      }
    } catch (e) {
      debugPrint('Fehler beim Laden der Spieler: $e');
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

  int _minute(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? -1;
  }

  int _addedTime(dynamic value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    return parsed > 0 && parsed <= 30 ? parsed : 0;
  }

  String _incidentTime(dynamic incident) {
    final minute = _minute(incident['time']);
    final added = _addedTime(incident['addedTime']);
    if (minute < 0) return '';
    return added > 0 ? "$minute'+$added" : "$minute'";
  }

  List<dynamic> get _incidents {
    final raw = currentSpielData['incidents'];
    return raw is List ? List<dynamic>.from(raw) : <dynamic>[];
  }

  PlayerInfo? _playerInfo(int? playerId) {
    if (playerId == null) return null;
    for (final player in [
      ...homePlayers,
      ...homeSubstitutes,
      ...awayPlayers,
      ...awaySubstitutes,
    ]) {
      if (player.id == playerId) return player;
    }
    return null;
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
    final goals = _incidents.where((event) => event['incidentType'] == 'goal').toList()
      ..sort((a, b) {
        final minuteCompare = _minute(a['time']).compareTo(_minute(b['time']));
        return minuteCompare != 0
            ? minuteCompare
            : _addedTime(a['addedTime']).compareTo(_addedTime(b['addedTime']));
      });

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${currentSpielData['round'] ?? '-'} . Spieltag  •  ${DateFormat('dd.MM.yyyy • HH:mm').format(datum)}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    _teamLogo(heimTeam, 42),
                    const SizedBox(height: 5),
                    Text(
                      heimTeam is Map ? heimTeam['name']?.toString() ?? 'Heim' : 'Heim',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Text(
                      isNotStarted ? '- : -' : ergebnis,
                      style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isNotStarted ? 'Anstoß ${DateFormat('HH:mm').format(datum)}' : status,
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    _teamLogo(auswaertsTeam, 42),
                    const SizedBox(height: 5),
                    Text(
                      auswaertsTeam is Map
                          ? auswaertsTeam['name']?.toString() ?? 'Auswärts'
                          : 'Auswärts',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (goals.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...goals.map((goal) {
              final isHome = goal['isHome'] == true;
              final incidentClass = goal['incidentClass']?.toString() ?? '';
              final suffix = incidentClass == 'ownGoal'
                  ? ' (ET.)'
                  : incidentClass == 'penalty'
                      ? ' (E.)'
                      : '';
              final text = '${_playerName(goal['player'])}$suffix ${_incidentTime(goal)}';
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
    final goals = _incidents.where((event) => event['incidentType'] == 'goal').length;
    final expandedHeight = (178.0 + goals * 18).clamp(210.0, 340.0).toDouble();

    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverOverlapAbsorber(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                  sliver: SliverAppBar(
                    expandedHeight: expandedHeight,
                    pinned: true,
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    actions: [
                      IconButton(
                        tooltip: 'Aktualisieren',
                        onPressed: _loadMatchData,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 38),
                          child: _buildHeaderSummary(),
                        ),
                      ),
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
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  Builder(
                    builder: (context) => CustomScrollView(
                      key: const PageStorageKey<String>('matchPreviewTab'),
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

    final homeColor = _hexToColor(currentSpielData['home_color_primary']) ?? Colors.blue.shade700;
    final homeGkColor =
        _hexToColor(currentSpielData['home_goalkeeper_color_primary']) ?? Colors.orange.shade700;
    final awayColor = _hexToColor(currentSpielData['away_color_primary']) ?? Colors.red.shade700;
    final awayGkColor =
        _hexToColor(currentSpielData['away_goalkeeper_color_primary']) ?? Colors.orange.shade700;
    final homeFormation = currentSpielData['hometeam_formation']?.toString() ?? 'N/A';
    final awayFormation = currentSpielData['awayteam_formation']?.toString() ?? 'N/A';

    final pitchHeight = math.max(430.0, mediaQuery.size.height * 0.62);

    return CustomScrollView(
      key: const PageStorageKey<String>('gamePitchTabV2'),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: pitchHeight,
            child: homePlayers.length >= 11 && awayPlayers.length >= 11
                ? MatchFormationDisplay(
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
                          builder: (_) => PlayerScreen(
                            seasonId: currentSpielData['season_id'] as int,
                            playerId: playerId,
                          ),
                        ),
                      );
                    },
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
          SliverToBoxAdapter(
            child: _BenchSection(
              title: 'Bank Heim',
              substitutes: homeSubstitutes,
              teamColor: homeColor,
              avatarRadius: playerAvatarRadiusOnField,
              isPlayed: _isFinishedStatus(currentSpielData['status']),
              seasonId: currentSpielData['season_id'] as int,
            ),
          ),
        if (awaySubstitutes.isNotEmpty)
          SliverToBoxAdapter(
            child: _BenchSection(
              title: 'Bank Auswärts',
              substitutes: awaySubstitutes,
              teamColor: awayColor,
              avatarRadius: playerAvatarRadiusOnField,
              isPlayed: _isFinishedStatus(currentSpielData['status']),
              seasonId: currentSpielData['season_id'] as int,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildEventsTab(BuildContext context) {
    final incidents = List<dynamic>.from(_incidents)
      ..sort((a, b) => _eventSortKey(a).compareTo(_eventSortKey(b)));

    return CustomScrollView(
      key: const PageStorageKey<String>('gameEventsTabV2'),
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

  int _eventSortKey(dynamic incident) {
    final type = incident['incidentType']?.toString() ?? '';
    if (type == 'period') {
      final text = incident['text']?.toString() ?? '';
      return text == 'HT' ? 4599 : 9999;
    }
    final minute = math.max(0, _minute(incident['time']));
    return minute * 100 + _addedTime(incident['addedTime']);
  }

  Widget _buildEventRow(dynamic incident) {
    final type = incident['incidentType']?.toString() ?? '';
    final incidentClass = incident['incidentClass']?.toString() ?? '';
    final isHome = incident['isHome'] == true;
    final time = _incidentTime(incident);

    if (type == 'period') {
      final label = incident['text'] == 'HT' ? 'Halbzeit' : 'Spielende';
      return _NeutralEvent(time: time, icon: Icons.timer_outlined, text: label);
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
      return _NeutralEvent(time: time, icon: Icons.fact_check_outlined, text: label);
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
        color = incidentClass == 'yellow' ? Colors.amber.shade700 : Colors.red.shade700;
        title = _playerName(incident['player']);
        if (incidentClass == 'yellowRed') {
          subtitle = 'Gelb-Rote Karte';
        } else if (incidentClass == 'red') {
          subtitle = 'Rote Karte';
        } else {
          subtitle = 'Gelbe Karte';
        }
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

    final card = _EventCard(
      icon: icon,
      iconColor: color,
      title: title,
      subtitle: subtitle,
      playerImageUrl: _playerInfo((incident['player'] as Map?)?['id'] as int?)?.profileImageUrl,
      onTap: () => _openEventPlayer(incident['player']),
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
              style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black54),
            ),
          ),
          Expanded(child: !isHome ? card : const SizedBox.shrink()),
        ],
      ),
    );
  }

  void _openEventPlayer(dynamic player) {
    if (player is! Map) return;
    final playerId = player['id'] as int?;
    final info = _playerInfo(playerId);
    if (info == null) return;

    showDialog(
      context: context,
      builder: (_) => MatchRatingScreen(
        playerInfo: info,
        matchStatistics: {
          'goals': info.goals,
          'assists': info.assists,
          'ownGoals': info.ownGoals,
        },
      ),
    );
  }
}

class _NeutralEvent extends StatelessWidget {
  final String time;
  final IconData icon;
  final String text;

  const _NeutralEvent({
    required this.time,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
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
}

class _EventCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? playerImageUrl;
  final VoidCallback? onTap;

  const _EventCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.playerImageUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: Colors.grey.shade200,
              foregroundImage: playerImageUrl != null && playerImageUrl!.isNotEmpty
                  ? NetworkImage(playerImageUrl!)
                  : null,
              child: playerImageUrl == null || playerImageUrl!.isEmpty
                  ? const Icon(Icons.person, size: 15)
                  : null,
            ),
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
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Icon(icon, color: iconColor, size: 19),
          ],
        ),
      ),
    );
  }
}

class _BenchSection extends StatelessWidget {
  final String title;
  final List<PlayerInfo> substitutes;
  final Color teamColor;
  final double avatarRadius;
  final bool isPlayed;
  final int seasonId;

  const _BenchSection({
    required this.title,
    required this.substitutes,
    required this.teamColor,
    required this.avatarRadius,
    required this.isPlayed,
    required this.seasonId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        children: substitutes
            .map(
              (player) => _SubstitutePlayerRow(
                player: player,
                teamColor: teamColor,
                avatarRadius: avatarRadius,
                isPlayed: isPlayed,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      seasonId: seasonId,
                      playerId: player.id,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SubstitutePlayerRow extends StatelessWidget {
  final PlayerInfo player;
  final Color teamColor;
  final double avatarRadius;
  final VoidCallback onTap;
  final bool isPlayed;

  const _SubstitutePlayerRow({
    required this.player,
    required this.teamColor,
    required this.avatarRadius,
    required this.onTap,
    required this.isPlayed,
  });

  Widget _eventIcon(IconData icon, Color color, int count) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Icon(icon, color: color, size: avatarRadius * 0.8),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGoalkeeper = player.position.toUpperCase() == 'TW' ||
        player.position.toUpperCase() == 'G';
    final ratingColor = isPlayed ? getColorForRating(player.rating, 250) : Colors.grey;

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Container(
        width: avatarRadius * 2,
        height: avatarRadius * 2,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          shape: BoxShape.circle,
          border: Border.all(
            color: isGoalkeeper ? Colors.orange.shade700 : teamColor,
          ),
          image: player.profileImageUrl != null
              ? DecorationImage(
                  image: NetworkImage(player.profileImageUrl!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: player.profileImageUrl == null
            ? Icon(Icons.person, size: avatarRadius * 1.1)
            : null,
      ),
      title: Row(
        children: [
          Expanded(child: Text(player.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          _eventIcon(Icons.sports_soccer, Colors.black, player.goals),
          _eventIcon(Icons.assistant, Colors.blue, player.assists),
          _eventIcon(Icons.sports_soccer, Colors.red, player.ownGoals),
        ],
      ),
      trailing: Text(
        isPlayed ? player.rating.toString() : '-',
        style: TextStyle(color: ratingColor, fontWeight: FontWeight.w800),
      ),
    );
  }
}
