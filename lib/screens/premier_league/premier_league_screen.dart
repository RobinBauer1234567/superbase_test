// lib/screens/premier_league/premier_league_screen.dart
import 'package:flutter/material.dart';
import 'package:premier_league/screens/premier_league/matches_screen.dart';
import 'package:premier_league/screens/premier_league/table_screen.dart';
import 'package:premier_league/screens/premier_league/top_team_screen.dart';
import 'dart:math'; // Import für die 'max'-Funktion

class PremierLeagueScreen extends StatelessWidget {
  const PremierLeagueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // --- ANPASSUNG HIER ---
    // 1. Bildschirmbreite ermitteln
    final screenWidth = MediaQuery.of(context).size.width;

    // 2. Eine passende Schriftgröße berechnen (Formel für 3 Tabs angepasst)
    final double tabFontSize = max(5.0, min(screenWidth / 45, 15));
    // --- ENDE DER ANPASSUNG ---

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 0,
          bottom: TabBar(
            tabs: const [
              Tab(text: 'BEGEGNUNGEN'),
              Tab(text: 'TABELLE'),
              Tab(text: 'TOP-TEAM'),
            ],
            // 3. Die dynamische Schriftgröße anwenden
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: tabFontSize),
            unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, fontSize: tabFontSize),
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