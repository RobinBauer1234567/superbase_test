// lib/screens/screenelements/main_screen/tournament_init_screen.dart
import 'package:flutter/material.dart';

class TournamentInitScreen extends StatefulWidget {
  final int seasonId;
  final String tournamentName;

  const TournamentInitScreen({super.key, required this.seasonId, required this.tournamentName});

  @override
  State<TournamentInitScreen> createState() => _TournamentInitScreenState();
}

class _TournamentInitScreenState extends State<TournamentInitScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Initialisiere ${widget.tournamentName}"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              "Die Datenbank rattert...",
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text("Bitte hab einen Moment Geduld."),
            // Hier kommt später der geniale Live-Log rein!
          ],
        ),
      ),
    );
  }
}