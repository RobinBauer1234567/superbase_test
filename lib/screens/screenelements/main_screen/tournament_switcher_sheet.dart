import 'package:flutter/material.dart';
import 'package:premier_league/screens/screenelements/league_logo.dart';
import 'package:premier_league/screens/screenelements/main_screen/tournament_init_screen.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TournamentSwitcherScreen extends StatefulWidget {
  const TournamentSwitcherScreen({super.key});

  @override
  State<TournamentSwitcherScreen> createState() => _TournamentSwitcherScreenState();
}

class _TournamentSwitcherScreenState extends State<TournamentSwitcherScreen>
    with SingleTickerProviderStateMixin {
  static const double _headerImageRadius = 48;
  static const double _collapsedImageRadius = 16;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showInitDialog(
    BuildContext context,
    Map<String, dynamic> season,
    String tournamentName,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Liga initialisieren?'),
        content: Text(
          'Möchtest du die Saison ${season['name']} für $tournamentName jetzt initialisieren? '
          'Das lädt alle Teams, Kader und Spieltage aus dem Internet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);

              await Supabase.instance.client
                  .from('season')
                  .update({'is_active': true})
                  .eq('id', season['id']);

              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TournamentInitScreen(
                    seasonId: season['id'],
                    tournamentName: tournamentName,
                  ),
                ),
              );
            },
            child: const Text('Ja, starten'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<TournamentViewModel>();
    final primaryColor = Theme.of(context).primaryColor;
    final selectedSeason = viewModel.selectedSeason;

    final bool showTournamentRow = _tabController.index != 0 &&
        viewModel.selectedTournament != null &&
        selectedSeason != null;
    final double bottomHeight = showTournamentRow ? 104.0 : 48.0;

    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          color: Colors.grey.shade100,
          child: viewModel.isLoading
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
                          pinned: true,
                          floating: false,
                          backgroundColor: Colors.white,
                          automaticallyImplyLeading: false,
                          surfaceTintColor: Colors.white,
                          elevation: 1,
                          title: const Text(
                            'Turnier-Hub',
                            style: TextStyle(color: Colors.black87),
                          ),
                          actions: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close, color: Colors.black87),
                            ),
                          ],
                          flexibleSpace: LayoutBuilder(
                            builder: (context, constraints) {
                              final safeAreaTop = MediaQuery.of(context).padding.top;
                              final screenWidth = MediaQuery.of(context).size.width;
                              final collapsedHeight =
                                  kToolbarHeight + bottomHeight + safeAreaTop;
                              final currentHeight = constraints.maxHeight;
                              final avatarRadius =
                                  (screenWidth * 0.13).clamp(38.0, _headerImageRadius);

                              double fade = 1.0;
                              if (280 > collapsedHeight) {
                                fade =
                                    (currentHeight - collapsedHeight) /
                                        (280 - collapsedHeight);
                                fade = fade.clamp(0.0, 1.0);
                              }

                              return Container(
                                color: Colors.white,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Positioned(
                                      top: safeAreaTop + 20,
                                      left: 0,
                                      right: 0,
                                      child: IgnorePointer(
                                        ignoring: fade < 0.5,
                                        child: Opacity(
                                          opacity: fade,
                                          child: Column(
                                            children: [
                                              LeagueLogo(
                                                imageUrl: viewModel.currentTournamentLogo,
                                                radius: avatarRadius,
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                viewModel.currentTournamentName,
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              if (selectedSeason != null)
                                                Text(
                                                  'Saison ${selectedSeason['name']}',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey.shade700,
                                                  ),
                                                ),
                                              const SizedBox(height: 10),
                                              if (selectedSeason != null)
                                                Wrap(
                                                  spacing: 8,
                                                  children: [
                                                    _buildStatusChip(
                                                      'Aktiv',
                                                      selectedSeason['is_active'] == true,
                                                      Colors.green,
                                                    ),
                                                    _buildStatusChip(
                                                      'Initialisiert',
                                                      selectedSeason['is_initialized'] == true,
                                                      Colors.blue,
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: safeAreaTop,
                                      left: 16,
                                      right: 68,
                                      height: kToolbarHeight,
                                      child: IgnorePointer(
                                        ignoring: fade > 0.5,
                                        child: Opacity(
                                          opacity: 1 - fade,
                                          child: Row(
                                            children: [
                                              LeagueLogo(
                                                imageUrl: viewModel.currentTournamentLogo,
                                                radius: _collapsedImageRadius,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      viewModel.currentTournamentName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.black87,
                                                      ),
                                                    ),
                                                    if (selectedSeason != null)
                                                      Text(
                                                        'Saison ${selectedSeason['name']}',
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
                                    labelColor: primaryColor,
                                    unselectedLabelColor: Colors.grey,
                                    indicatorColor: primaryColor,
                                    tabs: const [
                                      Tab(text: 'Verfügbar'),
                                      Tab(text: 'Aktiv'),
                                    ],
                                  ),
                                  if (showTournamentRow)
                                    _buildSelectedTournamentRow(
                                      context,
                                      viewModel,
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
                    behavior: ScrollConfiguration.of(context).copyWith(
                      scrollbars: false,
                    ),
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTournamentList(
                          context,
                          viewModel,
                          showOnlyActive: false,
                        ),
                        _buildTournamentList(
                          context,
                          viewModel,
                          showOnlyActive: true,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSelectedTournamentRow(
    BuildContext context,
    TournamentViewModel viewModel,
  ) {
    return InkWell(
      onTap: () => _tabController.animateTo(0),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            LeagueLogo(imageUrl: viewModel.currentTournamentLogo, radius: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                viewModel.currentTournamentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
            ),
            const Icon(Icons.swap_horiz, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildTournamentList(
    BuildContext context,
    TournamentViewModel viewModel, {
    required bool showOnlyActive,
  }) {
    final displayTournaments = showOnlyActive
        ? viewModel.allTournaments.where((tournament) {
            final seasons = List<Map<String, dynamic>>.from(
              tournament['season'] ?? [],
            );
            if (seasons.isEmpty) return false;
            return seasons.last['is_initialized'] == true;
          }).toList()
        : viewModel.allTournaments;

    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          key: PageStorageKey<String>(
            showOnlyActive ? 'activeTournamentsTab' : 'allTournamentsTab',
          ),
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            if (displayTournaments.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    showOnlyActive
                        ? 'Keine aktiven Turniere gefunden.'
                        : 'Keine Turniere gefunden.',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final tournament = displayTournaments[index];
                    final seasons = List<Map<String, dynamic>>.from(
                      tournament['season'] ?? [],
                    );
                    if (seasons.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    final currentSeason = seasons.last;
                    final bool isActive = currentSeason['is_active'] == true;
                    final bool isInitialized =
                        currentSeason['is_initialized'] == true;
                    final bool isCurrentlySelected =
                        tournament['id'] == viewModel.currentTournamentId;

                    return Card(
                      elevation: isCurrentlySelected ? 2 : 1,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: isCurrentlySelected
                            ? BorderSide(
                                color: Theme.of(context)
                                    .primaryColor
                                    .withOpacity(0.45),
                                width: 1.5,
                              )
                            : BorderSide.none,
                      ),
                      color: Colors.white,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          if (isActive && isInitialized) {
                            viewModel.selectTournament(
                              tournament['id'],
                              currentSeason['id'],
                            );
                            Navigator.pop(context);
                          } else {
                            _showInitDialog(
                              context,
                              currentSeason,
                              tournament['name'],
                            );
                          }
                        },
                        child: Opacity(
                          opacity: (isActive && isInitialized) ? 1 : 0.55,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                LeagueLogo(
                                  imageUrl: tournament['image_url'],
                                  radius: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tournament['name'],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Saison ${currentSeason['name']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          _buildStatusChip(
                                            'Aktiv',
                                            isActive,
                                            Colors.green,
                                            compact: true,
                                          ),
                                          _buildStatusChip(
                                            'Initialisiert',
                                            isInitialized,
                                            Colors.blue,
                                            compact: true,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isInitialized)
                                  const Icon(
                                    Icons.download_rounded,
                                    color: Colors.blue,
                                  )
                                else if (isCurrentlySelected)
                                  Icon(
                                    Icons.check_circle,
                                    color: Theme.of(context).primaryColor,
                                  )
                                else
                                  const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }, childCount: displayTournaments.length),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildStatusChip(
    String label,
    bool isEnabled,
    Color activeColor, {
    bool compact = false,
  }) {
    final color = isEnabled ? activeColor : Colors.grey;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isEnabled ? Icons.check_circle : Icons.cancel,
            color: color,
            size: compact ? 12 : 14,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 11 : 12,
            ),
          ),
        ],
      ),
    );
  }
}
