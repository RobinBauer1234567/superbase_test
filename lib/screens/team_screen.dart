// lib/screens/team_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/premier_league/matches_screen.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/utils/color_helper.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:premier_league/screens/screenelements/player_list_item.dart';

class TeamScreen extends StatefulWidget {
  final int teamId;

  const TeamScreen({super.key, required this.teamId});

  @override
  _TeamScreenState createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _isLoading = true;
  String _errorMessage = '';

  Map<String, dynamic>? _teamData;
  List<dynamic> _teamMatches = [];
  List<Map<String, dynamic>> _topPlayers = [];
  int anzahlMatches = 0;

  // scrollable_positioned_list controller/listener
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();

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

  Future<void> _fetchTeamData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final seasonId = dataManagement.seasonId;

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
          .select('spieler:spieler(*, matchrating!inner(punkte, spiel!inner(season_id)))')
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
          'profilbild_url': player['profilbild_url'],
          'marktwert': player['marktwert'], // Marktwert aus DB mappen
          'total_punkte': totalPoints,
        });
      }

      topPlayersList.sort((a, b) => b['total_punkte'].compareTo(a['total_punkte']));

      if (mounted) {
        setState(() {
          _teamData = teamResponse;
          _teamMatches = List<Map<String, dynamic>>.from(matchesResponse ?? []);
          _topPlayers = topPlayersList;
          _isLoading = false;
        });

        // Scroll erst nachdem Frame gebaut ist
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToUpcomingMatch();
        });
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

  Future<void> _scrollToUpcomingMatch() async {
    if (_teamMatches.isEmpty) return;

    final now = DateTime.now();
    int? upcomingMatchIndex;

    // Liste ist aufsteigend nach Datum sortiert -> nächstes Spiel ist das erste mit datum > now
    for (int i = 0; i < _teamMatches.length; i++) {
      final match = _teamMatches[i];
      if (match['datum'] != null) {
        try {
          final matchDate = DateTime.parse(match['datum']);
          if (matchDate.isAfter(now)) {
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
      upcomingMatchIndex = _teamMatches.isNotEmpty ? _teamMatches.length - 1 : null;
    }

    if (upcomingMatchIndex == null) return;

    // scrollable_positioned_list scrollTo ist robust — auch wenn Items noch lazy gebaut werden
    try {
      _itemScrollController.scrollTo(
        index: upcomingMatchIndex,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
      print('✅ TeamScreen: gescrollt zu Match Index $upcomingMatchIndex');
    } catch (e) {
      print('⚠️ TeamScreen: scrollTo fehlgeschlagen: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _getColorForRating(int rating) {
    final maxValue = anzahlMatches*250*0.8;
    return getColorForRating(rating, maxValue.round());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_teamData?['name'] ?? 'Team wird geladen...'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(child: Text(_errorMessage))
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Image.network(
              _teamData?['image_url'] ?? '',
              height: 120,
              width: 120,
              errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.shield, size: 120, color: Colors.grey),
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Spiele'),
              Tab(text: 'Kader'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Spiele-Tab: ScrollablePositionedList
                _teamMatches.isEmpty
                    ? const Center(child: Text('Keine Spiele verfügbar'))
                    : ScrollablePositionedList.builder(
                  itemCount: _teamMatches.length,
                  itemScrollController: _itemScrollController,
                  itemPositionsListener: _itemPositionsListener,
                  itemBuilder: (context, index) {
                    final match = _teamMatches[index];
                    return MatchCard(spiel: match, onRefresh: _fetchTeamData);
                  },
                ),
                ListView.builder(
                  itemCount: _topPlayers.length,
                  itemBuilder: (context, index) {
                    final player = _topPlayers[index];
                    return PlayerListItem(
                      rank: index + 1,
                      profileImageUrl: player['profilbild_url'],
                      playerName: player['name'],
                      // teamImageUrl auf null setzen, damit stattdessen der Marktwert angezeigt wird
                      teamImageUrl: null,
                      marketValue: player['marktwert'], // Marktwert übergeben
                      score: player['total_punkte'],
                      maxScore: (anzahlMatches * 250*0.8).toInt(),

                      position: player['position'] ?? 'N/A',
                      id: player['id'],
                      goals: 0, // Stats müssten erst aufwendig geparst werden, 0 reicht für die Optik
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
                ),
// ...
              ],
            ),
          ),
        ],
      ),
    );
  }
}
