// lib/screens/premier_league/premier_league_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:premier_league/screens/leagues/league_settings_screen.dart';
import 'package:premier_league/screens/premier_league/matches_screen.dart';
import 'package:premier_league/screens/premier_league/table_screen.dart';
import 'package:premier_league/screens/premier_league/top_team_screen.dart';

class PremierLeagueScreen extends StatelessWidget {
  const PremierLeagueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double tabFontSize = max(5.0, min(screenWidth / 45, 15));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 44,
          title: const Text(
            'Turnier',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              tooltip: 'Turniere und Initialisierung',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => const LeagueSettingsScreen(
                      isTournamentTab: true,
                    ),
                  ),
                );
              },
            ),
          ],
          bottom: TabBar(
            tabs: const [
              Tab(text: 'BEGEGNUNGEN'),
              Tab(text: 'TABELLE'),
              Tab(text: 'TOP-TEAM'),
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
        body: const TabBarView(
          children: [
            MatchesScreen(),
            TableScreen(),
            TopTeamScreen(),
          ],
        ),
      ),
    );
  }
}
