// lib/screens/leagues/league_settings_screen.dart
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

class _LeagueSettingsScreenState extends State<LeagueSettingsScreen> with TickerProviderStateMixin {
  static const double _headerImageRadius = 50;
  static const double _collapsedImageRadius = 18;
  static const double _imageEditButtonSize = 28;

  final supabase = Supabase.instance.client;
  final ImagePicker _imagePicker = ImagePicker();

  late TabController _tabController;

  bool _isLoading = true;
  bool _isAdmin = false;

  // Liga-Daten
  Map<String, dynamic> _leagueData = {};
  String _adminUsername = 'Unbekannt';

  // Bild-Variablen
  Uint8List? _localImageBytes;
  bool _showInitializationTab = false;
  bool _isInitializingSeason = false;
  double _initializationProgress = 0;
  String _initializationStatus = 'Warte auf Start...';
  int? _initializingTournamentId;
  int? _initializingSeasonId;
  final ScrollController _currentTaskPlayerScrollController = ScrollController();
  final ScrollController _teamTaskScrollController = ScrollController();
  final Map<int, Map<String, dynamic>> _teamMetaCache = <int, Map<String, dynamic>>{};
  final Map<int, Map<String, dynamic>> _playerMetaCache = <int, Map<String, dynamic>>{};
  String? _playerTimelineKey;
  int _playerTimelineCount = 0;
  static const List<String> _taskOrder = <String>[
    'FETCH_TEAMS',
    'FETCH_TEAM_SQUAD',
    'FETCH_SQUADS',
    'FETCH_ROUNDS',
    'FETCH_MATCHES',
    'UPDATE_SCHEDULE',
    'UPDATE_MATCH',
    'SYNC_TRANSFERS',
    'REPAIR_PLAYERS',
  ];
  static const List<String> _matchProcessingTaskTypes = <String>[
    'UPDATE_SCHEDULE',
    'UPDATE_MATCH',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _loadLeagueData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _currentTaskPlayerScrollController.dispose();
    _teamTaskScrollController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!mounted) return;
    if (_tabController.indexIsChanging) return;
    setState(() {});
  }

  int get _tabCount => widget.isTournamentTab && _showInitializationTab ? 2 : 1;

  Map<String, dynamic>? _resolveSeason(Map<String, dynamic> tournament) {
    final seasons = List<Map<String, dynamic>>.from(tournament['season'] ?? []);
    if (seasons.isEmpty) return null;
    final activeInitialized = seasons.where((s) => s['is_active'] == true && s['is_initialized'] == true).toList();
    if (activeInitialized.isNotEmpty) return activeInitialized.first;
    final active = seasons.where((s) => s['is_active'] == true).toList();
    if (active.isNotEmpty) return active.first;
    return seasons.first;
  }

  bool _isActiveAndInitialized(Map<String, dynamic> tournament) {
    final season = _resolveSeason(tournament);
    return season?['is_active'] == true && season?['is_initialized'] == true;
  }

  bool _isTournamentInitializing(Map<String, dynamic> tournament) {
    final season = _resolveSeason(tournament);
    return season?['is_active'] == true && season?['is_initialized'] != true;
  }

  Map<String, dynamic>? _findTournamentById(List<Map<String, dynamic>> tournaments, int? tournamentId) {
    if (tournamentId == null) return null;
    final matches = tournaments.where((t) => t['id'] == tournamentId).toList();
    return matches.isNotEmpty ? matches.first : null;
  }

  void _restoreInitializationStateFromTournaments(List<Map<String, dynamic>> tournaments) {
    if (!widget.isTournamentTab) return;

    final inProgress = tournaments.where(_isTournamentInitializing).toList();
    if (inProgress.isEmpty) return;

    final fallbackTournament = inProgress.first;
    final fallbackSeason = _resolveSeason(fallbackTournament);
    if (fallbackSeason == null) return;

    final currentTournament = inProgress.where((t) => t['id'] == _initializingTournamentId).toList();
    final activeTournament = currentTournament.isNotEmpty ? currentTournament.first : fallbackTournament;
    final activeSeason = _resolveSeason(activeTournament);
    if (activeSeason == null) return;

    _showInitializationTab = true;
    _initializingTournamentId = activeTournament['id'] as int?;
    _initializingSeasonId = activeSeason['id'] as int?;
    _initializationStatus = 'Saison wird aktuell initialisiert...';
    _initializationProgress = 0.6;
    _isInitializingSeason = false;
    _updateTabController();
  }

  void _updateTabController({int? targetIndex}) {
    final int nextLength = _tabCount;
    if (_tabController.length == nextLength) {
      if (targetIndex != null && targetIndex < nextLength) {
        _tabController.animateTo(targetIndex);
      }
      return;
    }

    final int fallbackIndex = (_tabController.index).clamp(0, nextLength - 1);
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _tabController = TabController(length: nextLength, vsync: this, initialIndex: fallbackIndex);
    _tabController.addListener(_handleTabChanged);

    if (targetIndex != null && targetIndex < nextLength) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tabController.animateTo(targetIndex);
      });
    }
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
        await tournamentVm.fetchTournaments();
        final tournament = tournamentVm.selectedTournament;
        _restoreInitializationStateFromTournaments(List<Map<String, dynamic>>.from(tournamentVm.allTournaments));

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

  Future<void> _showInitializeDialog(Map<String, dynamic> tournament, Map<String, dynamic> season) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Liga initialisieren?'),
        content: const Text('Möchtest du die Liga initialisieren?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Nein'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _initializeLeagueSeason(tournament: tournament, season: season);
            },
            child: const Text('Ja'),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeLeagueSeason({
    required Map<String, dynamic> tournament,
    required Map<String, dynamic> season,
  }) async {
    final seasonId = season['id'] as int?;
    final tournamentId = tournament['id'] as int?;
    if (seasonId == null || tournamentId == null) return;

    // Wichtig: Erst Controller-Länge anpassen, dann Rebuild auslösen.
    // Sonst kann kurzzeitig TabBar/TabBarView (2 Tabs) mit Controller-Länge 1 gerendert werden.
    _showInitializationTab = true;
    _updateTabController(targetIndex: 1);
    setState(() {
      _isInitializingSeason = true;
      _initializingSeasonId = seasonId;
      _initializingTournamentId = tournamentId;
      _initializationProgress = 0.2;
      _initializationStatus = 'Aktiviere Saison in der Datenbank...';
    });

    try {
      await supabase.from('season').update({'is_active': true}).eq('id', seasonId);

      if (!mounted) return;
      setState(() {
        _initializationProgress = 0.45;
        _initializationStatus = 'Saison ist aktiv. Initialisierung wird geprüft...';
      });

      final tournamentVm = context.read<TournamentViewModel>();
      await tournamentVm.fetchTournaments();
      _restoreInitializationStateFromTournaments(List<Map<String, dynamic>>.from(tournamentVm.allTournaments));

      bool initialized = false;
      for (int attempt = 0; attempt < 10; attempt++) {
        final response = await supabase
            .from('season')
            .select('is_initialized')
            .eq('id', seasonId)
            .single();

        initialized = response['is_initialized'] == true;
        if (initialized) break;
        await Future.delayed(const Duration(seconds: 2));
      }

      if (!mounted) return;
      setState(() {
        _isInitializingSeason = false;
        _initializationProgress = initialized ? 1.0 : 0.75;
        _initializationStatus = initialized
            ? 'Initialisierung abgeschlossen. Du kannst jetzt in das Turnier wechseln.'
            : 'Initialisierung läuft noch. Bitte kurz warten und später erneut prüfen.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializingSeason = false;
        _initializationProgress = 0;
        _initializationStatus = 'Fehler bei der Initialisierung: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Initialisierung fehlgeschlagen: $e')),
      );
    }
  }

  void _openInitializationTab({
    required Map<String, dynamic> tournament,
    required Map<String, dynamic> season,
  }) {
    final seasonId = season['id'] as int?;
    final tournamentId = tournament['id'] as int?;
    if (seasonId == null || tournamentId == null) return;

    _showInitializationTab = true;
    _updateTabController(targetIndex: 1);
    setState(() {
      _initializingSeasonId = seasonId;
      _initializingTournamentId = tournamentId;
      _isInitializingSeason = false;
      _initializationProgress = 0.6;
      _initializationStatus = 'Saison wird aktuell initialisiert...';
    });
  }

  Future<void> _selectActiveTournamentAndReturn({
    required TournamentViewModel tournamentVm,
    required Map<String, dynamic> tournament,
    required Map<String, dynamic> season,
  }) async {
    tournamentVm.selectTournament(tournament['id'] as int, season['id'] as int);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final tournamentVm = context.watch<TournamentViewModel>();
    final allTournaments = List<Map<String, dynamic>>.from(tournamentVm.allTournaments);
    final selectedTournamentId = tournamentVm.currentTournamentId;
    final selectedInitializingTournament = _findTournamentById(allTournaments, _initializingTournamentId);
    final bool showInitializingRow = widget.isTournamentTab &&
        _showInitializationTab &&
        _tabController.index == 1 &&
        selectedInitializingTournament != null &&
        _isTournamentInitializing(selectedInitializingTournament) &&
        selectedTournamentId != _initializingTournamentId;
    final double bottomHeight = showInitializingRow ? 104.0 : 48.0;

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
                  preferredSize: Size.fromHeight(bottomHeight),
                  child: Container(
                    color: Colors.white,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TabBar(
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
                        if (showInitializingRow)
                          _buildSelectedInitializingTournamentRow(
                            tournament: selectedInitializingTournament,
                          ),
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
    final activeInitialized = allTournaments.where(_isActiveAndInitialized).toList()
      ..sort((a, b) {
        final aSelected = a['id'] == selectedTournamentId;
        final bSelected = b['id'] == selectedTournamentId;
        if (aSelected == bSelected) return 0;
        return aSelected ? -1 : 1;
      });
    final initializing = allTournaments.where(_isTournamentInitializing).toList();
    final inactiveOrUninitialized = allTournaments.where((t) {
      return !_isActiveAndInitialized(t) && !_isTournamentInitializing(t);
    }).toList();

    return Builder(
      builder: (BuildContext context) {
        final List<Map<String, dynamic>> visibleSections = [
          {'title': 'Aktiv & initialisiert', 'items': activeInitialized},
          {'title': 'Wird initialisiert', 'items': initializing},
          {'title': 'Nicht initialisiert', 'items': inactiveOrUninitialized},
        ];
        final hasAnyItems = visibleSections.any(
          (section) => (section['items'] as List<Map<String, dynamic>>).isNotEmpty,
        );

        return CustomScrollView(
          key: const PageStorageKey<String>('tournamentTab'),
          slivers: [
            SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              sliver: hasAnyItems
                  ? SliverList(
                delegate: SliverChildListDelegate([
                  _buildTournamentSection(
                    title: 'Aktiv & initialisiert',
                    tournaments: activeInitialized,
                    selectedTournamentId: selectedTournamentId,
                    primaryColor: primaryColor,
                    tournamentVm: tournamentVm,
                  ),
                  _buildTournamentSection(
                    title: 'Wird initialisiert',
                    tournaments: initializing,
                    selectedTournamentId: selectedTournamentId,
                    primaryColor: primaryColor,
                    tournamentVm: tournamentVm,
                  ),
                  _buildTournamentSection(
                    title: 'Nicht initialisiert',
                    tournaments: inactiveOrUninitialized,
                    selectedTournamentId: selectedTournamentId,
                    primaryColor: primaryColor,
                    tournamentVm: tournamentVm,
                  ),
                ]),
              )
                  : const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: Text('Keine Turniere verfügbar.')),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTournamentSection({
    required String title,
    required List<Map<String, dynamic>> tournaments,
    required int? selectedTournamentId,
    required Color primaryColor,
    required TournamentViewModel tournamentVm,
  }) {
    if (tournaments.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8, top: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...tournaments.map((tournament) {
          final season = _resolveSeason(tournament);
          final bool isSelected = tournament['id'] == selectedTournamentId;
          final bool isInitializationFocus = tournament['id'] == _initializingTournamentId && _showInitializationTab;
          final bool isEnabled = isSelected || _isActiveAndInitialized(tournament);
          final bool isInitializing = _isTournamentInitializing(tournament);
          final bool needsInitialization = !isEnabled && !isInitializing;

          final statusText = isInitializationFocus
              ? (isSelected ? 'Ausgewählt & Initialisierungsansicht' : 'In Initialisierungsansicht geöffnet')
              : (isSelected
              ? 'Aktuell ausgewählt'
              : (isEnabled
              ? 'Aktiv & initialisiert'
              : (isInitializing ? 'Wird gerade initialisiert' : 'Nicht aktiv oder nicht initialisiert')));

          return Opacity(
            opacity: (isEnabled || isInitializing) ? 1 : 0.5,
            child: Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: isSelected
                    ? BorderSide(color: primaryColor, width: 2)
                    : (isInitializationFocus
                    ? BorderSide(color: Colors.orange.shade700, width: 2)
                    : BorderSide.none),
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
                    : (isInitializationFocus
                    ? Icon(Icons.hourglass_top, color: Colors.orange.shade700)
                    : const Icon(Icons.chevron_right)),
                onTap: season == null || isSelected
                    ? null
                    : () async {
                  if (needsInitialization) {
                    _showInitializeDialog(tournament, season);
                    return;
                  }

                  if (isInitializing) {
                    _openInitializationTab(tournament: tournament, season: season);
                    return;
                  }

                  await _selectActiveTournamentAndReturn(
                    tournamentVm: tournamentVm,
                    tournament: tournament,
                    season: season,
                  );
                },
              ),
            ),
          );
        }),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildSelectedInitializingTournamentRow({
    required Map<String, dynamic> tournament,
  }) {
    final imageUrl = tournament['image_url'] as String?;

    return InkWell(
      onTap: () => _tabController.animateTo(0),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 1)),
        ),
        child: Row(
          children: [
            LeagueLogo(imageUrl: imageUrl, radius: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tournament['name']?.toString() ?? 'Turnier',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.swap_horiz, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildInitializationTab(Color primaryColor) {
    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          key: const PageStorageKey<String>('initializationTab'),
          slivers: [
            SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              sliver: SliverToBoxAdapter(child: _buildSyncTaskCards(primaryColor)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSyncTaskCards(Color primaryColor) {
    if (_initializingSeasonId == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('sync_tasks')
          .stream(primaryKey: const ['id'])
          .eq('season_id', _initializingSeasonId!)
          .order('created_at'),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            color: Colors.red.shade50,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Fehler beim Laden der sync_tasks.'),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()));
        }

        final taskRows = snapshot.data ?? const <Map<String, dynamic>>[];

        final Map<String, List<Map<String, dynamic>>> grouped = <String, List<Map<String, dynamic>>>{};
        for (final row in taskRows) {
          final taskType = (row['task_type'] ?? 'UNKNOWN').toString();
          grouped.putIfAbsent(taskType, () => <Map<String, dynamic>>[]).add(row);
        }
        final teamIds = taskRows
            .map((row) => row['team_id'])
            .whereType<num>()
            .map((id) => id.toInt())
            .toSet()
            .toList(growable: false);

        final taskTypes = grouped.keys.toList()
          ..sort((a, b) {
            final ai = _taskOrder.indexOf(a);
            final bi = _taskOrder.indexOf(b);
            final aIndex = ai == -1 ? 999 : ai;
            final bIndex = bi == -1 ? 999 : bi;
            if (aIndex != bIndex) return aIndex.compareTo(bIndex);
            return a.compareTo(b);
          });

        String? activeTaskType;
        for (final type in taskTypes) {
          final rows = grouped[type]!;
          final hasProcessing = rows.any((r) => (r['status'] ?? '').toString().toUpperCase() == 'PROCESSING');
          if (hasProcessing) {
            activeTaskType = type;
            break;
          }
        }
        activeTaskType ??= taskTypes.cast<String?>().firstWhere(
              (type) => grouped[type!]!
                  .any((r) => !{'COMPLETED', 'FAILED'}.contains((r['status'] ?? '').toString().toUpperCase())),
              orElse: () => null,
            );

        return FutureBuilder<Map<int, Map<String, dynamic>>>(
          future: _loadTeamMeta(teamIds),
          builder: (context, teamSnapshot) {
            final teamMeta = teamSnapshot.data ?? _teamMetaCache;
            final stages = _buildInitializationStages(taskRows);
            return _buildInitializationPipelineLayout(
              stages: stages,
              grouped: grouped,
              taskTypes: taskTypes,
              activeTaskType: activeTaskType,
              primaryColor: primaryColor,
              teamMeta: teamMeta,
              taskRows: taskRows,
            );
          },
        );
      },
    );
  }

  Widget _buildInitializationPipelineLayout({
    required List<_InitializationStageState> stages,
    required Map<String, List<Map<String, dynamic>>> grouped,
    required List<String> taskTypes,
    required String? activeTaskType,
    required Color primaryColor,
    required Map<int, Map<String, dynamic>> teamMeta,
    required List<Map<String, dynamic>> taskRows,
  }) {
    final completedTitles = stages.where((stage) => stage.isCompleted).map((stage) => stage.title).toList(growable: false);
    final firstOpenIndex = stages.indexWhere((stage) => !stage.isCompleted);
    final activeStageIndex = firstOpenIndex == -1 ? math.max(stages.length - 1, 0) : firstOpenIndex;

    final overallProgress = _calculateOverallProgress(taskRows, stages);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOverallProgressBar(overallProgress),
        const SizedBox(height: 10),
        _buildCompletedStageStrip(completedTitles),
        const SizedBox(height: 12),
        if (taskRows.isEmpty)
          Card(
            elevation: 0,
            color: Colors.grey.shade100,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Noch keine Tasks in sync_tasks gefunden.'),
            ),
          )
        else ...[
          ...List<Widget>.generate(stages.length, (index) {
            final stage = stages[index];
            return _buildInitializationStageCard(
              stage: stage,
              index: index,
              isExpanded: index == activeStageIndex,
              grouped: grouped,
              taskTypes: taskTypes,
              activeTaskType: activeTaskType,
              primaryColor: primaryColor,
              teamMeta: teamMeta,
            );
          }),
        ],
      ],
    );
  }

  Widget _buildCompletedStageStrip(List<String> completedTitles) {
    final text = completedTitles.isEmpty ? 'Fertig: Noch keine Aufgabe abgeschlossen' : 'Fertig: ${completedTitles.join(' • ')}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.green.shade800,
          fontSize: 14,
        ),
      ),
    );
  }

  List<_InitializationStageState> _buildInitializationStages(List<Map<String, dynamic>> taskRows) {
    final bool finishCompleted =
        _initializationProgress >= 1.0 || _initializationStatus.toLowerCase().contains('abgeschlossen');

    return <_InitializationStageState>[
      _resolveStageState(
        title: 'Initialisiere Teams',
        taskRows: taskRows,
        taskTypes: const <String>{'FETCH_TEAMS'},
      ),
      _resolveStageState(
        title: 'Initialisiere Spieler',
        taskRows: taskRows,
        taskTypes: const <String>{'FETCH_TEAM_SQUAD', 'FETCH_SQUADS'},
      ),
      _resolveStageState(
        title: 'Initialisiere Spieltage',
        taskRows: taskRows,
        taskTypes: const <String>{'FETCH_ROUNDS'},
      ),
      _resolveStageState(
        title: 'Initialisiere Spiele',
        taskRows: taskRows,
        taskTypes: const <String>{'FETCH_MATCHES'},
      ),
      _resolveStageState(
        title: 'Bearbeite Spiele',
        taskRows: taskRows,
        taskTypes: _matchProcessingTaskTypes.toSet(),
      ),
      _resolveFinishStageState(isCompleted: finishCompleted),
    ];
  }

  _InitializationStageState _resolveStageState({
    required String title,
    required List<Map<String, dynamic>> taskRows,
    required Set<String> taskTypes,
  }) {
    final rows = taskRows.where((row) => taskTypes.contains((row['task_type'] ?? '').toString())).toList();
    if (rows.isEmpty) {
      return _InitializationStageState(title: title, taskTypes: taskTypes, isCompleted: false, isInProgress: false);
    }

    final normalizedStatuses = rows.map(_rowStatus).toList(growable: false);
    final isCompleted = normalizedStatuses.isNotEmpty && normalizedStatuses.every((status) => status == 'COMPLETED');
    final hasInProgress = normalizedStatuses.any((status) => status == 'PROCESSING');
    final hasStarted = normalizedStatuses.any((status) => status != 'PENDING');

    return _InitializationStageState(
      title: title,
      taskTypes: taskTypes,
      isCompleted: isCompleted,
      isInProgress: !isCompleted && (hasInProgress || hasStarted),
    );
  }

  _InitializationStageState _resolveFinishStageState({required bool isCompleted}) {
    return _InitializationStageState(
      title: 'Initialisierung abschließen',
      taskTypes: const <String>{},
      isCompleted: isCompleted,
      isInProgress: !isCompleted && _initializationProgress > 0.0,
    );
  }

  Widget _buildInitializationStageCard({
    required _InitializationStageState stage,
    required int index,
    required bool isExpanded,
    required Map<String, List<Map<String, dynamic>>> grouped,
    required List<String> taskTypes,
    required String? activeTaskType,
    required Color primaryColor,
    required Map<int, Map<String, dynamic>> teamMeta,
  }) {
    final Color color = stage.isCompleted
        ? Colors.green.shade700
        : (stage.isInProgress ? primaryColor : Colors.grey.shade500);
    final IconData icon = stage.isCompleted
        ? Icons.check_circle_rounded
        : (stage.isInProgress ? Icons.autorenew_rounded : Icons.radio_button_unchecked_rounded);

    final stageRows = _rowsForStage(stage: stage, grouped: grouped, taskTypes: taskTypes);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isExpanded ? 1 : 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: EdgeInsets.all(isExpanded ? 16 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${index + 1}.', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stage.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade900,
                    ),
                  ),
                ),
                _buildStatusBadge(
                  label: stage.isCompleted ? 'ERLEDIGT' : (stage.isInProgress ? 'LÄUFT' : 'OFFEN'),
                  color: color,
                ),
              ],
            ),
            if (isExpanded) ...[
              const SizedBox(height: 12),
              if (stage.taskTypes.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade50,
                  ),
                  child: Text(
                    stage.isCompleted ? 'Alle Initialisierungsschritte sind abgeschlossen.' : _initializationStatus,
                    style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                  ),
                )
              else ...[
                _buildCurrentTaskCenterArea(
                  activeTaskType,
                  stage,
                  stageRows,
                  primaryColor,
                  teamMeta,
                ),
                const SizedBox(height: 12),
                Text('Initialisierte Elemente', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _buildTaskFlowLine(
                  rows: stageRows,
                  taskType: stage.taskTypes.first,
                  primaryColor: primaryColor,
                  teamMeta: teamMeta,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _rowsForStage({
    required _InitializationStageState stage,
    required Map<String, List<Map<String, dynamic>>> grouped,
    required List<String> taskTypes,
  }) {
    if (stage.taskTypes.isEmpty) return const <Map<String, dynamic>>[];
    final ordered = taskTypes.where((type) => stage.taskTypes.contains(type)).toList(growable: false);
    final rows = <Map<String, dynamic>>[];
    for (final type in ordered) {
      rows.addAll(grouped[type] ?? const <Map<String, dynamic>>[]);
    }
    return rows;
  }

  Widget _buildStatusBadge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.2),
      ),
    );
  }

  Widget _buildTaskFlowLine({
    required List<Map<String, dynamic>> rows,
    required String taskType,
    required Color primaryColor,
    required Map<int, Map<String, dynamic>> teamMeta,
  }) {
    final completedRows =
        rows.where((r) => (r['status'] ?? '').toString().toUpperCase() == 'COMPLETED').toList(growable: false);
    final processingRows =
        rows.where((r) => (r['status'] ?? '').toString().toUpperCase() == 'PROCESSING').toList(growable: false);
    final pendingRows = rows
        .where((r) => !{'COMPLETED', 'PROCESSING'}.contains((r['status'] ?? '').toString().toUpperCase()))
        .toList(growable: false);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...completedRows.map((row) => _buildTaskFlowNode(
                row: row,
                taskType: taskType,
                color: Colors.green,
                statusIcon: Icons.check_circle,
                actionIcon: Icons.done_all_rounded,
                teamMeta: teamMeta,
              )),
          if (completedRows.isNotEmpty && (processingRows.isNotEmpty || pendingRows.isNotEmpty))
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
            ),
          ...processingRows.map((row) => _buildTaskFlowNode(
                row: row,
                taskType: taskType,
                color: primaryColor,
                statusIcon: Icons.sync,
                actionIcon: Icons.autorenew_rounded,
                teamMeta: teamMeta,
              )),
          if (processingRows.isNotEmpty && pendingRows.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
            ),
          ...pendingRows.map((row) {
            final status = (row['status'] ?? '').toString().toUpperCase();
            final isFailed = status == 'FAILED';
            return _buildTaskFlowNode(
              row: row,
              taskType: taskType,
              color: isFailed ? Colors.red.shade400 : Colors.grey.shade500,
              statusIcon: isFailed ? Icons.error_outline : Icons.radio_button_unchecked,
              actionIcon: isFailed ? Icons.close_rounded : Icons.schedule_rounded,
              teamMeta: teamMeta,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTaskFlowNode({
    required Map<String, dynamic> row,
    required String taskType,
    required Color color,
    required IconData statusIcon,
    required IconData actionIcon,
    required Map<int, Map<String, dynamic>> teamMeta,
  }) {
    final teamId = row['team_id'];
    final matchId = row['match_id'];
    final status = (row['status'] ?? '').toString().toUpperCase();
    final bool isFetchTeams = taskType == 'FETCH_TEAMS';

    final teamIdInt = teamId is num ? teamId.toInt() : int.tryParse(teamId?.toString() ?? '');
    final teamName = teamIdInt == null ? null : teamMeta[teamIdInt]?['name']?.toString();

    final Widget leading = (isFetchTeams || taskType == 'FETCH_TEAM_SQUAD' || taskType == 'FETCH_SQUADS')
        ? _buildTeamCrest(teamId, color)
        : Icon(statusIcon, size: 18, color: color);

    final String label = teamId != null
        ? (teamName == null ? 'Team $teamId' : '$teamName (#$teamId)')
        : (matchId != null ? 'Match $matchId' : status);

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Icon(actionIcon, size: 14, color: color),
          if (!isFetchTeams) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Future<Map<int, Map<String, dynamic>>> _loadTeamMeta(List<int> teamIds) async {
    final unresolved = teamIds.where((id) => !_teamMetaCache.containsKey(id)).toList(growable: false);
    if (unresolved.isEmpty) return _teamMetaCache;
    try {
      final rows = await supabase.from('team').select('id, name, image_url').inFilter('id', unresolved);
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['id'];
        if (id is num) {
          _teamMetaCache[id.toInt()] = map;
        }
      }
    } catch (_) {}
    return _teamMetaCache;
  }

  String _rowStatus(Map<String, dynamic> row) => (row['status'] ?? '').toString().toUpperCase();

  Widget _buildCurrentTaskCenterArea(
    String? activeTaskType,
    _InitializationStageState stage,
    List<Map<String, dynamic>> activeRows,
    Color primaryColor,
    Map<int, Map<String, dynamic>> teamMeta,
  ) {
    if (activeTaskType == null || activeRows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: const Text('Aktuell keine laufende Task.'),
      );
    }

    final isPlayerStage = stage.taskTypes.contains('FETCH_TEAM_SQUAD') || stage.taskTypes.contains('FETCH_SQUADS');
    if (isPlayerStage && _initializingSeasonId != null) {
      return _buildLiveSquadInitializationProgress(
        rows: activeRows,
        seasonId: _initializingSeasonId!,
        primaryColor: primaryColor,
        teamMeta: teamMeta,
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Text('Aktueller Vorgang: ${_taskTitle(activeTaskType)}'),
    );
  }

  Widget _buildLiveSquadInitializationProgress({
    required List<Map<String, dynamic>> rows,
    required int seasonId,
    required Color primaryColor,
    required Map<int, Map<String, dynamic>> teamMeta,
  }) {
    final orderedTeamIds = rows
        .map((row) => row['team_id'])
        .whereType<num>()
        .map((id) => id.toInt())
        .toSet()
        .toList(growable: false);

    if (orderedTeamIds.isEmpty) {
      return const SizedBox.shrink();
    }

    int activeTeamId = orderedTeamIds.first;
    final processing = rows.where((row) => _rowStatus(row) == 'PROCESSING').toList(growable: false);
    if (processing.isNotEmpty) {
      final raw = processing.first['team_id'];
      final id = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
      if (id != null) activeTeamId = id;
    } else {
      final pending = rows.where((row) => _rowStatus(row) != 'COMPLETED').toList(growable: false);
      if (pending.isNotEmpty) {
        final raw = pending.first['team_id'];
        final id = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
        if (id != null) activeTeamId = id;
      }
    }

    final activeTeamIndex = orderedTeamIds.indexOf(activeTeamId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_teamTaskScrollController.hasClients && activeTeamIndex >= 0) {
        final targetOffset = (activeTeamIndex * 92.0).clamp(
          0.0,
          _teamTaskScrollController.position.maxScrollExtent,
        );
        _teamTaskScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
        );
      }
    });

    final activeTeamName = teamMeta[activeTeamId]?['name']?.toString() ?? 'Team $activeTeamId';

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('season_players')
          .stream(primaryKey: const ['season_id', 'player_id'])
          .eq('season_id', seasonId),
      builder: (context, snapshot) {
        final playerRows = (snapshot.data ?? const <Map<String, dynamic>>[])
            .map((r) => Map<String, dynamic>.from(r))
            .where((row) {
              final rawTeamId = row['team_id'];
              final rowTeamId = rawTeamId is num ? rawTeamId.toInt() : int.tryParse(rawTeamId?.toString() ?? '');
              return rowTeamId == activeTeamId;
            })
            .toList()
          ..sort((a, b) => ((a['player_id'] ?? 0) as num).compareTo((b['player_id'] ?? 0) as num));

        final timelineKey = '$seasonId-$activeTeamId';
        if (_playerTimelineKey != timelineKey) {
          _playerTimelineKey = timelineKey;
          _playerTimelineCount = 0;
        }
        if (playerRows.length > _playerTimelineCount) {
          _playerTimelineCount = playerRows.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_currentTaskPlayerScrollController.hasClients) {
              _currentTaskPlayerScrollController.animateTo(
                _currentTaskPlayerScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOut,
              );
            }
          });
        }

        final playerIds = playerRows
            .map((row) => row['player_id'])
            .whereType<num>()
            .map((id) => id.toInt())
            .toList(growable: false);

        return FutureBuilder<Map<int, Map<String, dynamic>>>(
          future: _loadPlayerMeta(playerIds),
          builder: (context, playerSnapshot) {
            final playerMeta = playerSnapshot.data ?? _playerMetaCache;

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Aktuelle Task: Initialisiere Spieler', style: TextStyle(fontWeight: FontWeight.w700, color: primaryColor)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 76,
                    child: SingleChildScrollView(
                      controller: _teamTaskScrollController,
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: orderedTeamIds.map((teamId) {
                          final isActive = teamId == activeTeamId;
                          final teamName = teamMeta[teamId]?['name']?.toString() ?? 'Team $teamId';
                          final teamStatus = rows
                              .where((row) => (row['team_id'] is num ? (row['team_id'] as num).toInt() : null) == teamId)
                              .map(_rowStatus)
                              .toList(growable: false);
                          final isDone = teamStatus.isNotEmpty && teamStatus.every((status) => status == 'COMPLETED');
                          return Container(
                            width: 84,
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: isActive ? primaryColor.withOpacity(0.1) : Colors.transparent,
                              border: Border.all(
                                color: isDone ? Colors.green.shade300 : (isActive ? primaryColor.withOpacity(0.4) : Colors.grey.shade300),
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildTeamCrest(teamId, isDone ? Colors.green : primaryColor),
                                const SizedBox(height: 4),
                                Text(
                                  teamName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          );
                        }).toList(growable: false),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Team: $activeTeamName • Initialisierte Spieler: ${playerRows.length}', style: TextStyle(color: Colors.grey.shade700)),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    controller: _currentTaskPlayerScrollController,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: playerRows.map((row) {
                        final playerIdRaw = row['player_id'];
                        final playerId = playerIdRaw is num ? playerIdRaw.toInt() : int.tryParse(playerIdRaw?.toString() ?? '');
                        final data = playerId == null ? null : playerMeta[playerId];
                        return _buildInitializedPlayerCard(
                          playerId: playerId,
                          playerData: data,
                          teamName: activeTeamName,
                          accentColor: primaryColor,
                        );
                      }).toList(growable: false),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInitializedPlayerCard({
    required int? playerId,
    required Map<String, dynamic>? playerData,
    required String teamName,
    required Color accentColor,
  }) {
    final playerName = playerData?['name']?.toString() ?? 'Spieler #${playerId ?? '-'}';
    final imageUrl = playerData?['profilbild_url']?.toString();
    final marketValue = _formatMarketValue(playerData?['marktwert']);

    return Container(
      width: 210,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        border: Border.all(color: accentColor.withOpacity(0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: (imageUrl != null && imageUrl.isNotEmpty) ? NetworkImage(imageUrl) : null,
            child: (imageUrl == null || imageUrl.isEmpty)
                ? const Icon(Icons.person, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(playerName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(teamName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                const SizedBox(height: 4),
                Text('Marktwert: $marketValue', style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<int, Map<String, dynamic>>> _loadPlayerMeta(List<int> playerIds) async {
    final unresolved = playerIds.where((id) => !_playerMetaCache.containsKey(id)).toList(growable: false);
    if (unresolved.isEmpty) return _playerMetaCache;
    try {
      final rows = await supabase
          .from('spieler')
          .select('id, name, profilbild_url, spieler_analytics(marktwert)')
          .inFilter('id', unresolved);
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final idRaw = map['id'];
        if (idRaw is! num) continue;
        final analyticsRaw = map['spieler_analytics'];
        int? marketValue;
        if (analyticsRaw is List && analyticsRaw.isNotEmpty) {
          final first = analyticsRaw.first;
          if (first is Map && first['marktwert'] is num) {
            marketValue = (first['marktwert'] as num).toInt();
          }
        }
        map['marktwert'] = marketValue;
        _playerMetaCache[idRaw.toInt()] = map;
      }
    } catch (_) {}
    return _playerMetaCache;
  }

  String _formatMarketValue(dynamic raw) {
    final value = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    if (value == null || value <= 0) return 'k. A.';
    if (value >= 1000000) {
      final asM = value / 1000000;
      return '€ ${asM.toStringAsFixed(asM >= 10 ? 0 : 1)} Mio';
    }
    if (value >= 1000) {
      final asK = value / 1000;
      return '€ ${asK.toStringAsFixed(asK >= 10 ? 0 : 1)} Tsd';
    }
    return '€ $value';
  }

  double _calculateOverallProgress(
    List<Map<String, dynamic>> taskRows,
    List<_InitializationStageState> stages,
  ) {
    if (taskRows.isNotEmpty) {
      final completed = taskRows.where((row) => _rowStatus(row) == 'COMPLETED').length;
      final failed = taskRows.where((row) => _rowStatus(row) == 'FAILED').length;
      final denominator = taskRows.length - failed;
      if (denominator > 0) {
        return (completed / denominator).clamp(0.0, 1.0);
      }
    }

    final completedStages = stages.where((stage) => stage.isCompleted).length;
    if (stages.isNotEmpty) {
      return (completedStages / stages.length).clamp(0.0, 1.0);
    }

    return _initializationProgress.clamp(0.0, 1.0);
  }

  Widget _buildOverallProgressBar(double progress) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timelapse_rounded, size: 18, color: Colors.black87),
              const SizedBox(width: 8),
              const Text('Gesamtfortschritt', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${(progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamCrest(dynamic teamIdRaw, Color color) {
    final teamId = teamIdRaw is num ? teamIdRaw.toInt() : int.tryParse(teamIdRaw?.toString() ?? '');
    if (teamId == null) {
      return Icon(Icons.shield_outlined, size: 18, color: color);
    }

    final imagePath = 'wappen/$teamId.jpg';
    final imageUrl = supabase.storage.from('wappen').getPublicUrl(imagePath);

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.35)),
        image: DecorationImage(
          image: NetworkImage(imageUrl),
          fit: BoxFit.cover,
          onError: (exception, stackTrace) {},
        ),
      ),
    );
  }

  String _taskTitle(String taskType) {
    switch (taskType) {
      case 'FETCH_TEAMS':
        return 'Teams laden';
      case 'FETCH_TEAM_SQUAD':
      case 'FETCH_SQUADS':
        return 'Kader laden';
      case 'FETCH_ROUNDS':
        return 'Spieltage laden';
      case 'FETCH_MATCHES':
        return 'Spiele laden';
      case 'UPDATE_SCHEDULE':
        return 'Spielplan aktualisieren';
      case 'UPDATE_MATCH':
        return 'Live-Spiel aktualisieren';
      case 'SYNC_TRANSFERS':
        return 'Transfers synchronisieren';
      case 'REPAIR_PLAYERS':
        return 'Spieler reparieren';
      default:
        return taskType.replaceAll('_', ' ');
    }
  }

  String _taskDescription(String taskType) {
    switch (taskType) {
      case 'FETCH_TEAMS':
        return 'Grunddaten der Teams werden importiert.';
      case 'FETCH_TEAM_SQUAD':
      case 'FETCH_SQUADS':
        return 'Spielerkader der Teams werden aufgebaut.';
      case 'FETCH_ROUNDS':
        return 'Spieltage der Saison werden erstellt.';
      case 'FETCH_MATCHES':
        return 'Spiele inklusive Terminierung werden geladen.';
      case 'UPDATE_SCHEDULE':
        return 'Der Spielplan wird mit neuen Daten abgeglichen.';
      case 'UPDATE_MATCH':
        return 'Live-Daten eines laufenden Spiels werden synchronisiert.';
      case 'SYNC_TRANSFERS':
        return 'Transferbewegungen werden eingespielt.';
      case 'REPAIR_PLAYERS':
        return 'Fehlende oder defekte Spielerdaten werden repariert.';
      default:
        return 'Task aus sync_tasks.';
    }
  }

  IconData _taskIcon(String taskType) {
    switch (taskType) {
      case 'FETCH_TEAMS':
        return Icons.groups_rounded;
      case 'FETCH_TEAM_SQUAD':
      case 'FETCH_SQUADS':
        return Icons.badge_rounded;
      case 'FETCH_ROUNDS':
        return Icons.calendar_view_week_rounded;
      case 'FETCH_MATCHES':
        return Icons.sports_soccer_rounded;
      case 'UPDATE_SCHEDULE':
        return Icons.event_repeat_rounded;
      case 'UPDATE_MATCH':
        return Icons.live_tv_rounded;
      case 'SYNC_TRANSFERS':
        return Icons.compare_arrows_rounded;
      case 'REPAIR_PLAYERS':
        return Icons.build_circle_rounded;
      default:
        return Icons.task_alt_rounded;
    }
  }
}

class _InitializationStageState {
  final String title;
  final Set<String> taskTypes;
  final bool isCompleted;
  final bool isInProgress;

  const _InitializationStageState({
    required this.title,
    required this.taskTypes,
    required this.isCompleted,
    required this.isInProgress,
  });
}
