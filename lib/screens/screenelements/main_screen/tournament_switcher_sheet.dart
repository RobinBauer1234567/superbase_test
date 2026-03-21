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

class _TournamentSwitcherScreenState extends State<TournamentSwitcherScreen> with SingleTickerProviderStateMixin {
  static const double _headerLogoRadius = 50;
  static const double _collapsedLogoRadius = 18;

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

  void _showInitDialog(BuildContext context, Map<String, dynamic> season, String tournamentName) {
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

              await Supabase.instance.client.from('season').update({'is_active': true}).eq('id', season['id']);

              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TournamentInitScreen(
                      seasonId: season['id'],
                      tournamentName: tournamentName,
                    ),
                  ),
                );
              }
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

    final bool showCurrentTournamentRow = _tabController.index != 0 && viewModel.currentTournamentId != null;
    final double bottomHeight = showCurrentTournamentRow ? 104.0 : 48.0;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: viewModel.isLoading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverOverlapAbsorber(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                    sliver: SliverAppBar(
                      expandedHeight: 310,
                      pinned: true,
                      floating: false,
                      backgroundColor: Colors.white,
                      elevation: 1,
                      iconTheme: const IconThemeData(color: Colors.black87),
                      flexibleSpace: LayoutBuilder(
                        builder: (context, constraints) {
                          final safeAreaTop = MediaQuery.of(context).padding.top;
                          final screenWidth = MediaQuery.of(context).size.width;
                          final collapsedHeight = kToolbarHeight + bottomHeight + safeAreaTop;
                          const expandedHeight = 310.0;
                          final currentHeight = constraints.maxHeight;
                          final logoRadius = (screenWidth * 0.14).clamp(40.0, _headerLogoRadius);

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
                                            child: LeagueLogo(imageUrl: viewModel.currentTournamentLogo, radius: logoRadius),
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
                                          const SizedBox(height: 4),
                                          Text(
                                            'Saison ${viewModel.selectedSeason?['name'] ?? '-'}',
                                            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: safeAreaTop,
                                  left: Navigator.canPop(context) ? 64.0 : 16.0,
                                  right: 16,
                                  height: kToolbarHeight,
                                  child: IgnorePointer(
                                    ignoring: fade > 0.5,
                                    child: Opacity(
                                      opacity: 1 - fade,
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: _collapsedLogoRadius,
                                            backgroundColor: Colors.grey.shade200,
                                            child: LeagueLogo(
                                              imageUrl: viewModel.currentTournamentLogo,
                                              radius: _collapsedLogoRadius,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                                Text(
                                                  'Saison ${viewModel.selectedSeason?['name'] ?? '-'}',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                                  Tab(text: 'Verfügbar'),
                                  Tab(text: 'Aktiv'),
                                ],
                              ),
                              if (showCurrentTournamentRow)
                                _buildCurrentTournamentRow(viewModel, primaryColor),
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
                    _buildTournamentList(context, viewModel, showOnlyActive: false),
                    _buildTournamentList(context, viewModel, showOnlyActive: true),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildCurrentTournamentRow(TournamentViewModel viewModel, Color primaryColor) {
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
            LeagueLogo(imageUrl: viewModel.currentTournamentLogo, radius: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                viewModel.currentTournamentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
              ),
            ),
            Icon(Icons.swap_horiz, color: primaryColor),
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
    final allTournaments = viewModel.allTournaments;
    final displayTournaments = showOnlyActive
        ? allTournaments.where((tournament) {
            final seasons = List<Map<String, dynamic>>.from(tournament['season'] ?? []);
            if (seasons.isEmpty) return false;
            return seasons.last['is_initialized'] == true;
          }).toList()
        : allTournaments;

    return Builder(
      builder: (BuildContext context) {
        return CustomScrollView(
          key: PageStorageKey<String>(showOnlyActive ? 'activeTournamentTab' : 'availableTournamentTab'),
          slivers: [
            SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
            if (displayTournaments.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Keine Turniere gefunden.')),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final tournament = displayTournaments[index];
                      final seasons = List<Map<String, dynamic>>.from(tournament['season'] ?? []);
                      if (seasons.isEmpty) return const SizedBox.shrink();

                      final currentSeason = seasons.last;
                      final bool isActive = currentSeason['is_active'] == true;
                      final bool isInitialized = currentSeason['is_initialized'] == true;
                      final bool isCurrentlySelected = tournament['id'] == viewModel.currentTournamentId;
                      final statusColor = !isInitialized
                          ? Colors.blue
                          : isActive
                              ? Colors.green
                              : Colors.orange;

                      return Card(
                        elevation: isCurrentlySelected ? 2 : 1,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: isCurrentlySelected
                              ? BorderSide(color: Theme.of(context).primaryColor.withOpacity(0.5), width: 1.5)
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
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: Icon(
                                    !isInitialized ? Icons.download_rounded : (isActive ? Icons.play_arrow_rounded : Icons.pause),
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          title: Text(
                            tournament['name'],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          subtitle: Text(
                            'Saison ${currentSeason['name']} • ${isInitialized ? 'Initialisiert' : 'Nicht initialisiert'}',
                          ),
                          trailing: isCurrentlySelected
                              ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
                              : const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                          onTap: () {
                            if (isActive && isInitialized) {
                              viewModel.selectTournament(tournament['id'], currentSeason['id']);
                              Navigator.pop(context);
                              return;
                            }
                            _showInitDialog(context, currentSeason, tournament['name']);
                          },
                        ),
                      );
                    },
                    childCount: displayTournaments.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
