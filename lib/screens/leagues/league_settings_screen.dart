// lib/screens/leagues/league_settings_screen.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/screens/screenelements/league_logo.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';

class LeagueSettingsScreen extends StatefulWidget {
  final int? leagueId;
  final bool isTournamentTab;

  const LeagueSettingsScreen({
    super.key,
    this.leagueId,
    this.isTournamentTab = false,
  }) : assert(isTournamentTab || leagueId != null, 'leagueId is required when isTournamentTab is false');

  @override
  State<LeagueSettingsScreen> createState() => _LeagueSettingsScreenState();
}

class _LeagueSettingsScreenState extends State<LeagueSettingsScreen> with SingleTickerProviderStateMixin {
  static const double _headerImageRadius = 50;
  static const double _collapsedImageRadius = 18;
  static const double _imageEditButtonSize = 28;

  final supabase = Supabase.instance.client;
  final ImagePicker _imagePicker = ImagePicker();

  late TabController _tabController;

  bool _isLoading = true;
  bool _isAdmin = false;
  bool _showInitializationTab = false;
  bool _isInitializingTournament = false;
  String? _initializingTournamentName;
  int? _initializingSeasonId;
  bool _initializationCompleted = false;
  Timer? _initializationPollingTimer;

  // Liga-Daten
  Map<String, dynamic> _leagueData = {};
  String _adminUsername = 'Unbekannt';

