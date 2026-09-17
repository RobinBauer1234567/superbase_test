import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/screenelements/league_logo.dart';
import 'package:premier_league/utils/league_ranking.dart';
import 'package:premier_league/utils/season_order.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';

enum _TournamentGenderFilter { all, men, women }

class TournamentSelectionScreen extends StatefulWidget {
  const TournamentSelectionScreen({super.key});

  @override
  State<TournamentSelectionScreen> createState() =>
      _TournamentSelectionScreenState();
}

class _TournamentSelectionScreenState extends State<TournamentSelectionScreen>
    with TickerProviderStateMixin {
  static const double _headerImageRadius = 50;
  static const double _collapsedImageRadius = 18;

  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  bool _isLoading = true;
  bool _showInitializationTab = false;
  bool _isInitializingSeason = false;
  double _initializationProgress = 0;
  String _initializationStatus = 'Warte auf Start...';
  int? _initializingTournamentId;
  int? _initializingSeasonId;
  String _searchQuery = '';
  _TournamentGenderFilter _genderFilter = _TournamentGenderFilter.all;

  int get _tabCount => 2 + (_showInitializationTab ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _loadTournaments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    setState(() {});
  }

  Map<String, dynamic>? _latestSeason(Map<String, dynamic> tournament) {
    final seasons = managerSeasons(tournament['season']);
    return seasons.isEmpty ? null : seasons.first;
  }

  bool _isLatestInitializing(Map<String, dynamic> tournament) {
    final season = _latestSeason(tournament);
    return season?['is_active'] == true && season?['is_initialized'] != true;
  }

  Map<String, dynamic>? _findTournamentById(
    List<Map<String, dynamic>> tournaments,
    int? tournamentId,
  ) {
    if (tournamentId == null) return null;
    for (final tournament in tournaments) {
      if (tournament['id'] == tournamentId) return tournament;
    }
    return null;
  }

  Future<void> _loadTournaments() async {
    final vm = context.read<TournamentViewModel>();
    try {
      await vm.fetchTournaments();
      _restoreInitializationState(
        List<Map<String, dynamic>>.from(vm.allTournaments),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _restoreInitializationState(
    List<Map<String, dynamic>> tournaments,
  ) {
    final initializing = tournaments.where(_isLatestInitializing).toList();
    if (initializing.isEmpty) return;

    final current = _findTournamentById(
      initializing,
      _initializingTournamentId,
    );
    final tournament = current ?? initializing.first;
    final season = _latestSeason(tournament);
    if (season == null) return;

    _showInitializationTab = true;
    _initializingTournamentId = tournament['id'] as int?;
    _initializingSeasonId = season['id'] as int?;
    _initializationStatus = 'Saison wird aktuell initialisiert...';
    _initializationProgress = 0.6;
    _isInitializingSeason = false;
    _updateTabController();
  }

  void _updateTabController({int? targetIndex}) {
    final nextLength = _tabCount;
    if (_tabController.length == nextLength) {
      if (targetIndex != null && targetIndex < nextLength) {
        _tabController.animateTo(targetIndex);
      }
      return;
    }

    final fallbackIndex = _tabController.index.clamp(0, nextLength - 1).toInt();
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _tabController = TabController(
      length: nextLength,
      vsync: this,
      initialIndex: fallbackIndex,
    );
    _tabController.addListener(_handleTabChanged);

    if (targetIndex != null && targetIndex < nextLength) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tabController.animateTo(targetIndex);
      });
    }
  }

  void _cycleGenderFilter() {
    setState(() {
      switch (_genderFilter) {
        case _TournamentGenderFilter.all:
          _genderFilter = _TournamentGenderFilter.men;
          break;
        case _TournamentGenderFilter.men:
          _genderFilter = _TournamentGenderFilter.women;
          break;
        case _TournamentGenderFilter.women:
          _genderFilter = _TournamentGenderFilter.all;
          break;
      }
    });
  }

  String? get _genderFilterValue {
    switch (_genderFilter) {
      case _TournamentGenderFilter.all:
        return null;
      case _TournamentGenderFilter.men:
        return 'M';
      case _TournamentGenderFilter.women:
        return 'F';
    }
  }

  IconData get _genderFilterIcon {
    switch (_genderFilter) {
      case _TournamentGenderFilter.all:
        return Icons.filter_alt_off;
      case _TournamentGenderFilter.men:
        return Icons.male;
      case _TournamentGenderFilter.women:
        return Icons.female;
    }
  }

  String get _genderFilterTooltip {
    switch (_genderFilter) {
      case _TournamentGenderFilter.all:
        return 'Alle Ligen';
      case _TournamentGenderFilter.men:
        return 'Nur Männerligen';
      case _TournamentGenderFilter.women:
        return 'Nur Frauenligen';
    }
  }

  Future<void> _showInitializeDialog(
    Map<String, dynamic> tournament,
  ) async {
    final season = _latestSeason(tournament);
    if (season == null) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Liga initialisieren?'),
        content: Text(
          'Möchtest du ${tournament['name']} mit der neuesten Saison '
          '${season['name']} initialisieren?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Nein'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _initializeLatestSeason(tournament);
            },
            child: const Text('Ja'),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeLatestSeason(
    Map<String, dynamic> tournament,
  ) async {
    final season = _latestSeason(tournament);
    final seasonId = season?['id'] as int?;
    final tournamentId = tournament['id'] as int?;
    if (seasonId == null || tournamentId == null) return;

    _showInitializationTab = true;
    _updateTabController(targetIndex: 2);
    setState(() {
      _isInitializingSeason = true;
      _initializingSeasonId = seasonId;
      _initializingTournamentId = tournamentId;
      _initializationProgress = 0.2;
      _initializationStatus = 'Aktiviere neueste Saison in der Datenbank...';
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw StateError('Kein angemeldeter Benutzer.');
      }

      await supabase.from('season_activation_requests').insert({
        'season_id': seasonId,
        'requested_by': userId,
      });

      if (!mounted) return;
      setState(() {
        _initializationProgress = 0.45;
        _initializationStatus =
            'Aktivierung angefordert. Der Saison-Dienst übernimmt die Initialisierung.';
      });

      final vm = context.read<TournamentViewModel>();
      await vm.fetchTournaments();

      var initialized = false;
      for (var attempt = 0; attempt < 10; attempt++) {
        final response = await supabase
            .from('season')
            .select('is_initialized')
            .eq('id', seasonId)
            .single();
        initialized = response['is_initialized'] == true;
        if (initialized) break;
        await Future.delayed(const Duration(seconds: 2));
      }

      await vm.fetchTournaments();
      if (!mounted) return;
      setState(() {
        _isInitializingSeason = false;
        _initializationProgress = initialized ? 1.0 : 0.75;
        _initializationStatus = initialized
            ? 'Initialisierung abgeschlossen. Die neueste Saison ist verfügbar.'
            : 'Initialisierung läuft noch. Die Tasks werden weiter unten live angezeigt.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isInitializingSeason = false;
        _initializationProgress = 0;
        _initializationStatus = 'Fehler bei der Initialisierung: $error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Initialisierung fehlgeschlagen: $error')),
      );
    }
  }

  void _openInitializationTab(Map<String, dynamic> tournament) {
    final season = _latestSeason(tournament);
    final seasonId = season?['id'] as int?;
    final tournamentId = tournament['id'] as int?;
    if (seasonId == null || tournamentId == null) return;

    _showInitializationTab = true;
    _updateTabController(targetIndex: 2);
    setState(() {
      _initializingTournamentId = tournamentId;
      _initializingSeasonId = seasonId;
      _isInitializingSeason = false;
      _initializationProgress = 0.6;
      _initializationStatus = 'Saison wird aktuell initialisiert...';
    });
  }

  Future<void> _selectLatestTournamentAndReturn(
    TournamentViewModel vm,
    Map<String, dynamic> tournament,
  ) async {
    final tournamentId = tournament['id'] as int?;
    if (tournamentId == null) return;
    vm.selectLatestTournament(tournamentId);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _selectSeasonAndReturn(
    TournamentViewModel vm,
    Map<String, dynamic> tournament,
    Map<String, dynamic> season,
  ) async {
    final tournamentId = tournament['id'] as int?;
    final seasonId = season['id'] as int?;
    if (tournamentId == null || seasonId == null) return;
    vm.selectTournament(tournamentId, seasonId);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  ImageProvider? _headerImageProvider(Map<String, dynamic>? tournament) {
    final url = tournament?['image_url']?.toString();
    if (url == null || url.isEmpty) return null;
    return NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final vm = context.watch<TournamentViewModel>();
    final tournaments = List<Map<String, dynamic>>.from(vm.allTournaments);
    final selectedTournament = vm.selectedTournament;
    final initializingTournament = _findTournamentById(
      tournaments,
      _initializingTournamentId,
    );

    final index = _tabController.index;
    final Map<String, dynamic>? switcherTournament = index == 1
        ? selectedTournament
        : (_showInitializationTab && index == 2
            ? (initializingTournament ?? selectedTournament)
            : null);
    final bottomHeight = switcherTournament == null ? 48.0 : 104.0;
    final headerImage = _headerImageProvider(selectedTournament);
    final headerName = selectedTournament?['name']?.toString() ?? 'Turniere';

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverOverlapAbsorber(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                      context,
                    ),
                    sliver: SliverAppBar(
                      expandedHeight: 280,
                      floating: false,
                      pinned: true,
                      backgroundColor: Colors.white,
                      elevation: 1,
                      iconTheme: const IconThemeData(color: Colors.black87),
                      flexibleSpace: LayoutBuilder(
                        builder: (context, constraints) {
                          final safeAreaTop = MediaQuery.of(context).padding.top;
                          final screenWidth = MediaQuery.of(context).size.width;
                          final collapsedHeight =
                              kToolbarHeight + bottomHeight + safeAreaTop;
                          const expandedHeight = 280.0;
                          final currentHeight = constraints.maxHeight;
                          final radius = (screenWidth * 0.14)
                              .clamp(40.0, _headerImageRadius)
                              .toDouble();

                          var fade = 1.0;
                          if (expandedHeight > collapsedHeight) {
                            fade = (currentHeight - collapsedHeight) /
                                (expandedHeight - collapsedHeight);
                            fade = fade.clamp(0.0, 1.0).toDouble();
                          }

                          return Container(
                            color: Colors.white,
                            child: Stack(
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
                                          CircleAvatar(
                                            radius: radius,
                                            backgroundColor:
                                                primaryColor.withOpacity(0.1),
                                            backgroundImage: headerImage,
                                            child: headerImage == null
                                                ? Icon(
                                                    Icons.emoji_events,
                                                    size: radius,
                                                    color: primaryColor,
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            headerName,
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Turnierauswahl',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: safeAreaTop,
                                  left: Navigator.canPop(context) ? 64 : 16,
                                  right: 16,
                                  height: kToolbarHeight,
                                  child: IgnorePointer(
                                    ignoring: fade > 0.5,
                                    child: Opacity(
                                      opacity: 1 - fade,
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: _collapsedImageRadius,
                                            backgroundColor:
                                                primaryColor.withOpacity(0.1),
                                            backgroundImage: headerImage,
                                            child: headerImage == null
                                                ? Icon(
                                                    Icons.emoji_events,
                                                    size: _collapsedImageRadius,
                                                    color: primaryColor,
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  headerName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                    color: Colors.black87,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  'Turnierauswahl',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
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
                                tabs: [
                                  const Tab(text: 'Turniere'),
                                  const Tab(text: 'Liga'),
                                  if (_showInitializationTab)
                                    const Tab(text: 'Initialisierung'),
                                ],
                              ),
                              if (switcherTournament != null)
                                _buildTournamentSwitcherRow(
                                  tournament: switcherTournament,
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
                behavior:
                    ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTournamentTab(primaryColor),
                    _buildLeagueTab(primaryColor),
                    if (_showInitializationTab)
                      _buildInitializationTab(primaryColor),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTournamentTab(Color primaryColor) {
    final vm = context.watch<TournamentViewModel>();
    final allTournaments =
        List<Map<String, dynamic>>.from(vm.allTournaments);
    final selectedTournamentId = vm.currentTournamentId;
    final filtered = filterTournaments(
      tournaments: allTournaments,
      query: _searchQuery,
      gender: _genderFilterValue,
    );
    final countryGroups = groupTournamentsByAssociationRanking(filtered);

    return Builder(
      builder: (context) => CustomScrollView(
        key: const PageStorageKey<String>('tournamentTab'),
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildTournamentSearch(primaryColor),
                const SizedBox(height: 14),
                if (allTournaments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(child: Text('Keine Turniere verfügbar.')),
                  )
                else if (countryGroups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Center(
                      child: Text(
                        'Keine passenden Ligen gefunden.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  )
                else
                  ...countryGroups.map(
                    (group) => _buildCountrySection(
                      group: group,
                      selectedTournamentId: selectedTournamentId,
                      primaryColor: primaryColor,
                      vm: vm,
                    ),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTournamentSearch(Color primaryColor) {
    final filterActive = _genderFilter != _TournamentGenderFilter.all;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Land oder Liga suchen',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Suche löschen',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: primaryColor, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: _genderFilterTooltip,
          child: Material(
            color: filterActive
                ? primaryColor.withOpacity(0.12)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: _cycleGenderFilter,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: filterActive
                        ? primaryColor.withOpacity(0.45)
                        : Colors.grey.shade300,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _genderFilterIcon,
                  color: filterActive ? primaryColor : Colors.grey.shade700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountrySection({
    required LeagueCountryGroup group,
    required int? selectedTournamentId,
    required Color primaryColor,
    required TournamentViewModel vm,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 6, top: 6),
          child: Text(
            group.displayCountry,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
              fontSize: 12,
              letterSpacing: 0.2,
            ),
          ),
        ),
        ...group.tournaments.map(
          (tournament) => _buildTournamentCard(
            tournament: tournament,
            selectedTournamentId: selectedTournamentId,
            primaryColor: primaryColor,
            vm: vm,
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildTournamentCard({
    required Map<String, dynamic> tournament,
    required int? selectedTournamentId,
    required Color primaryColor,
    required TournamentViewModel vm,
  }) {
    final latest = _latestSeason(tournament);
    final isSelected = tournament['id'] == selectedTournamentId;
    final isInitializationFocus =
        tournament['id'] == _initializingTournamentId &&
            _showInitializationTab;
    final isInitialized = latest?['is_initialized'] == true;
    final isInitializing = latest?['is_active'] == true && !isInitialized;
    final latestName = latest?['name']?.toString();
    final subtitle = latest == null
        ? 'Noch keine Saison entdeckt'
        : 'Neueste Saison $latestName · '
            '${TournamentViewModel.seasonStatus(latest)}';

    return Card(
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
        leading: LeagueLogo(
          imageUrl: tournament['image_url'] as String?,
          radius: 20,
        ),
        title: Text(
          tournament['name']?.toString() ?? 'Turnier',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: latest == null
            ? const Icon(Icons.info_outline)
            : isInitializing || isInitializationFocus
                ? Icon(Icons.hourglass_top, color: Colors.orange.shade700)
                : isSelected
                    ? Icon(Icons.check_circle, color: primaryColor)
                    : const Icon(Icons.chevron_right),
        onTap: latest == null
            ? null
            : () async {
                if (isInitializing) {
                  _openInitializationTab(tournament);
                  return;
                }
                if (!isInitialized) {
                  await _showInitializeDialog(tournament);
                  return;
                }
                await _selectLatestTournamentAndReturn(vm, tournament);
              },
      ),
    );
  }

  Widget _buildLeagueTab(Color primaryColor) {
    final vm = context.watch<TournamentViewModel>();
    final tournament = vm.selectedTournament;

    return Builder(
      builder: (context) {
        if (tournament == null) {
          return CustomScrollView(
            key: const PageStorageKey<String>('leagueInfoTabEmpty'),
            slivers: [
              SliverOverlapInjector(
                handle:
                    NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              ),
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Keine Liga ausgewählt.')),
              ),
            ],
          );
        }

        final seasons = managerSeasons(tournament['season']);
        final latest = seasons.isEmpty ? null : seasons.first;
        final selected = vm.selectedSeason;
        final archives = seasons
            .where(
              (season) =>
                  season['id'] != latest?['id'] &&
                  season['is_initialized'] == true,
            )
            .toList();
        final country = displayTournamentCountry(
          tournament['country_name']?.toString(),
        );
        final gender = tournamentGender(tournament) == 'F' ? 'Frauen' : 'Männer';
        final tier = tournamentTier(tournament);
        final coefficient = tournamentAssociationCoefficient(tournament);

        return CustomScrollView(
          key: const PageStorageKey<String>('leagueInfoTab'),
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const _SectionTitle('ALLGEMEIN'),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: LeagueLogo(
                            imageUrl: tournament['image_url'] as String?,
                            radius: 20,
                          ),
                          title: const Text('Liga'),
                          subtitle: Text(
                            tournament['name']?.toString() ?? 'Turnier',
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.public_outlined),
                          title: const Text('Ligaland'),
                          trailing: Text(
                            country,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            tournamentGender(tournament) == 'F'
                                ? Icons.female
                                : Icons.male,
                          ),
                          title: const Text('Kategorie'),
                          trailing: Text(
                            gender,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.format_list_numbered),
                          title: const Text('Ligastufe'),
                          trailing: Text(
                            '$tier',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.leaderboard_outlined),
                          title: const Text('Länderkoeffizient'),
                          trailing: Text(
                            coefficient.toStringAsFixed(3),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.new_releases_outlined),
                          title: const Text('Neueste Saison'),
                          trailing: Text(
                            latest?['name']?.toString() ?? '–',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.visibility_outlined),
                          title: const Text('Angezeigte Saison'),
                          trailing: Text(
                            selected?['name']?.toString() ?? '–',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.archive_outlined),
                          title: const Text('Archivierte Saisons'),
                          trailing: Text(
                            '${archives.length}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _SectionTitle('SAISONAUSWAHL'),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: seasons.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Keine Saison verfügbar.'),
                          )
                        : Column(
                            children: [
                              for (var index = 0;
                                  index < seasons.length;
                                  index++) ...[
                                _buildSeasonTile(
                                  vm: vm,
                                  tournament: tournament,
                                  season: seasons[index],
                                  latestSeasonId: latest?['id'] as int?,
                                  primaryColor: primaryColor,
                                ),
                                if (index < seasons.length - 1)
                                  const Divider(height: 1),
                              ],
                            ],
                          ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Vergangene, bereits initialisierte Saisons werden als '
                      'Archiv geladen. Neue Initialisierungen erfolgen ausschließlich '
                      'für die neueste Saison über den Tab „Turniere“.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSeasonTile({
    required TournamentViewModel vm,
    required Map<String, dynamic> tournament,
    required Map<String, dynamic> season,
    required int? latestSeasonId,
    required Color primaryColor,
  }) {
    final seasonId = season['id'] as int?;
    final isLatest = seasonId == latestSeasonId;
    final isSelected = seasonId == vm.currentSeasonId;
    final isInitialized = season['is_initialized'] == true;

    return ListTile(
      leading: Icon(
        isLatest ? Icons.calendar_month : Icons.history,
        color: isSelected ? primaryColor : null,
      ),
      title: Row(
        children: [
          Flexible(child: Text('Saison ${season['name']}')),
          if (isLatest) ...[
            const SizedBox(width: 8),
            _buildBadge('NEUESTE', primaryColor),
          ],
        ],
      ),
      subtitle: Text(TournamentViewModel.seasonStatus(season)),
      selected: isSelected,
      selectedColor: primaryColor,
      trailing: isSelected
          ? Icon(Icons.check_circle, color: primaryColor)
          : isInitialized
              ? const Icon(Icons.chevron_right)
              : const Icon(Icons.lock_outline),
      onTap: !isInitialized || isSelected
          ? null
          : () => _selectSeasonAndReturn(vm, tournament, season),
    );
  }

  Widget _buildInitializationTab(Color primaryColor) {
    return Builder(
      builder: (context) => CustomScrollView(
        key: const PageStorageKey<String>('initializationTab'),
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            sliver: SliverToBoxAdapter(
              child: _buildInitializationContent(primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitializationContent(Color primaryColor) {
    final seasonId = _initializingSeasonId;
    if (seasonId == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Keine Initialisierung ausgewählt.'),
        ),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: supabase
          .from('sync_tasks')
          .stream(primaryKey: const ['id'])
          .eq('season_id', seasonId)
          .order('created_at'),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        final failed = rows.where((row) => _taskStatus(row) == 'FAILED').length;
        final processing =
            rows.where((row) => _taskStatus(row) == 'PROCESSING').length;
        final completed =
            rows.where((row) => _taskStatus(row) == 'COMPLETED').length;
        final taskProgress = rows.isEmpty ? 0.0 : completed / rows.length;
        final progress = math
            .max(_initializationProgress, taskProgress)
            .clamp(0.0, 1.0)
            .toDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isInitializingSeason
                              ? Icons.autorenew
                              : Icons.sync_alt,
                          color: primaryColor,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Initialisierung',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text('${(progress * 100).round()} %'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(_initializationStatus),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const _SectionTitle('SYNC-TASKS'),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.task_alt),
                    title: const Text('Abgeschlossen'),
                    trailing: Text('$completed'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.sync, color: primaryColor),
                    title: const Text('In Bearbeitung'),
                    trailing: Text('$processing'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.error_outline,
                      color: failed == 0 ? Colors.grey : Colors.red,
                    ),
                    title: const Text('Fehlgeschlagen'),
                    trailing: Text('$failed'),
                  ),
                ],
              ),
            ),
            if (snapshot.hasError) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.red.shade50,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Fehler beim Laden der sync_tasks.'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _taskStatus(Map<String, dynamic> row) =>
      (row['status'] ?? '').toString().toUpperCase();

  Widget _buildTournamentSwitcherRow({
    required Map<String, dynamic> tournament,
  }) {
    return InkWell(
      onTap: () => _tabController.animateTo(0),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
        ),
        child: Row(
          children: [
            LeagueLogo(
              imageUrl: tournament['image_url'] as String?,
              radius: 16,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tournament['name']?.toString() ?? 'Turnier',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black87,
                ),
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

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8, top: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
