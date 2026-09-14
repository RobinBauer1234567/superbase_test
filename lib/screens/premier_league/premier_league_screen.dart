import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';
// lib/screens/premier_league/premier_league_screen.dart
import 'package:flutter/material.dart';
import 'package:premier_league/screens/premier_league/matches_screen.dart';
import 'package:premier_league/screens/premier_league/table_screen.dart';
import 'package:premier_league/screens/premier_league/top_team_screen.dart';
import 'dart:math'; // Import für die 'max'-Funktion

class PremierLeagueScreen extends StatelessWidget {
  final bool enableRealtime;
  const PremierLeagueScreen({super.key, this.enableRealtime = true});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TournamentViewModel>();
    final screenWidth = MediaQuery.of(context).size.width;

    final double tabFontSize = max(5.0, min(screenWidth / 45, 15));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 0,
          bottom: TabBar(
            isScrollable: false,
            tabs: const [
              Tab(text: 'BEGEGNUNGEN'),
              Tab(text: 'TABELLE'),
              Tab(text: 'TOP-TEAM'),
            ],
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: tabFontSize),
            unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal, fontSize: tabFontSize),
          ),
        ),
        body: TabBarView(
          key: ValueKey(vm.currentSeasonId),
          children: [
            MatchesScreen(enableRealtime: enableRealtime),
            const TableScreen(),
            const TopTeamScreen(),
          ],
        ),
      ),
    );
  }
}
