// lib/screens/league/league_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:premier_league/screens/leagues/ranking_screen.dart';
import 'dart:math';
import 'package:premier_league/screens/leagues/league_team_screen.dart';
import 'package:premier_league/screens/leagues/transfer_market_screen.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/leagues/activity_feed_tab.dart';

class LeagueDetailScreen extends StatefulWidget {
  final Map<String, dynamic> league;
  const LeagueDetailScreen({super.key, required this.league});

  @override
  State<LeagueDetailScreen> createState() => _LeagueDetailScreenState();
}

class _LeagueDetailScreenState extends State<LeagueDetailScreen> {
  bool get _isFinished => widget.league['finished_at'] != null;

  @override
  void initState() {
    super.initState();

    // A finished league is a permanent read-only archive. Do not send the
    // activity ping that normally wakes an idle league up again.
    if (!_isFinished) {
      final int leagueId = widget.league['id'];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final service =
            Provider.of<DataManagement>(context, listen: false).supabaseService;
        service.updateLeagueActivity(leagueId);
      });
    }
  }

  Widget _buildClosedMarket() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_clock_outlined, size: 52),
            SizedBox(height: 16),
            Text(
              'Saison beendet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Text(
              'Diese Liga ist jetzt ein Archiv. Der Transfermarkt ist geschlossen; '
              'Team, Aktivitäten und Rangliste bleiben weiterhin einsehbar.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double tabFontSize = max(5, min(screenWidth / 45, 15));

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: _isFinished ? null : 0,
          title: _isFinished
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.archive_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Liga beendet'),
                  ],
                )
              : null,
          bottom: TabBar(
            isScrollable: false,
            tabs: const [
              Tab(text: 'AKTIVITÄTEN'),
              Tab(text: 'TRANSFERMARKT'),
              Tab(text: 'TEAM'),
              Tab(text: 'RANKING'),
            ],
            labelStyle: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: tabFontSize,
            ),
            unselectedLabelStyle: TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: tabFontSize,
            ),
          ),
        ),
        body: TabBarView(
          children: [
            ActivityFeedTab(leagueId: widget.league['id']),
            _isFinished
                ? _buildClosedMarket()
                : TransferMarketScreen(leagueId: widget.league['id']),
            LeagueTeamScreen(leagueId: widget.league['id']),
            RankingScreen(leagueId: widget.league['id']),
          ],
        ),
      ),
    );
  }
}
