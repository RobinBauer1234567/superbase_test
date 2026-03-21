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
  static const double _headerImageRadius = 50;
  static const double _collapsedImageRadius = 18;

  late TabController _tabController;
  int _previousTabIndex = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
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

    const bool showTournamentRow = true;
    final double bottomHeight = showTournamentRow ? 104.0 : 48.0;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar(
                expandedHeight: 320,
                floating: false,
                pinned: true,
                backgroundColor: Colors.white,
                elevation: 1,
                iconTheme: const IconThemeData(color: Colors.black87),
                flexibleSpace: LayoutBuilder(
                  builder: (context, constraints) {
                    final double safeAreaTop = MediaQuery.of(context).padding.top;
                    final double screenWidth = MediaQuery.of(context).size.width;
                    final double collapsedHeight =
                        kToolbarHeight + bottomHeight + safeAreaTop;
                    final double expandedHeight = 320.0;
                    final double currentHeight = constraints.maxHeight;
                    final double logoRadius =
                        (screenWidth * 0.14).clamp(40.0, _headerImageRadius);

                    double fade = 1.0;
                    if (expandedHeight > collapsedHeight) {
                      fade =
                          (currentHeight - collapsedHeight) /
                          (expandedHeight - collapsedHeight);
                      fade = fade.clamp(0.0, 1.0);
                    }

                    final seasonName = viewModel.selectedSeason?['name'] ?? '-';

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
                                      radius: logoRadius,
                                      backgroundColor: Colors.grey.shade200,
                                      child: LeagueLogo(
                                        imageUrl: viewModel.currentTournamentLogo,
                                        radius: logoRadius,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      viewModel.currentTournamentName,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Saison $seasonName',
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
                            left: Navigator.canPop(context) ? 64.0 : 16.0,
                            right: 60,
                            height: kToolbarHeight,
                            child: IgnorePointer(
                              ignoring: fade > 0.5,
                              child: Opacity(
                                opacity: 1.0 - fade,
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: _collapsedImageRadius,
                                      backgroundColor: Colors.grey.shade200,
                                      child: LeagueLogo(
                                        imageUrl: viewModel.currentTournamentLogo,
                                        radius: _collapsedImageRadius,
                                      ),
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
                                            viewModel.currentTournamentName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Colors.black87,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            'Saison $seasonName',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
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
                          tabs: const [
                            Tab(text: 'Turniere'),
                            Tab(text: 'Aktiv'),
                          ],
                        ),
                        _buildSelectedTournamentRow(viewModel),
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
            children: [
              _buildTournamentTab(context, viewModel, showOnlyActive: false),
              _buildTournamentTab(context, viewModel, showOnlyActive: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedTournamentRow(TournamentViewModel viewModel) {
    return InkWell(
      onTap: () {
        _previousTabIndex = _tabController.index;
        _tabController.animateTo(0);
      },
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
            LeagueLogo(imageUrl: viewModel.currentTournamentLogo, radius: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                viewModel.currentTournamentName,
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

  Widget _buildTournamentTab(
    BuildContext context,
    TournamentViewModel viewModel, {
    required bool showOnlyActive,
  }) {
    final primaryColor = Theme.of(context).primaryColor;
    final allTournaments = viewModel.allTournaments;

    final displayTournaments =
        showOnlyActive
            ? allTournaments.where((t) {
              final seasons = List<Map<String, dynamic>>.from(t['season'] ?? []);
              if (seasons.isEmpty) return false;
              return seasons.last['is_initialized'] == true;
            }).toList()
            : allTournaments;

    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          key: PageStorageKey<String>(
            showOnlyActive ? 'tournamentsActiveTab' : 'tournamentsAllTab',
          ),
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            if (displayTournaments.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Keine Turniere gefunden.')),
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
                    if (seasons.isEmpty) return const SizedBox.shrink();

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
                        side:
                            isCurrentlySelected
                                ? BorderSide(
                                  color: primaryColor.withOpacity(0.5),
                                  width: 1.5,
                                )
                                : BorderSide.none,
                      ),
                      color: Colors.white,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            LeagueLogo(imageUrl: tournament['image_url'], radius: 20),
                            Positioned(
                              right: -4,
                              bottom: -4,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color:
                                      isActive && isInitialized
                                          ? Colors.green
                                          : Colors.grey,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    isActive && isInitialized
                                        ? Icons.check
                                        : Icons.close,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          tournament['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          'Saison ${currentSeason['name']}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        trailing:
                            !isInitialized
                                ? const Icon(
                                  Icons.download_rounded,
                                  color: Colors.blue,
                                )
                                : isCurrentlySelected
                                ? Icon(
                                  Icons.check_circle,
                                  color: primaryColor,
                                )
                                : const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                        onTap: () {
                          if (isActive && isInitialized) {
                            viewModel.selectTournament(
                              tournament['id'],
                              currentSeason['id'],
                            );
                            final targetTab =
                                _previousTabIndex != 0 ? _previousTabIndex : 1;
                            _tabController.animateTo(targetTab);
                            Navigator.pop(context);
                          } else {
                            _showInitDialog(
                              context,
                              currentSeason,
                              tournament['name'],
                            );
                          }
                        },
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
}
