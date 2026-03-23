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
      _leagueData = {
        'name': tournament['name'],
        'image_url': tournament['image_url'],
      };
    });
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

    final selectedTournament = allTournaments.where((t) => t['id'] == selectedTournamentId).toList();
    final activeInitialized = allTournaments.where((t) => t['id'] != selectedTournamentId && _isActiveAndInitialized(t)).toList();
    final initializing = allTournaments.where((t) => t['id'] != selectedTournamentId && _isTournamentInitializing(t)).toList();
    final inactiveOrUninitialized = allTournaments.where((t) {
      if (t['id'] == selectedTournamentId) return false;
      return !_isActiveAndInitialized(t) && !_isTournamentInitializing(t);
    }).toList();

    final ordered = [...selectedTournament, ...activeInitialized, ...initializing, ...inactiveOrUninitialized];

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
                            : () {
                          if (needsInitialization) {
                            _showInitializeDialog(tournament, season);
                            return;
                          }

                          if (isInitializing) {
                            _openInitializationTab(tournament: tournament, season: season);
                            return;
                          }

                          tournamentVm.selectTournament(tournament['id'] as int, season['id'] as int);
                          setState(() {
                            _leagueData = {
                              'name': tournament['name'],
                              'image_url': tournament['image_url'],
                            };
                          });
                        },
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              sliver: SliverToBoxAdapter(
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Turnier-Initialisierung',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Turnier-ID: ${_initializingTournamentId ?? '-'} | Saison-ID: ${_initializingSeasonId ?? '-'}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: _isInitializingSeason ? null : _initializationProgress,
                            minHeight: 10,
                            color: primaryColor,
                            backgroundColor: primaryColor.withOpacity(0.2),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(_initializationStatus),
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
