// lib/screens/main_screen.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/auth_service.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/screenelements/main_screen/draggable_nav_bar.dart';
import 'package:premier_league/screens/leagues/league_detail_screen.dart';
import 'package:premier_league/screens/premier_league/premier_league_screen.dart';
import 'package:premier_league/screens/leagues/league_hub_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/team_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:premier_league/screens/User/profile_screen.dart';
import 'package:premier_league/screens/leagues/league_settings_screen.dart';
import 'package:premier_league/screens/leagues/tournament_selection_screen.dart';
import 'package:premier_league/screens/screenelements/league_logo.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';
import 'package:premier_league/services/app_data_repository.dart';

enum SearchFilter { players, teams }

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const double _topBarImageRadius = 20;
  static const double _bottomNavLeagueLogoRadius = 14;

  final AppDataRepository _repository = AppDataRepository.instance;

  int _selectedIndex = 0;
  int _premierScreenVersion = 0;
  List<Map<String, dynamic>> _userLeagues = [];
  bool _isLoading = false;
  Map<int, String> _leagueImageUrls = {};
  String? _accountImageUrl;
  Uint8List? _accountImagePreview;
  final Map<int, Uint8List> _leagueImagePreviews = {};

  OverlayEntry? _overflowOverlay;
  bool _isOverflowMenuOpen = false;
  final GlobalKey _moreButtonKey = GlobalKey();

  Timer? _debounce;
  SearchFilter _searchFilter = SearchFilter.players;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _handleNewLeague(int newLeagueId) async {
    if (mounted) setState(() => _isLoading = true);
    _repository.invalidateLeagues();
    await _refreshLeagues(forceRefresh: true);

    final index = _userLeagues.indexWhere((l) => l['id'] == newLeagueId);

    if (index != -1) {
      final league = _userLeagues.removeAt(index);
      _userLeagues.insert(0, league);

      context
          .read<DataManagement>()
          .supabaseService
          .updateUserLeagueOrder(_userLeagues)
          .catchError((e) {
        debugPrint('Fehler beim Speichern der Reihenfolge: $e');
      });

      if (mounted) {
        setState(() {
          _selectedIndex = 1;
          _isLoading = false;
        });
      }
    } else {
      debugPrint('Warnung: Neue Liga ID $newLeagueId nicht in geladener Liste gefunden.');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleOverflowMenu() {
    if (_isOverflowMenuOpen) {
      _closeOverflowMenu();
    } else {
      _openOverflowMenu();
    }
  }

  void _closeOverflowMenu() {
    if (_overflowOverlay != null) {
      _overflowOverlay!.remove();
      _overflowOverlay = null;
    }
    if (mounted) {
      setState(() => _isOverflowMenuOpen = false);
    }
  }

  void _openOverflowMenu() {
    final renderBox =
        _moreButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overflowOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeOverflowMenu,
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned(
            left: offset.dx - 120 + (size.width / 2),
            bottom: MediaQuery.of(context).viewInsets.bottom + 80,
            width: 200,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.list,
                          size: 16,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Weitere Ligen',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_userLeagues.length > 3)
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _userLeagues.length - 3,
                        separatorBuilder: (ctx, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final realIndex = index + 3;
                          final league = _userLeagues[realIndex];

                          return ListTile(
                            dense: true,
                            title: Text(league['name']),
                            trailing:
                                const Icon(Icons.arrow_forward_ios, size: 14),
                            onTap: () => _swapAndSelectLeague(realIndex),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overflowOverlay!);
    setState(() => _isOverflowMenuOpen = true);
  }

  void _swapAndSelectLeague(int selectedLeagueIndexInFullList) {
    _closeOverflowMenu();

    setState(() {
      final league = _userLeagues.removeAt(selectedLeagueIndexInFullList);
      _userLeagues.insert(2, league);
      _selectedIndex = 3;
    });

    context
        .read<DataManagement>()
        .supabaseService
        .updateUserLeagueOrder(_userLeagues);
  }

  Future<void> _loadInitialData({bool forceRefresh = false}) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    // Never block the whole shell. The tournament screen can render while account
    // and league metadata are filled in asynchronously.
    setState(() => _isLoading = true);
    final dataManagement = context.read<DataManagement>();
    dataManagement.startAutoSync();

    try {
      final results = await Future.wait<dynamic>([
        _repository.getUserLeagues(
          loader: dataManagement.supabaseService.getLeaguesForUser,
          forceRefresh: forceRefresh,
        ),
        _repository.getProfileAvatar(forceRefresh: forceRefresh),
      ]);

      if (!mounted) return;
      final leagues = List<Map<String, dynamic>>.from(results[0] as List);
      final avatarUrl = results[1] as String?;

      final Map<int, String> leagueImageUrls = {};
      for (final league in leagues) {
        final imageUrl = league['image_url'] as String?;
        if (imageUrl != null && imageUrl.isNotEmpty) {
          leagueImageUrls[league['id'] as int] = imageUrl;
        }
      }

      setState(() {
        _userLeagues = leagues;
        _accountImageUrl = avatarUrl;
        _leagueImageUrls = leagueImageUrls;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Fehler beim initialen Laden: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshLeagues({
    bool showLoading = false,
    bool forceRefresh = false,
  }) async {
    if (showLoading && mounted) setState(() => _isLoading = true);
    final supabaseService = context.read<DataManagement>().supabaseService;

    try {
      final leagues = await _repository.getUserLeagues(
        loader: supabaseService.getLeaguesForUser,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;

      final Map<int, String> refreshedImageUrls = {};
      for (final league in leagues) {
        final imageUrl = league['image_url'] as String?;
        if (imageUrl != null && imageUrl.isNotEmpty) {
          refreshedImageUrls[league['id'] as int] = imageUrl;
        }
      }

      setState(() {
        _userLeagues = leagues;
        _leagueImageUrls = refreshedImageUrls;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Fehler beim Aktualisieren der Ligen: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _selectedLeagueId {
    if (_selectedIndex <= 0) return 0;
    final leagueListIndex = _selectedIndex - 1;
    if (leagueListIndex >= 0 && leagueListIndex < _userLeagues.length) {
      return _userLeagues[leagueListIndex]['id'] as int;
    }
    return 0;
  }

  Widget _buildImagePreview({
    required IconData fallbackIcon,
    required String? imageUrl,
    required Uint8List? previewBytes,
    double radius = 22,
  }) {
    ImageProvider? provider;
    if (previewBytes != null) {
      provider = MemoryImage(previewBytes);
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      provider = NetworkImage(imageUrl);
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: provider,
      child: provider == null
          ? Icon(fallbackIcon, color: Colors.black54)
          : null,
    );
  }

  void _onReorder(int oldItemIndex, int newItemIndex) {
    final oldLeagueIndex = oldItemIndex - 1;
    final newLeagueIndex = newItemIndex - 1;
    final visibleLeagueCount = min(_userLeagues.length, 3);

    if (oldLeagueIndex < 0 ||
        newLeagueIndex < 0 ||
        oldLeagueIndex >= visibleLeagueCount ||
        newLeagueIndex >= visibleLeagueCount) {
      return;
    }

    setState(() {
      final item = _userLeagues.removeAt(oldLeagueIndex);
      _userLeagues.insert(newLeagueIndex, item);
      if (_selectedIndex == oldItemIndex) {
        _selectedIndex = newItemIndex;
      }
    });

    context
        .read<DataManagement>()
        .supabaseService
        .updateUserLeagueOrder(_userLeagues);
  }

  Future<List<Widget>> _fetchSuggestions(
    String query,
    SearchFilter filter,
  ) async {
    final seasonId = context.read<TournamentViewModel>().currentSeasonId;
    if (seasonId == null || query.trim().isEmpty) return [];

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
          for (final item in response) {
            if (item['spieler'] != null) {
              combinedResults.add({...item['spieler'], 'type': 'player'});
            }
          }
        } else {
          final response = await supabase
              .from('season_teams')
              .select('teams:team(id, name, image_url)')
              .eq('season_id', seasonId)
              .ilike('teams.name', '%$query%');
          for (final item in response) {
            if (item['teams'] != null) {
              combinedResults.add({...item['teams'], 'type': 'team'});
            }
          }
        }
        completer.complete(combinedResults);
      } catch (e) {
        debugPrint('Fehler bei der Suche: $e');
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
          child: imageUrl == null
              ? Icon(isTeam ? Icons.shield : Icons.person)
              : null,
        ),
        title: Text(result['name']),
        onTap: () {
          Navigator.of(context).pop();
          if (isTeam) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TeamScreen(teamId: result['id']),
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlayerScreen(playerId: result['id']),
              ),
            );
          }
        },
      );
    }).toList();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _closeOverflowMenu();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tournamentViewModel = context.watch<TournamentViewModel>();
    final bool isTournamentTab = _selectedIndex == 0;

    const double actionTabWidth = 64.0;
    final List<Widget> screens = [
      PremierLeagueScreen(key: ValueKey('premier-$_premierScreenVersion')),
    ];

    String shortTournamentName = tournamentViewModel.currentTournamentName;
    if (shortTournamentName.length > 10) {
      shortTournamentName = '${shortTournamentName.substring(0, 8)}...';
    }

    final List<NavItem> navItems = [
      NavItem(
        icon: LeagueLogo(
          imageUrl: tournamentViewModel.currentTournamentLogo,
          radius: _bottomNavLeagueLogoRadius,
        ),
        label: shortTournamentName,
      ),
    ];

    final int visibleLeagueCount = min(_userLeagues.length, 3);
    for (int i = 0; i < visibleLeagueCount; i++) {
      final league = _userLeagues[i];
      screens.add(
        LeagueDetailScreen(
          key: ValueKey(league['id']),
          league: league,
        ),
      );

      navItems.add(
        NavItem(
          icon: LeagueLogo(
            imageUrl: _leagueImageUrls[league['id'] as int],
            radius: _bottomNavLeagueLogoRadius,
          ),
          label: league['name'],
          isDraggable: true,
        ),
      );
    }

    if (_userLeagues.length > 3) {
      navItems.add(
        NavItem(
          label: 'Mehr',
          fixedWidth: actionTabWidth,
          isDraggable: false,
          onMoreTap: _toggleOverflowMenu,
          icon: Icon(
            _isOverflowMenuOpen
                ? Icons.keyboard_arrow_down
                : Icons.keyboard_arrow_up,
            key: _moreButtonKey,
          ),
        ),
      );
      screens.add(Container());
    }

    navItems.add(
      NavItem(
        icon: const Icon(Icons.add),
        label: 'Hinzufügen',
        fixedWidth: actionTabWidth,
      ),
    );
    screens.add(const LeagueHubScreen());

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: IconButton(
                icon: LeagueLogo(
                  imageUrl: isTournamentTab
                      ? tournamentViewModel.currentTournamentLogo
                      : _leagueImageUrls[_selectedLeagueId],
                  radius: _topBarImageRadius,
                ),
                onPressed: () {
                  if (isTournamentTab) {
                    Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const TournamentSelectionScreen(),
                      ),
                    ).then((shouldReload) {
                      if (shouldReload == true && mounted) {
                        final seasonId = context
                            .read<TournamentViewModel>()
                            .currentSeasonId;
                        if (seasonId != null) {
                          _repository.invalidateSeason(seasonId);
                        }
                        setState(() {
                          _selectedIndex = 0;
                          _premierScreenVersion++;
                        });
                      }
                    });
                  } else if (_selectedLeagueId != 0) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            LeagueSettingsScreen(leagueId: _selectedLeagueId),
                      ),
                    );
                  }
                },
              ),
            ),
            Expanded(
              child: SearchAnchor.bar(
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
                                    foregroundColor:
                                        _searchFilter == SearchFilter.players
                                            ? Colors.white
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                    backgroundColor:
                                        _searchFilter == SearchFilter.players
                                            ? Theme.of(context).colorScheme.primary
                                            : Colors.grey[300],
                                  ),
                                  onPressed: () => setState(
                                    () => _searchFilter = SearchFilter.players,
                                  ),
                                ),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.shield, size: 18),
                                  label: const Text('Teams'),
                                  style: ElevatedButton.styleFrom(
                                    foregroundColor:
                                        _searchFilter == SearchFilter.teams
                                            ? Colors.white
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                    backgroundColor:
                                        _searchFilter == SearchFilter.teams
                                            ? Theme.of(context).colorScheme.primary
                                            : Colors.grey[300],
                                  ),
                                  onPressed: () => setState(
                                    () => _searchFilter = SearchFilter.teams,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return FutureBuilder<List<Widget>>(
                          future: _fetchSuggestions(
                            controller.text,
                            _searchFilter,
                          ),
                          builder: (context, snapshot) {
                            if (controller.text.isEmpty) {
                              return Column(
                                children: [
                                  buildFilterButtons(),
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Text('Gib einen Namen ein...'),
                                    ),
                                  ),
                                ],
                              );
                            }
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Column(
                                children: [
                                  buildFilterButtons(),
                                  const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                ],
                              );
                            }
                            final suggestions = snapshot.data ?? [];
                            return ListView(
                              shrinkWrap: true,
                              children: [
                                buildFilterButtons(),
                                if (suggestions.isEmpty)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Text('Keine Ergebnisse gefunden.'),
                                    ),
                                  ),
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
            ),
            IconButton(
              tooltip: 'Account',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                ).then((_) {
                  _repository.invalidateProfile();
                  _loadInitialData(forceRefresh: true);
                });
              },
              icon: _buildImagePreview(
                fallbackIcon: Icons.person,
                imageUrl: _accountImageUrl,
                previewBytes: null,
                radius: _topBarImageRadius,
              ),
            ),
          ],
        ),
        bottom: _isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: DraggableNavBar(
        items: navItems,
        currentIndex: _selectedIndex,
        onTap: (index) async {
          if (_userLeagues.length > 3 && index == 4) return;

          if (index == navItems.length - 1) {
            final newLeagueId = await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LeagueHubScreen()),
            );

            if (newLeagueId != null && newLeagueId is int) {
              await _handleNewLeague(newLeagueId);
            } else {
              _repository.invalidateLeagues();
              _refreshLeagues(forceRefresh: true);
            }
          } else {
            setState(() => _selectedIndex = index);
          }
        },
        onReorder: _onReorder,
      ),
    );
  }
}
