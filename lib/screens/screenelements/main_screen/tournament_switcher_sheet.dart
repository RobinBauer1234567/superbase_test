// lib/screens/screenelements/main_screen/tournament_switcher_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';
import 'package:premier_league/screens/screenelements/league_logo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/screenelements/main_screen/tournament_init_screen.dart';

class TournamentSwitcherSheet extends StatelessWidget {
  const TournamentSwitcherSheet({super.key});

  void _showInitDialog(BuildContext context, Map<String, dynamic> season, String tournamentName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Liga initialisieren?"),
        content: Text("Möchtest du die Saison ${season['name']} für $tournamentName jetzt initialisieren? Das lädt alle Teams, Kader und Spieltage aus dem Internet."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Abbrechen", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx); // Dialog schließen
              Navigator.pop(context); // Bottom Sheet schließen

              // 1. Liga in der DB auf is_active = true setzen
              await Supabase.instance.client
                  .from('season')
                  .update({'is_active': true})
                  .eq('id', season['id']);

              // 2. Den neuen Lade-Screen öffnen!
              if (context.mounted) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => TournamentInitScreen(seasonId: season['id'], tournamentName: tournamentName)));
              }
            },
            child: const Text("Ja, starten"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<TournamentViewModel>();
    final allTournaments = viewModel.allTournaments;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // HEADER (Aktuelles Turnier)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                LeagueLogo(imageUrl: viewModel.currentTournamentLogo, radius: 30),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Aktuelles Turnier", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                      Text(
                        viewModel.currentTournamentName,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                      Text("Saison ${viewModel.selectedSeason?['name'] ?? ''}", style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(alignment: Alignment.centerLeft, child: Text("Verfügbare Turniere", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(height: 8),

          // LISTE ALLER TURNIERE
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: allTournaments.length,
              itemBuilder: (context, index) {
                final tournament = allTournaments[index];
                final seasons = List<Map<String, dynamic>>.from(tournament['season'] ?? []);
                if (seasons.isEmpty) return const SizedBox.shrink();

                final currentSeason = seasons.last; // Neueste Saison
                final bool isActive = currentSeason['is_active'] == true;
                final bool isInitialized = currentSeason['is_initialized'] == true;
                final bool isCurrentlySelected = tournament['id'] == viewModel.currentTournamentId;

                return Card(
                  elevation: isCurrentlySelected ? 4 : 1,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: isCurrentlySelected ? Theme.of(context).primaryColor : Colors.transparent, width: 2),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (isActive && isInitialized) {
                        viewModel.selectTournament(tournament['id'], currentSeason['id']);
                        Navigator.pop(context); // Schließen nach Auswahl
                      } else {
                        _showInitDialog(context, currentSeason, tournament['name']);
                      }
                    },
                    child: Opacity(
                      opacity: (isActive && isInitialized) ? 1.0 : 0.5, // Ausgrauen, wenn nicht fertig
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            LeagueLogo(imageUrl: tournament['image_url'], radius: 24),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tournament['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  Text("Saison ${currentSeason['name']}", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                ],
                              ),
                            ),
                            if (!isInitialized)
                              const Icon(Icons.download_rounded, color: Colors.blue)
                            else if (isCurrentlySelected)
                              Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}