  // Bild-Variablen
  Uint8List? _localImageBytes;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _loadLeagueData();
  }

  @override
  void dispose() {
    _initializationPollingTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  int get _tabCount => widget.isTournamentTab && _showInitializationTab ? 2 : 1;

  void _recreateTabController() {
    final previousIndex = _tabController.index;
    _tabController.dispose();
    _tabController = TabController(length: _tabCount, vsync: this);
    _tabController.index = previousIndex.clamp(0, _tabCount - 1);
  }

  ImageProvider? _getLeagueImageProvider() {
    if (_localImageBytes != null) return MemoryImage(_localImageBytes!);
    final url = _leagueData['image_url'] as String?;
    if (url != null && url.isNotEmpty) return NetworkImage(url);
    return null;
  }

  Future<void> _loadLeagueData() async {
    setState(() => _isLoading = true);

    try {
      if (widget.isTournamentTab) {
        final tournamentVm = context.read<TournamentViewModel>();
        final tournament = tournamentVm.selectedTournament;

        _leagueData = {
          'name': tournament?['name'] ?? 'Turnier',
          'image_url': tournament?['image_url'],
        };
        _adminUsername = 'System';

        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final response = await supabase
          .from('leagues')
          .select('*, admin:profiles!leagues_admin_id_fkey(username)')
          .eq('id', widget.leagueId!)
          .single();

      _leagueData = response;
      _isAdmin = _leagueData['admin_id'] == currentUser.id;

      if (_leagueData['admin'] != null) {
        _adminUsername = _leagueData['admin']['username'] ?? 'Unbekannt';
      }

    } catch (e) {
      print('Fehler beim Laden der Liga-Daten: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // --- BILD UPLOAD (Nur für Admin) ---
  Future<void> _pickNewLeagueImage() async {
    if (!_isAdmin || widget.isTournamentTab) return;

    final picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() => _localImageBytes = bytes);

    try {
      // Dateiname ist einfach die Liga-ID. Wird überschrieben, wenn schon vorhanden (upsert).
      final path = '${widget.leagueId!}.jpg';

      await supabase.storage.from('league_images').uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      final newUrl = supabase.storage.from('league_images').getPublicUrl(path);

      await supabase.from('leagues').update({'image_url': newUrl}).eq('id', widget.leagueId!);

      if (mounted) {
        setState(() => _leagueData['image_url'] = newUrl);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ligabild erfolgreich aktualisiert!')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _localImageBytes = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler beim Hochladen: $e')));
    }
  }

  // --- UPDATE FUNKTIONEN (Nur für Admin) ---
  Future<void> _updateLeagueName(String newName) async {
    if (!_isAdmin || widget.isTournamentTab || newName.trim().isEmpty) return;
    try {
      await supabase.from('leagues').update({'name': newName.trim()}).eq('id', widget.leagueId!);
      setState(() => _leagueData['name'] = newName.trim());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Liganame aktualisiert!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _updateVisibility(bool isPublic) async {
    if (!_isAdmin || widget.isTournamentTab) return;
    try {
      await supabase.from('leagues').update({'is_public': isPublic}).eq('id', widget.leagueId!);
      setState(() => _leagueData['is_public'] = isPublic);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  Future<void> _updateSquadLimit(int limit) async {
    if (!_isAdmin || widget.isTournamentTab) return;
    try {
      await supabase.from('leagues').update({'squad_limit': limit}).eq('id', widget.leagueId!);
      setState(() => _leagueData['squad_limit'] = limit);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kadergröße aktualisiert!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  // --- DIALOGE FÜR EINGABEN ---
  void _showEditNameDialog() {
    final TextEditingController controller = TextEditingController(text: _leagueData['name']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Liganame ändern'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Neuer Name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateLeagueName(controller.text);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  void _showEditSquadLimitDialog() {
    final currentLimit = _leagueData['squad_limit']?.toString() ?? '15';
    final TextEditingController controller = TextEditingController(text: currentLimit);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Maximale Kadergröße'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Anzahl Spieler'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              final newLimit = int.tryParse(controller.text);
              if (newLimit != null && newLimit > 0) {
                Navigator.pop(context);
                _updateSquadLimit(newLimit);
              }
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleTournamentTap(
    Map<String, dynamic> tournament,
    Map<String, dynamic>? season,
    bool isSelected,
    bool isEnabled,
  ) async {
    if (season == null || isSelected) return;

    if (isEnabled) {
      context.read<TournamentViewModel>().selectTournament(tournament['id'] as int, season['id'] as int);
      setState(() {
        _leagueData = {
          'name': tournament['name'],
          'image_url': tournament['image_url'],
        };
      });
      return;
    }

    final shouldInitialize = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Liga initialisieren?'),
        content: const Text('Möchtest du die Liga initialisieren?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Nein'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Ja'),
          ),
        ],
      ),
    );

    if (shouldInitialize == true) {
      await _startInitialization(tournament: tournament, season: season);
    }
  }

  Future<void> _startInitialization({
    required Map<String, dynamic> tournament,
    required Map<String, dynamic> season,
  }) async {
    final seasonId = season['id'] as int?;
    if (seasonId == null) return;

    setState(() {
      _showInitializationTab = true;
      _isInitializingTournament = true;
      _initializingTournamentName = tournament['name']?.toString() ?? 'Turnier';
      _initializingSeasonId = seasonId;
      _initializationCompleted = false;
      _recreateTabController();
      _tabController.index = 1;
    });

    try {
      await supabase.from('season').update({'is_active': true}).eq('id', seasonId);
      _startInitializationPolling(tournament, seasonId);
      await context.read<TournamentViewModel>().fetchTournaments();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isInitializingTournament = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Initialisieren: $e')),
      );
    }
  }

  void _startInitializationPolling(Map<String, dynamic> tournament, int seasonId) {
    _initializationPollingTimer?.cancel();
    _initializationPollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final response = await supabase
            .from('season')
            .select('id, is_active, is_initialized')
            .eq('id', seasonId)
            .maybeSingle();

        if (!mounted || response == null) return;
        final bool isInitialized = response['is_initialized'] == true;

        if (isInitialized) {
          _initializationPollingTimer?.cancel();
          context.read<TournamentViewModel>().selectTournament(
            tournament['id'] as int,
            seasonId,
          );
          setState(() {
            _isInitializingTournament = false;
            _initializationCompleted = true;
            _leagueData = {
              'name': tournament['name'],
              'image_url': tournament['image_url'],
            };
          });
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    const double bottomHeight = 48.0;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar(
                expandedHeight: 280.0,
                floating: false,
                pinned: true,
                backgroundColor: Colors.white,
                elevation: 1,
                iconTheme: const IconThemeData(color: Colors.black87),
                flexibleSpace: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double safeAreaTop = MediaQuery.of(context).padding.top;
                    final double screenWidth = MediaQuery.of(context).size.width;
                    final double collapsedHeight = kToolbarHeight + bottomHeight + safeAreaTop;
                    final double expandedHeight = 280.0;
                    final double currentHeight = constraints.maxHeight;
                    final double leagueImageRadius = (screenWidth * 0.14).clamp(40.0, _headerImageRadius);
                    final double cameraButtonSize = (leagueImageRadius * 0.56).clamp(22.0, _imageEditButtonSize);
                    final double cameraIconSize = (cameraButtonSize * 0.58).clamp(14.0, 18.0);
                    final double cameraCenterOffset = leagueImageRadius + (leagueImageRadius / math.sqrt2) - (cameraButtonSize / 2);

                    double fade = 1.0;
                    if (expandedHeight > collapsedHeight) {
                      fade = (currentHeight - collapsedHeight) / (expandedHeight - collapsedHeight);
                      fade = fade.clamp(0.0, 1.0);
                    }

                    return Container(
                      color: Colors.white,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // --- GROSSE ANSICHT ---
                          Positioned(
                            top: safeAreaTop + 16,
                            left: 0, right: 0,
                            child: IgnorePointer(
                              ignoring: fade < 0.5,
                              child: Opacity(
                                opacity: fade,
                                child: Column(
                                  children: [
                                    Stack(
                                      alignment: Alignment.bottomRight,
                                      children: [
                                        CircleAvatar(
                                          radius: leagueImageRadius,
                                          backgroundColor: primaryColor.withOpacity(0.1),
                                          backgroundImage: _getLeagueImageProvider(),
                                          child: _getLeagueImageProvider() == null
                                              ? Icon(Icons.emoji_events, size: leagueImageRadius, color: primaryColor)
                                              : null,
                                        ),
                                        if (_isAdmin)
                                          Positioned(
                                            left: cameraCenterOffset,
                                            top: cameraCenterOffset,
                                            child: _buildEditImageButton(
                                              primaryColor: primaryColor,
                                              buttonSize: cameraButtonSize,
                                              iconSize: cameraIconSize,
                                              onPressed: _pickNewLeagueImage,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _leagueData['name'] ?? 'Liga',
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                        widget.isTournamentTab ? 'Turnierauswahl' : 'Gemanagt von $_adminUsername',
                                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600)
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // --- KLEINE EINGEKLAPPTE ANSICHT ---
                          Positioned(
                            top: safeAreaTop,
                            left: Navigator.canPop(context) ? 64.0 : 16.0,
                            right: 16,
                            height: kToolbarHeight,
                            child: IgnorePointer(
                              ignoring: fade > 0.5,
                              child: Opacity(
                                opacity: 1.0 - fade,
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: _collapsedImageRadius,
                                      backgroundColor: primaryColor.withOpacity(0.1),
                                      backgroundImage: _getLeagueImageProvider(),
                                      child: _getLeagueImageProvider() == null
                                          ? Icon(Icons.emoji_events, size: _collapsedImageRadius, color: primaryColor)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              _leagueData['name'] ?? 'Liga',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                                              maxLines: 1, overflow: TextOverflow.ellipsis
                                          ),
                                          Text(
                                              widget.isTournamentTab ? 'Turnierauswahl' : 'Gemanagt von $_adminUsername',
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                              maxLines: 1, overflow: TextOverflow.ellipsis
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(bottomHeight),
                  child: Container(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: false,
                      labelColor: primaryColor,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: primaryColor,
                      tabs: widget.isTournamentTab
                          ? [
                        const Tab(text: 'Turniere'),
                        if (_showInitializationTab) const Tab(text: 'Initialisierung'),
                      ]
                          : const [
                        Tab(text: 'Einstellungen'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ];
        },
        body: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: TabBarView(
            controller: _tabController,
            children: widget.isTournamentTab
                ? [
              _buildTournamentTab(primaryColor),
              if (_showInitializationTab) _buildInitializationTab(primaryColor),
            ]
                : [
              _buildSettingsTab(primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditImageButton({
    required Color primaryColor,
    required double buttonSize,
    required double iconSize,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: buttonSize,
      height: buttonSize,
      decoration: BoxDecoration(
        color: primaryColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: IconButton(
        icon: Icon(Icons.camera_alt, color: Colors.white, size: iconSize),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      ),
    );
  }

  // --- DER EINSTELLUNGS-TAB ---
  Widget _buildSettingsTab(Color primaryColor) {
    final fmt = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          key: const PageStorageKey<String>('settingsTab'),
          slivers: [
            SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([

                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 8),
                    child: Text('ALLGEMEIN', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12, letterSpacing: 1.2)),
                  ),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.edit),
                          title: const Text('Name der Liga'),
                          subtitle: Text(_leagueData['name'] ?? ''),
                          trailing: _isAdmin ? const Icon(Icons.chevron_right) : null,
                          onTap: _isAdmin ? _showEditNameDialog : null,
                        ),
                        const Divider(height: 1),
                        SwitchListTile(
                          secondary: const Icon(Icons.public),
                          title: const Text('Öffentliche Liga'),
                          subtitle: const Text('Jeder kann der Liga beitreten'),
                          value: _leagueData['is_public'] ?? false,
                          activeColor: primaryColor,
                          onChanged: _isAdmin ? (val) => _updateVisibility(val) : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 8),
                    child: Text('REGELN', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12, letterSpacing: 1.2)),
                  ),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: const Icon(Icons.groups),
                      title: const Text('Max. Kadergröße'),
                      subtitle: Text('${_leagueData['squad_limit'] ?? 'Kein Limit'} Spieler'),
                      trailing: _isAdmin ? const Icon(Icons.chevron_right) : null,
                      onTap: _isAdmin ? _showEditSquadLimitDialog : null,
                    ),
                  ),
                  const SizedBox(height: 24),

                  const Padding(
                    padding: EdgeInsets.only(left: 8, bottom: 8),
                    child: Text('STARTBEDINGUNGEN (Fix)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 12, letterSpacing: 1.2)),
                  ),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.account_balance_wallet),
                          title: const Text('Startbudget'),
                          trailing: Text(
                            fmt.format(_leagueData['starting_budget'] ?? 0),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.person_add),
                          title: const Text('Zugeloste Spieler'),
                          trailing: Text(
                            '${_leagueData['num_starting_players'] ?? 0}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.trending_up),
                          title: const Text('Wert der zugelosten Spieler'),
                          trailing: Text(
                            fmt.format(_leagueData['starting_team_value'] ?? 0),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTournamentTab(Color primaryColor) {
    final tournamentVm = context.watch<TournamentViewModel>();
    final allTournaments = List<Map<String, dynamic>>.from(tournamentVm.allTournaments);
    final selectedTournamentId = tournamentVm.currentTournamentId;

    Map<String, dynamic>? resolveSeason(Map<String, dynamic> tournament) {
      final seasons = List<Map<String, dynamic>>.from(tournament['season'] ?? []);
      if (seasons.isEmpty) return null;
      final activeInitialized = seasons.where((s) => s['is_active'] == true && s['is_initialized'] == true).toList();
      if (activeInitialized.isNotEmpty) return activeInitialized.first;
      final active = seasons.where((s) => s['is_active'] == true).toList();
      if (active.isNotEmpty) return active.first;
      return seasons.first;
    }

    bool isActiveAndInitialized(Map<String, dynamic> tournament) {
      final season = resolveSeason(tournament);
      return season?['is_active'] == true && season?['is_initialized'] == true;
    }

    final selectedTournament = allTournaments.where((t) => t['id'] == selectedTournamentId).toList();
    final activeInitialized = allTournaments.where((t) => t['id'] != selectedTournamentId && isActiveAndInitialized(t)).toList();
    final inactiveOrUninitialized = allTournaments.where((t) => t['id'] != selectedTournamentId && !isActiveAndInitialized(t)).toList();

    final ordered = [...selectedTournament, ...activeInitialized, ...inactiveOrUninitialized];

    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          key: const PageStorageKey<String>('tournamentTab'),
          slivers: [
            SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              sliver: SliverList.builder(
                itemCount: ordered.length,
                itemBuilder: (context, index) {
                  final tournament = ordered[index];
                  final season = resolveSeason(tournament);
                  final bool isSelected = tournament['id'] == selectedTournamentId;
                  final bool isEnabled = isSelected || isActiveAndInitialized(tournament);
                  final bool canInitialize = !isEnabled && season != null;

                  final statusText = isSelected
                      ? 'Aktuell ausgewählt'
                      : (isEnabled ? 'Aktiv & initialisiert' : 'Nicht aktiv oder nicht initialisiert');

                  return Opacity(
                    opacity: isEnabled ? 1 : 0.5,
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: isSelected ? BorderSide(color: primaryColor, width: 2) : BorderSide.none,
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        leading: LeagueLogo(imageUrl: tournament['image_url'] as String?, radius: 20),
                        title: Text(
                          tournament['name']?.toString() ?? 'Turnier',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(statusText),
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: primaryColor)
                            : Icon(canInitialize ? Icons.play_circle_outline : Icons.chevron_right),
                        onTap: () => _handleTournamentTap(tournament, season, isSelected, isEnabled),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInitializationTab(Color primaryColor) {
    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          key: const PageStorageKey<String>('initializationTab'),
          slivers: [
            SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _initializationCompleted ? Icons.check_circle : Icons.hourglass_top,
                          color: _initializationCompleted ? Colors.green : primaryColor,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _initializingTournamentName == null
                              ? 'Initialisierung'
                              : 'Initialisierung: $_initializingTournamentName',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 14),
                        if (_isInitializingTournament) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 12),
                          const Text(
                            'Liga wird vorbereitet. Dieser Vorgang kann kurz dauern.',
                            textAlign: TextAlign.center,
                          ),
                        ] else ...[
                          Text(
                            _initializationCompleted
                                ? 'Die Liga wurde erfolgreich initialisiert und aktiviert.'
                                : 'Initialisierung pausiert oder fehlgeschlagen.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                        if (_initializingSeasonId != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Saison-ID: $_initializingSeasonId',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
