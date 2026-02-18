// lib/screens/league/league_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:premier_league/screens/leagues/ranking_screen.dart';
import 'dart:math'; // Import für die 'max'-Funktion
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
  @override
  void initState() {
    super.initState();

    // Die ID einfach aus dem übergebenen Liga-Objekt auslesen
    final int leagueId = widget.league['id'];

    // Nach dem ersten Frame den Ping an die Datenbank schicken
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = Provider.of<DataManagement>(context, listen: false).supabaseService;
      service.updateLeagueActivity(leagueId);
    });
  }
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    final double tabFontSize = max(5, min(screenWidth / 45, 15));

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 0,
          bottom: TabBar(
            tabs: const [
              Tab(text: 'AKTIVITÄTEN'),
              Tab(text: 'TRANSFERMARKT'),
              Tab(text: 'TEAM'),
              Tab(text: 'RANKING'),
            ],
            // 3. Die dynamische Schriftgröße anwenden
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: tabFontSize),
            unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, fontSize: tabFontSize),
          ),
        ),
        body: TabBarView(
          children: [
            ActivityFeedTab(leagueId: widget.league['id']),
            TransferMarketScreen(leagueId: widget.league['id']),
            LeagueTeamScreen(leagueId: widget.league['id']), // Statt Text-Placeholder
            RankingScreen(leagueId: widget.league['id']),
          ],
        ),
      ),
    );
  }
}
