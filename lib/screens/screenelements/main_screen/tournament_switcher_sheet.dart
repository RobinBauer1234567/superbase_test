// lib/screens/screenelements/main_screen/tournament_switcher_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/tournament_viewmodel.dart';
import 'package:premier_league/screens/screenelements/league_logo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:premier_league/screens/screenelements/main_screen/tournament_init_screen.dart';

class TournamentSwitcherScreen extends StatelessWidget {
  const TournamentSwitcherScreen({super.key});

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

    return DefaultTabController(
      length: 2, // Anzahl der Tabs
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Turnier-Hub"),
          elevation: 0,
        ),
        body: Column(
          children: [
            // --- OBERER TEIL (Header wie in LeagueSettingsScreen) ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.05),
                border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 1)),
              ),
              child: Row(
                children: [
                  LeagueLogo(imageUrl: viewModel.currentTournamentLogo, radius: 36),
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

            // --- DIE TABS ---
            const TabBar(
              tabs: [
                Tab(text: "VERFÜGBAR"),
                Tab(text: "AKTIV"),
              ],
            ),

            // --- INHALT DER TABS ---
            Expanded(
              child: TabBarView(
                children: [
                  // Tab 1: Alle Turniere
                  _buildTournamentList(context, viewModel, showOnlyActive: false),

                  // Tab 2: Nur aktive Turniere
                  _buildTournamentList(context, viewModel, showOnlyActive: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Ausgelagerte Methode für die Listen-Generierung
  Widget _buildTournamentList(BuildContext context, TournamentViewModel viewModel, {required bool showOnlyActive}) {
    final allTournaments = viewModel.allTournaments;

    // Filtern, falls "showOnlyActive" true ist
    final displayTournaments = showOnlyActive
        ? allTournaments.where((t) {
      final seasons = List<Map<String, dynamic>>.from(t['season'] ?? []);
      if (seasons.isEmpty) return false;
      return seasons.last['is_initialized'] == true;
    }).toList()
        : allTournaments;

    if (displayTournaments.isEmpty) {
      return const Center(child: Text("Keine Turniere gefunden."));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: displayTournaments.length,
      itemBuilder: (context, index) {
        final tournament = displayTournaments[index];
        final seasons = List<Map<String, dynamic>>.from(tournament['season'] ?? []);
        if (seasons.isEmpty) return const SizedBox.shrink();

        final currentSeason = seasons.last;
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
                Navigator.pop(context); // Zurück zum MainScreen
              } else {
                _showInitDialog(context, currentSeason, tournament['name']);
              }
            },
            child: Opacity(
              opacity: (isActive && isInitialized) ? 1.0 : 0.5,
              child: Padding(
                padding: const EdgeInsets.all(16),
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
    );
  }
}