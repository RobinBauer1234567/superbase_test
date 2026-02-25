// lib/screens/main_screen.dart
import 'dart:async';
import 'dart:typed_data';
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
import 'package:image_picker/image_picker.dart';

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

  // --- KORREKTUR: initState ruft jetzt _loadInitialData auf ---
  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _handleNewLeague(int newLeagueId) async {
    setState(() => _isLoading = true);

    // 1. Daten neu laden
    await _refreshLeagues();


    // 2. Die neue Liga suchen
    final index = _userLeagues.indexWhere((l) => l['id'] == newLeagueId);

    if (index != -1) {
      // 3. Lokale Liste manipulieren: Liga entfernen und an den Anfang setzen
      final league = _userLeagues.removeAt(index);
      _userLeagues.insert(0, league);

      // 4. Neue Reihenfolge in der DB speichern
      // Wir machen das im Hintergrund (kein await nötig für UI Update)
      context.read<DataManagement>().supabaseService.updateUserLeagueOrder(_userLeagues).catchError((e) {
        print("Fehler beim Speichern der Reihenfolge: $e");
      });

      // 5. UI aktualisieren und Tab wechseln
      if (mounted) {
        setState(() {
          _selectedIndex = 1; // Tab 1 ist die erste Liga (Tab 0 ist PL)
          _isLoading = false;
        });
      }
    } else {
      // Fallback: Wenn Liga nicht gefunden wurde (sollte nicht passieren)
      print("Warnung: Neue Liga ID $newLeagueId nicht in geladener Liste gefunden.");
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
      setState(() {
        _isOverflowMenuOpen = false;
      });
    }
  }

  void _openOverflowMenu() {
    // 1. Position des Buttons finden
    final renderBox = _moreButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    // 2. Overlay erstellen
    _overflowOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Klick in den Hintergrund schließt das Menü
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeOverflowMenu,
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
          ),
          // Das eigentliche Menü
          Positioned(
            left: offset.dx - 120 + (size.width / 2), // Zentriert über dem Button ausrichten
            bottom: MediaQuery.of(context).viewInsets.bottom + 80, // Über der NavBar
            width: 200,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.list, size: 16, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          "Weitere Ligen",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Liste der versteckten Ligen (Index 3 bis Ende)
                  if (_userLeagues.length > 3)
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _userLeagues.length - 3,
                        separatorBuilder: (ctx, i) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          // Der Index in der _userLeagues Liste ist um 3 verschoben
                          final realIndex = index + 3;
                          final league = _userLeagues[realIndex];

                          return ListTile(
                            dense: true,
                            title: Text(league['name']),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
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

    // 3. Overlay anzeigen
    Overlay.of(context).insert(_overflowOverlay!);
    setState(() {
      _isOverflowMenuOpen = true;
    });
  }

  void _swapAndSelectLeague(int selectedLeagueIndexInFullList) {
    _closeOverflowMenu();

    setState(() {
      // 1. Die ausgewählte Liga aus der Liste nehmen
      final league = _userLeagues.removeAt(selectedLeagueIndexInFullList);

      // 2. Liga an die erste Stelle setzen (damit sie sichtbar wird)
      _userLeagues.insert(2, league);

      // 3. Den Tab wechseln (Index 1 = Erste User-Liga, da Index 0 = PL ist)
      _selectedIndex = 3;
    });

    // 4. Neue Reihenfolge speichern
    context.read<DataManagement>().supabaseService.updateUserLeagueOrder(_userLeagues);
  }
  Future<void> _loadInitialData() async {
    // Warten auf den ersten Frame, damit der context verfügbar ist
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    setState(() => _isLoading = true);
    final dataManagement = context.read<DataManagement>();
    dataManagement.startAutoSync();
    final leagues = await dataManagement.supabaseService.getLeaguesForUser();
    final profileData = await Supabase.instance.client
        .from('profiles')
        .select('avatar_url')
        .eq('user_id', Supabase.instance.client.auth.currentUser!.id)
        .maybeSingle();

    final Map<int, String> leagueImageUrls = {};
    for (final league in leagues) {
      final dynamic settings = league['settings'];
      if (settings is Map && settings['logo_url'] is String) {
        leagueImageUrls[league['id'] as int] = settings['logo_url'] as String;
      }
    }

    if (mounted) {
      setState(() {
        _userLeagues = leagues;
        _accountImageUrl = profileData?['avatar_url'] as String?;
        _leagueImageUrls = leagueImageUrls;
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
        final Map<int, String> refreshedImageUrls = {};
        for (final league in leagues) {
          final dynamic settings = league['settings'];
          if (settings is Map && settings['logo_url'] is String) {
            refreshedImageUrls[league['id'] as int] = settings['logo_url'] as String;
          }
        }
        _leagueImageUrls = refreshedImageUrls;
        _isLoading = false;
      });
    }
  }

  int? get _selectedLeagueId {
    if (_selectedIndex <= 0) return null;
    final leagueListIndex = _selectedIndex - 1;
    if (leagueListIndex >= 0 && leagueListIndex < _userLeagues.length) {
      return _userLeagues[leagueListIndex]['id'] as int;
    }
    return null;
  }

  String get _selectedLeagueName {
    if (_selectedIndex == 0) return 'Premier League';
    final leagueListIndex = _selectedIndex - 1;
    if (leagueListIndex >= 0 && leagueListIndex < _userLeagues.length) {
      return _userLeagues[leagueListIndex]['name'] as String;
    }
    return 'Liga';
  }

  Future<void> _pickAccountImage() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    setState(() {
      _accountImagePreview = bytes;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final path = 'avatars/$userId.jpg';
      await Supabase.instance.client.storage.from('spielerbilder').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );
      final publicUrl = Supabase.instance.client.storage.from('spielerbilder').getPublicUrl(path);
      await Supabase.instance.client.from('profiles').update({'avatar_url': publicUrl}).eq('user_id', userId);

      if (mounted) {
        setState(() {
          _accountImageUrl = publicUrl;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konnte Account-Bild nicht speichern: $e')),
      );
    }
  }

  Future<void> _pickLeagueImage() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final leagueId = _selectedLeagueId;
    if (leagueId == null) {
      setState(() {
        _leagueImagePreviews[-1] = bytes;
      });
      return;
    }

    setState(() {
      _leagueImagePreviews[leagueId] = bytes;
    });

    try {
      final path = 'league_badges/$leagueId.jpg';
      await Supabase.instance.client.storage.from('wappen').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );
      final publicUrl = Supabase.instance.client.storage.from('wappen').getPublicUrl(path);

      final selectedLeague = _userLeagues.firstWhere((league) => league['id'] == leagueId);
      final settings = (selectedLeague['settings'] is Map<String, dynamic>)
          ? Map<String, dynamic>.from(selectedLeague['settings'])
          : <String, dynamic>{};
      settings['logo_url'] = publicUrl;

      await Supabase.instance.client.from('leagues').update({'settings': settings}).eq('id', leagueId);

      if (mounted) {
        setState(() {
          _leagueImageUrls[leagueId] = publicUrl;
          selectedLeague['settings'] = settings;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konnte Liga-Bild nicht speichern: $e')),
      );
    }
  }

  void _openAccountSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final authService = this.context.read<AuthService>();
        final user = Supabase.instance.client.auth.currentUser;

        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildImagePreview(
                fallbackIcon: Icons.person,
                imageUrl: _accountImageUrl,
                previewBytes: _accountImagePreview,
                radius: 42,
              ),
              const SizedBox(height: 12),
              Text(user?.email ?? 'Kein Account', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Profilbild ändern oder direkt abmelden.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      await _pickAccountImage();
                      if (mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.image),
                    label: const Text('Bild importieren'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      authService.signOut();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Abmelden'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _openLeagueSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final leagueId = _selectedLeagueId;
        final preview = leagueId == null ? _leagueImagePreviews[-1] : _leagueImagePreviews[leagueId];
        final imageUrl = leagueId == null ? null : _leagueImageUrls[leagueId];

        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildImagePreview(
                fallbackIcon: Icons.shield,
                imageUrl: imageUrl,
                previewBytes: preview,
                radius: 42,
              ),
              const SizedBox(height: 12),
              Text(
                _selectedLeagueName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                leagueId == null
                    ? 'Dummy im Premier-League-Tab – Bild ist lokal auf diesem Gerät.'
                    : 'Liga-ID: $leagueId • Badge wird in Supabase gespeichert.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await _pickLeagueImage();
                  if (mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.image_outlined),
                label: Text(leagueId == null ? 'Dummy-Bild importieren' : 'Liga-Bild importieren'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImagePreview({
    required IconData fallbackIcon,
    required String? imageUrl,
    required Uint8List? previewBytes,
    double radius = 18,
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
      child: provider == null ? Icon(fallbackIcon, color: Colors.black54) : null,
    );
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
      screens.add(LeagueDetailScreen(
          key: ValueKey(league['id']), // <--- WICHTIG: Das zwingt zum Neuladen
          league: league
      ));

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
        titleSpacing: 0,
        title: Row(
          children: [
            IconButton(
              tooltip: 'Liga',
              onPressed: _openLeagueSheet,
              icon: _buildImagePreview(
                fallbackIcon: Icons.shield,
                imageUrl: _selectedLeagueId != null ? _leagueImageUrls[_selectedLeagueId!] : null,
                previewBytes: _selectedLeagueId != null ? _leagueImagePreviews[_selectedLeagueId!] : _leagueImagePreviews[-1],
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
            ),
            IconButton(
              tooltip: 'Account',
              onPressed: _openAccountSheet,
              icon: _buildImagePreview(
                fallbackIcon: Icons.person,
                imageUrl: _accountImageUrl,
                previewBytes: _accountImagePreview,
              ),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: DraggableNavBar(
        items: navItems,
        currentIndex: _selectedIndex,
        onTap: (index) async { // HIER async hinzufügen
          if (_userLeagues.length > 3 && index == 4) return;

          if (index == navItems.length - 1) {
            // "Hinzufügen" wurde geklickt -> LeagueHubScreen öffnen
            // Wir warten auf das Ergebnis (die ID der neuen Liga)
            final newLeagueId = await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LeagueHubScreen())
            );

            // Wenn wir eine ID zurückbekommen, rufen wir unsere Logik auf
            if (newLeagueId != null && newLeagueId is int) {
              await _handleNewLeague(newLeagueId);
            } else {
              // Wenn abgebrochen wurde, nur refreshen um sicher zu gehen
              _refreshLeagues();
            }
          } else {
            // Normaler Tab-Wechsel
            setState(() { _selectedIndex = index; });
          }
        },
        onReorder: _onReorder,
      ),
    );
  }
}
