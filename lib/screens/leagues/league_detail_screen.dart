// lib/screens/league/league_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:premier_league/screens/leagues/ranking_screen.dart';
import 'dart:math'; // Import für die 'max'-Funktion
import 'package:premier_league/screens/leagues/league_team_screen.dart';

class LeagueDetailScreen extends StatefulWidget {
  final Map<String, dynamic> league;
  const LeagueDetailScreen({super.key, required this.league});

  @override
  State<LeagueDetailScreen> createState() => _LeagueDetailScreenState();
}

class _LeagueDetailScreenState extends State<LeagueDetailScreen> {
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
            const Center(child: Text('Hier erscheinen bald die letzten Aktivitäten der Liga.')),
            const Center(child: Text('Hier wird der Transfermarkt angezeigt.')),
            LeagueTeamScreen(leagueId: widget.league['id']), // Statt Text-Placeholder
            RankingScreen(leagueId: widget.league['id']),
          ],
        ),
      ),
    );
  }
}
