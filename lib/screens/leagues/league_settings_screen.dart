import 'package:flutter/material.dart';
import 'package:premier_league/screens/leagues/league_settings_screen_legacy.dart'
    as legacy;
import 'package:premier_league/screens/leagues/tournament_selection_screen.dart';

/// Keeps the existing manager-league settings screen untouched while routing
/// the tournament/competition picker to its dedicated redesigned screen.
class LeagueSettingsScreen extends StatelessWidget {
  final int? leagueId;
  final bool isTournamentTab;

  const LeagueSettingsScreen({
    super.key,
    this.leagueId,
    this.isTournamentTab = false,
  }) : assert(
         isTournamentTab || leagueId != null,
         'leagueId is required when isTournamentTab is false',
       );

  @override
  Widget build(BuildContext context) {
    if (isTournamentTab) {
      return const TournamentSelectionScreen();
    }

    return legacy.LeagueSettingsScreen(leagueId: leagueId);
  }
}
