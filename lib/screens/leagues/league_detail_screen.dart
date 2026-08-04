// lib/screens/league/league_detail_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/screens/leagues/activity_feed_tab.dart';
import 'package:premier_league/screens/leagues/league_settings_screen.dart';
import 'package:premier_league/screens/leagues/league_team_screen.dart';
import 'package:premier_league/screens/leagues/ranking_screen.dart';
import 'package:premier_league/screens/leagues/transfer_market_screen.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';

class LeagueDetailScreen extends StatefulWidget {
  final Map<String, dynamic> league;

  const LeagueDetailScreen({super.key, required this.league});

  @override
  State<LeagueDetailScreen> createState() => _LeagueDetailScreenState();
}

class _LeagueDetailScreenState extends State<LeagueDetailScreen> {
  @override
  void initState() {
    super.initState();
    final int leagueId = (widget.league['id'] as num).toInt();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final service = Provider.of<DataManagement>(context, listen: false)
          .supabaseService;
      service.updateLeagueActivity(leagueId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double tabFontSize = max(5.0, min(screenWidth / 45, 15.0));
    final int leagueId = (widget.league['id'] as num).toInt();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 44,
          title: Text(
            widget.league['name']?.toString() ?? 'Liga',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              tooltip: 'Liga-Einstellungen',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LeagueSettingsScreen(leagueId: leagueId),
                  ),
                );
              },
            ),
          ],
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
            ActivityFeedTab(leagueId: leagueId),
            TransferMarketScreen(leagueId: leagueId),
            LeagueTeamScreen(leagueId: leagueId),
            RankingScreen(leagueId: leagueId),
          ],
        ),
      ),
    );
  }
}
