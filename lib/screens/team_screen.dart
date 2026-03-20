// lib/screens/team_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/premier_league/matches_screen.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';
import 'package:premier_league/screens/screenelements/player_list_item.dart';
import 'package:premier_league/utils/match_time_helper.dart';

class TeamScreen extends StatefulWidget {
  final int teamId;

  const TeamScreen({super.key, required this.teamId});

  @override
  _TeamScreenState createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final ScrollController _matchesScrollController = ScrollController();

  bool _isLoading = true;
  String _errorMessage = '';

  Map<String, dynamic>? _teamData;
  List<dynamic> _teamMatches = [];
  List<Map<String, dynamic>> _topPlayers = [];
  int anzahlMatches = 0;
  bool _hasInitialAutoScroll = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchTeamData();
  }



  String _normalizePosition(dynamic rawPosition) {
    if (rawPosition == null) return 'N/A';
    if (rawPosition is String) {
      final value = rawPosition.trim();
      return value.isEmpty ? 'N/A' : value;
    }
    if (rawPosition is List) {
      final values = rawPosition
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return values.isEmpty ? 'N/A' : values.join(', ');
    }
    final value = rawPosition.toString().trim();
    return value.isEmpty ? 'N/A' : value;
  }

  int _extractMarketValue(dynamic analyticsRaw, int seasonId) {
    if (analyticsRaw is Map) {
      return (analyticsRaw['marktwert'] as num?)?.toInt() ?? 0;
    }
    if (analyticsRaw is List) {
      final selected = analyticsRaw.cast<Map<String, dynamic>>().firstWhere(
        (a) => a['season_id'] == seasonId,
        orElse: () => <String, dynamic>{},
      );
      return (selected['marktwert'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  Future<void> _fetchTeamData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final seasonId = context.read<TournamentViewModel>().currentSeasonId;
    if (seasonId == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Keine Saison ausgewählt.';
        });
      }
      return;
    }

    try {
      final teamResponse = await Supabase.instance.client
          .from('team')
          .select()
          .eq('id', widget.teamId)
          .single();

      // Spiele: aufsteigend nach Datum (nächste Spiele weiter unten)
      final matchesResponse = await Supabase.instance.client
          .from('spiel')
          .select('*, heimteam:team!spiel_heimteam_id_fkey(id, name, image_url), auswaertsteam:team!spiel_auswärtsteam_id_fkey(id, name, image_url)')
          .eq('season_id', seasonId)
          .or('heimteam_id.eq.${widget.teamId},auswärtsteam_id.eq.${widget.teamId}')
          .order('datum', ascending: true);

      final matches = await Supabase.instance.client
          .from('spiel')
          .select('*, heimteam:team!spiel_heimteam_id_fkey(id, name, image_url), auswaertsteam:team!spiel_auswärtsteam_id_fkey(id, name, image_url)')
          .eq('season_id', seasonId)
      .neq('status', 'nicht gestartet')
          .or('heimteam_id.eq.${widget.teamId},auswärtsteam_id.eq.${widget.teamId}');
      anzahlMatches = matches.length;


      final playersResponse = await Supabase.instance.client
          .from('season_players')
          .select('spieler:spieler(*, spieler_analytics(marktwert, season_id), matchrating!inner(punkte, spiel!inner(season_id)))')
          .eq('season_id', seasonId)
          .eq('team_id', widget.teamId)
          .eq('spieler.matchrating.spiel.season_id', seasonId);

      List<Map<String, dynamic>> topPlayersList = [];
      for (var playerEntry in playersResponse) {
        final player = playerEntry['spieler'];
        if (player == null) continue;

        int totalPoints = 0;
        if (player['matchrating'] is Iterable) {
          for (var rating in player['matchrating']) {
            totalPoints += (rating['punkte'] as int?) ?? 0;
          }
        }
        topPlayersList.add({
          'id': player['id'],
          'name': player['name'],
          'position': _normalizePosition(player['position']),
          'profilbild_url': player['profilbild_url'],
          'marktwert': _extractMarketValue(player['spieler_analytics'], seasonId), // Marktwert aus DB mappen
          'total_punkte': totalPoints,
        });
      }

      topPlayersList.sort((a, b) => b['total_punkte'].compareTo(a['total_punkte']));

      if (mounted) {
        setState(() {
          _teamData = teamResponse;
          _teamMatches = List<Map<String, dynamic>>.from(matchesResponse);
          _topPlayers = topPlayersList;
          _isLoading = false;
        });

        _maybeScrollToUpcomingMatch();
      }
    } catch (e) {
      print("Fehler beim Laden der Teamdaten: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Daten konnten nicht geladen werden.";
        });
      }
    }
  }

  void _maybeScrollToUpcomingMatch() {
    if (_hasInitialAutoScroll) return;
    _hasInitialAutoScroll = true;
    _scrollToUpcomingMatch();
  }

  Future<void> _scrollToUpcomingMatch() async {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_teamMatches.isEmpty || !_matchesScrollController.hasClients) return;

      final now = DateTime.now().toUtc();
      int? upcomingMatchIndex;

    // Liste ist aufsteigend nach Datum sortiert -> nächstes Spiel ist das erste mit datum > now
      for (int i = 0; i < _teamMatches.length; i++) {
        final match = _teamMatches[i];
        if (match['datum'] != null) {
          try {
            final matchDate = MatchTimeHelper.parseToUtc(match['datum']);
            if (matchDate != null && matchDate.isAfter(now)) {
              upcomingMatchIndex = i;
              break;
            }
          } catch (_) {
            // parsing fail -> skip
          }
        }
      }

      if (upcomingMatchIndex == null) {
        // kein zukünftiges Spiel gefunden -> evtl. letztes Spiel anzeigen
        upcomingMatchIndex = _teamMatches.isNotEmpty ? _teamMatches.length - 1 : 0;
      }

      _matchesScrollController.animateTo(
        upcomingMatchIndex * 90.0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _matchesScrollController.dispose();
    super.dispose();
  }

  int get _totalSquadMarketValue => _topPlayers.fold<int>(
        0,
        (sum, player) => sum + ((player['marktwert'] as int?) ?? 0),
      );

  int get _totalSquadRating => _topPlayers.fold<int>(
        0,
        (sum, player) => sum + ((player['total_punkte'] as int?) ?? 0),
      );

  Widget _buildCollapsedTeamBar() {
    final maxTotalScore = (anzahlMatches * 250 * 0.8).round();
    final teamScore = _totalSquadRating;
    return SizedBox(
      height: kToolbarHeight,
      child: PlayerListItem(
        profileImageUrl: _teamData?['image_url'],
        playerName: _teamData?['name'] ?? '',
        marketValue: _totalSquadMarketValue,
        score: teamScore,
        maxScore: maxTotalScore > 0 ? maxTotalScore : 1,
        position: '',
        isPlayed: anzahlMatches > 0,
        showTeamImageTrailing: false,
        showMarketValueTrailing: false,
        teamColor: Colors.blueGrey,
        onTap: () {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(child: Text(_errorMessage))
          : NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                elevation: 1,
                flexibleSpace: LayoutBuilder(
                  builder: (context, constraints) {
                    final safeAreaTop = MediaQuery.of(context).padding.top;
                    final collapsedHeight = kToolbarHeight + 48.0 + safeAreaTop;
                    const expandedHeight = 220.0;
                    var fade = 1.0;
                    if (expandedHeight > collapsedHeight) {
                      fade = (constraints.maxHeight - collapsedHeight) / (expandedHeight - collapsedHeight);
                      fade = fade.clamp(0.0, 1.0);
                    }

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned(
                          top: safeAreaTop + 16,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            ignoring: fade < 0.5,
                            child: Opacity(
                              opacity: fade,
                              child: Column(
                                children: [
                                  Image.network(
                                    _teamData?['image_url'] ?? '',
                                    height: 100,
                                    width: 100,
                                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.shield, size: 100, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _teamData?['name'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: safeAreaTop,
                          left: 72,
                          right: 16,
                          height: kToolbarHeight,
                          child: IgnorePointer(
                            ignoring: fade > 0.5,
                            child: Opacity(
                              opacity: 1 - fade,
                              child: _buildCollapsedTeamBar(),
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
                    Tab(text: 'Spiele'),
                    Tab(text: 'Kader'),
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
              builder: (context) {
                return CustomScrollView(
                  key: const PageStorageKey<String>('teamMatchesTab'),
                  controller: _matchesScrollController,
                  slivers: [
                    SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
                    if (_teamMatches.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: Text('Keine Spiele verfügbar')),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final match = _teamMatches[index];
                            return MatchCard(spiel: match, onRefresh: _fetchTeamData);
                          },
                          childCount: _teamMatches.length,
                        ),
                      ),
                  ],
                );
              },
            ),
            Builder(
              builder: (context) {
                return CustomScrollView(
                  key: const PageStorageKey<String>('teamSquadTab'),
                  slivers: [
                    SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final player = _topPlayers[index];
                          return PlayerListItem(
                            rank: index + 1,
                            profileImageUrl: player['profilbild_url'],
                            playerName: player['name'],
                            teamImageUrl: null,
                            showTeamImageTrailing: false,
                            marketValue: player['marktwert'],
                            score: player['total_punkte'],
                            maxScore: (anzahlMatches * 250 * 0.8).toInt(),
                            position: _normalizePosition(player['position']),
                            id: player['id'],
                            goals: 0,
                            assists: 0,
                            ownGoals: 0,
                            teamColor: Colors.blue,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PlayerScreen(playerId: player['id']),
                                ),
                              );
                            },
                          );
                        },
                        childCount: _topPlayers.length,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
