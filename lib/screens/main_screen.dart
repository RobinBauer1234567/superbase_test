// lib/screens/main_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/auth_service.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/screenelements/main_screen/draggable_nav_bar.dart';
import 'package:premier_league/screens/leagues/league_detail_screen.dart';
import 'package:premier_league/screens/premier_league/premier_league_screen.dart';
import 'package:premier_league/screens/leagues/league_hub_screen.dart';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/team_screen.dart';

enum SearchFilter { players, teams }

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _userLeagues = [];
  bool _isLoading = true;

  OverlayEntry? _overflowOverlay;
  bool _isOverflowMenuOpen = false;
  final GlobalKey _moreButtonKey = GlobalKey();

  Timer? _debounce;
  SearchFilter _searchFilter = SearchFilter.players;

  // --- KORREKTUR: initState ruft jetzt _loadInitialData auf ---
  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    // Warten auf den ersten Frame, damit der context verfügbar ist
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    setState(() => _isLoading = true);
    final dataManagement = context.read<DataManagement>();

    // Ruft updateData() (für PL-Daten) und getLeaguesForUser() (für Ligen) auf
    await dataManagement.updateData();
    final leagues = await dataManagement.supabaseService.getLeaguesForUser();

    if (mounted) {
      setState(() {
        _userLeagues = leagues;
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshLeagues({bool showLoading = false}) async {
    if (showLoading && mounted) setState(() => _isLoading = true);
    final supabaseService = context.read<DataManagement>().supabaseService;
    final leagues = await supabaseService.getLeaguesForUser();
    if (mounted) {
      setState(() {
        _userLeagues = leagues;
        _isLoading = false;
      });
    }
  }
  // --- ENDE DER KORREKTUR ---

  void _onReorder(int oldItemIndex, int newItemIndex) {
    final oldLeagueIndex = oldItemIndex - 1;
    final newLeagueIndex = newItemIndex - 1;
    final visibleLeagueCount = min(_userLeagues.length, 3);

    if (oldLeagueIndex < 0 || newLeagueIndex < 0 || oldLeagueIndex >= visibleLeagueCount || newLeagueIndex >= visibleLeagueCount) return;

    setState(() {
      final item = _userLeagues.removeAt(oldLeagueIndex);
      _userLeagues.insert(newLeagueIndex, item);
      if (_selectedIndex == oldItemIndex) {
        _selectedIndex = newItemIndex;
      }
    });

    context.read<DataManagement>().supabaseService.updateUserLeagueOrder(_userLeagues);
  }

  // --- Overlay-Methoden (unverändert) ---
  void _toggleOverflowMenu() { /* ... */ }
  void _openOverflowMenu() { /* ... */ }
  void _closeOverflowMenu() { /* ... */ }
  void _swapAndSelectLeague(int selectedLeagueIndexInFullList) { /* ... */ }
  // --- Ende Overlay-Methoden ---

  // --- Suchfunktion (wieder vollständig integriert) ---
  Future<List<Widget>> _fetchSuggestions(String query, SearchFilter filter) async {
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final seasonId = dataManagement.seasonId;
    if (query.trim().isEmpty) return [];

    final completer = Completer<List<Map<String, dynamic>>>();
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final supabase = Supabase.instance.client;
        final List<Map<String, dynamic>> combinedResults = [];

        if (filter == SearchFilter.players) {
          final response = await supabase
              .from('season_players')
              .select('spieler:spieler(id, name, profilbild_url)')
              .eq('season_id', seasonId)
              .ilike('spieler.name', '%$query%');
          for (var item in response) { if (item['spieler'] != null) combinedResults.add({...item['spieler'], 'type': 'player'}); }
        } else {
          final response = await supabase
              .from('season_teams')
              .select('teams:team(id, name, image_url)')
              .eq('season_id', seasonId)
              .ilike('teams.name', '%$query%');
          for (var item in response) { if (item['teams'] != null) combinedResults.add({...item['teams'], 'type': 'team'});}
        }
        completer.complete(combinedResults);
      } catch (e) {
        print("Fehler bei der Suche: $e");
        completer.complete([]);
      }
    });

    final results = await completer.future;
    return results.map((result) {
      final isTeam = result['type'] == 'team';
      final imageUrl = isTeam ? result['image_url'] : result['profilbild_url'];
      return ListTile(
        leading: CircleAvatar(
          backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
          child: imageUrl == null ? Icon(isTeam ? Icons.shield : Icons.person) : null,
        ),
        title: Text(result['name']),
        onTap: () {
          Navigator.of(context).pop(); // Such-Overlay schließen
          if (isTeam) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => TeamScreen(teamId: result['id'])));
          } else {
            Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: result['id'])));
          }
        },
      );
    }).toList();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _closeOverflowMenu(); // Wichtig, um das Overlay zu entfernen
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final authService = context.read<AuthService>();
    final screenWidth = MediaQuery.of(context).size.width;
    final double plTabWidth = screenWidth / 4;
    const double actionTabWidth = 60.0;

    // --- Dynamischer Aufbau (unverändert) ---
    final List<Widget> screens = [ const PremierLeagueScreen() ];
    final List<NavItem> navItems = [
      NavItem(icon: const Icon(Icons.sports_soccer), label: 'PL', fixedWidth: plTabWidth)
    ];
    final int visibleLeagueCount = min(_userLeagues.length, 3);
    for (int i = 0; i < visibleLeagueCount; i++) {
      final league = _userLeagues[i];
      screens.add(LeagueDetailScreen(league: league));
      navItems.add(NavItem(icon: const Icon(Icons.groups), label: league['name'], isDraggable: true));
    }
    if (_userLeagues.length > 3) {
      final isMoreTabSelected = _selectedIndex == (1 + visibleLeagueCount);
      navItems.add(NavItem(
        label: 'Mehr',
        fixedWidth: actionTabWidth,
        isDraggable: false,
        onMoreTap: _toggleOverflowMenu,
        icon: Icon(
          _isOverflowMenuOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
          key: _moreButtonKey,
        ),
      ));
      screens.add(Container());
    }
    navItems.add(NavItem(icon: const Icon(Icons.add), label: 'Hinzufügen', fixedWidth: actionTabWidth));
    screens.add(const LeagueHubScreen());
    // --- Ende Dynamischer Aufbau ---

    return Scaffold(
      appBar: AppBar(
        // --- Suchleiste (wieder integriert) ---
        title: SearchAnchor.bar(
          suggestionsBuilder: (context, controller) {
            return [
              StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
                  Widget buildFilterButtons() {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.person, size: 18),
                            label: const Text('Spieler'),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: _searchFilter == SearchFilter.players ? Colors.white : Theme.of(context).colorScheme.onSurface,
                              backgroundColor: _searchFilter == SearchFilter.players ? Theme.of(context).colorScheme.primary : Colors.grey[300],
                            ),
                            onPressed: () => setState(() => _searchFilter = SearchFilter.players),
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.shield, size: 18),
                            label: const Text('Teams'),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: _searchFilter == SearchFilter.teams ? Colors.white : Theme.of(context).colorScheme.onSurface,
                              backgroundColor: _searchFilter == SearchFilter.teams ? Theme.of(context).colorScheme.primary : Colors.grey[300],
                            ),
                            onPressed: () => setState(() => _searchFilter = SearchFilter.teams),
                          ),
                        ],
                      ),
                    );
                  }

                  return FutureBuilder<List<Widget>>(
                    future: _fetchSuggestions(controller.text, _searchFilter),
                    builder: (context, snapshot) {
                      if (controller.text.isEmpty) {
                        return Column(
                          children: [
                            buildFilterButtons(),
                            const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Gib einen Namen ein..."))),
                          ],
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Column(
                          children: [
                            buildFilterButtons(),
                            const Padding(padding: EdgeInsets.all(16.0), child: Center(child: CircularProgressIndicator())),
                          ],
                        );
                      }
                      final suggestions = snapshot.data ?? [];
                      return ListView(
                        shrinkWrap: true,
                        children: [
                          buildFilterButtons(),
                          if (suggestions.isEmpty)
                            const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Keine Ergebnisse gefunden."))),
                          ...suggestions,
                        ],
                      );
                    },
                  );
                },
              ),
            ];
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Abmelden',
            onPressed: () => authService.signOut(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: DraggableNavBar(
        items: navItems,
        currentIndex: _selectedIndex,
        onTap: (index) {
          if (_userLeagues.length > 3 && index == 4) return;

          if (index == navItems.length - 1) {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LeagueHubScreen())
            ).then((_) => _refreshLeagues());
          } else {
            setState(() { _selectedIndex = index; });
          }
        },
        onReorder: _onReorder,
      ),
    );
  }
}