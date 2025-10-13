// lib/screens/premier_league/premier_league_screen.dart
import 'package:flutter/material.dart';
import 'package:premier_league/screens/premier_league/matches_screen.dart';
import 'package:premier_league/screens/premier_league/table_screen.dart';
import 'package:premier_league/screens/premier_league/top_team_screen.dart'; // Importiert

class PremierLeagueScreen extends StatelessWidget {
  const PremierLeagueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'BEGEGNUNGEN'),
              Tab(text: 'TABELLE'),
              Tab(text: 'TOP-TEAM'),
            ],
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal),
          ),
        ),
        body: const TabBarView(
          children: [
            MatchesScreen(),
            TableScreen(),
            TopTeamScreen(), // Platzhalter ersetzt
          ],
        ),
      ),
    );
  }
}