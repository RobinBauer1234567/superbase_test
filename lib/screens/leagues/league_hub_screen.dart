// lib/screens/leagues/league_hub_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/data_service.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/leagues/starter_team_reveal_screen.dart';

class LeagueHubScreen extends StatefulWidget {
  const LeagueHubScreen({super.key});

  @override
  State<LeagueHubScreen> createState() => _LeagueHubScreenState();
}

class _LeagueHubScreenState extends State<LeagueHubScreen> {

  void _showCreateLeagueDialog() {
    final formKey = GlobalKey<FormState>();

    // Form State Variables
    String leagueName = '';
    double startingBudget = 50.0; // <--- HIER GEÄNDERT: Standard auf 50.0
    bool isPublic = false;

    // Neue State Variables für Kader & Startformat
    bool isSquadLimitEnabled = false;
    double squadLimit = 15.0;
    double numStartingPlayers = 11.0;
    double startingTeamValue = 110.0;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double minTeamValue = numStartingPlayers > 0 ? numStartingPlayers * 5.0 : 0.0;
            double maxTeamValue = numStartingPlayers > 0 ? numStartingPlayers * 15.0 : 0.0;

            if (startingTeamValue < minTeamValue) startingTeamValue = minTeamValue;
            if (startingTeamValue > maxTeamValue) startingTeamValue = maxTeamValue;
            if (numStartingPlayers == 0) startingTeamValue = 0.0;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- HEADER ---
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.add_moderator, color: Colors.white),
                          SizedBox(width: 12),
                          Text(
                            'Neue Liga gründen',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),

                    // --- CONTENT ---
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader("Allgemeines", Icons.info_outline),
                              const SizedBox(height: 16),
                              TextFormField(
                                decoration: InputDecoration(
                                  labelText: 'Name der Liga',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.emoji_events_outlined),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                                validator: (value) => (value == null || value.isEmpty) ? 'Bitte Namen eingeben' : null,
                                onSaved: (value) => leagueName = value!,
                              ),
                              const SizedBox(height: 12),
                              SwitchListTile(
                                title: const Text("Öffentliche Liga"),
                                subtitle: Text(
                                  isPublic ? "Jeder kann beitreten" : "Nur mit Einladung",
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                ),
                                secondary: Icon(isPublic ? Icons.public : Icons.lock_outline),
                                value: isPublic,
                                activeColor: Theme.of(context).primaryColor,
                                onChanged: (val) => setDialogState(() => isPublic = val),
                                contentPadding: EdgeInsets.zero,
                              ),

                              const SizedBox(height: 24),
                              _buildSectionHeader("Kader & Regeln", Icons.groups_outlined),
                              const SizedBox(height: 12),

                              SwitchListTile(
                                title: const Text("Kaderbegrenzung"),
                                value: isSquadLimitEnabled,
                                onChanged: (val) => setDialogState(() => isSquadLimitEnabled = val),
                                contentPadding: EdgeInsets.zero,
                              ),
                              if (isSquadLimitEnabled)
                                Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text("Max. Spieleranzahl:"),
                                        Chip(label: Text("${squadLimit.round()}", style: const TextStyle(fontWeight: FontWeight.bold))),
                                      ],
                                    ),
                                    Slider(
                                      value: squadLimit,
                                      min: 11,
                                      max: 25,
                                      divisions: 14,
                                      label: squadLimit.round().toString(),
                                      onChanged: (val) => setDialogState(() => squadLimit = val),
                                    ),
                                  ],
                                ),

                              const SizedBox(height: 24),
                              _buildSectionHeader("Startbedingungen", Icons.monetization_on_outlined),
                              const SizedBox(height: 16),

                              TextFormField(
                                decoration: InputDecoration(
                                  labelText: 'Startbudget',
                                  suffixText: 'Mio. €',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                                keyboardType: TextInputType.number,
                                initialValue: '50', // <--- HIER GEÄNDERT: Startwert im Textfeld auf '50'
                                validator: (value) => (value == null || double.tryParse(value) == null) ? 'Zahl eingeben' : null,
                                onSaved: (value) => startingBudget = double.parse(value!),
                              ),

                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Zugeloste Spieler:"),
                                  Chip(
                                    label: Text(numStartingPlayers == 0 ? "Keine" : "${numStartingPlayers.round()}"),
                                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                                  ),
                                ],
                              ),
                              Slider(
                                value: numStartingPlayers,
                                min: 0,
                                max: 15,
                                divisions: 15,
                                label: numStartingPlayers.round().toString(),
                                onChanged: (val) {
                                  setDialogState(() {
                                    numStartingPlayers = val;
                                    // Automatisch auf die Mitte (x 10 Mio) setzen
                                    if (numStartingPlayers > 0) {
                                      startingTeamValue = numStartingPlayers * 10.0;
                                    } else {
                                      startingTeamValue = 0.0;
                                    }
                                  });
                                },
                              ),

                              // Teamwert Slider nur wenn Spieler ausgewählt sind
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 300),
                                opacity: numStartingPlayers > 0 ? 1.0 : 0.3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text("Teamwert (Gesamt):"),
                                        Text(
                                          "${startingTeamValue.toStringAsFixed(1)} Mio. €",
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                                        ),
                                      ],
                                    ),
                                    Slider(
                                      value: startingTeamValue,
                                      min: minTeamValue,
                                      max: maxTeamValue,
                                      divisions: (maxTeamValue - minTeamValue) > 0 ? ((maxTeamValue - minTeamValue) * 2).toInt() : 1,
                                      onChanged: numStartingPlayers > 0
                                          ? (val) => setDialogState(() => startingTeamValue = val)
                                          : null,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("${minTeamValue.round()} Mio", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                          Text("${maxTeamValue.round()} Mio", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // --- ACTIONS ---
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(), // Dialog schließen
                            child: const Text('Abbrechen', style: TextStyle(color: Colors.grey)),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            onPressed: () async {
                              if (formKey.currentState!.validate()) {
                                formKey.currentState!.save();
                                final dataManagement = Provider.of<DataManagement>(this.context, listen: false);
                                try {
                                  // 1. Liga erstellen
                                  final newLeagueId = await dataManagement.supabaseService.createLeague(
                                    name: leagueName,
                                    startingBudget: startingBudget * 1000000,
                                    seasonId: dataManagement.seasonId,
                                    isPublic: isPublic,
                                    squadLimit: isSquadLimitEnabled ? squadLimit.round() : null,
                                    numStartingPlayers: numStartingPlayers.round(),
                                    startingTeamValue: startingTeamValue * 1000000,
                                  );

                                  // 2. Dialog schließen
                                  if (mounted) Navigator.of(dialogContext).pop();

                                  // 3. Reveal Screen öffnen UND auf Ergebnis (leagueId) warten
                                  if (mounted) {
                                    final result = await Navigator.push(
                                      this.context, // Screen Context nutzen!
                                      MaterialPageRoute(builder: (_) => StarterTeamRevealScreen(
                                        leagueId: newLeagueId,
                                        startingBudget: startingBudget * 1000000,
                                        leagueName: leagueName,
                                      )),
                                    );

                                    // 4. Hub schließen und Ergebnis an MainScreen weitergeben
                                    if (result != null && mounted) {
                                      Navigator.of(this.context).pop(result);
                                    }
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                                  }
                                }
                              }
                            },
                            child: const Text('LIGA GRÜNDEN'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).primaryColor),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Theme.of(context).primaryColor,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dataManagement = Provider.of<DataManagement>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ligen-Hub'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Liga gründen',
            onPressed: _showCreateLeagueDialog,
          )
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: dataManagement.supabaseService.getPublicLeagues(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return const Center(child: Text('Fehler beim Laden der Ligen.'));
          }
          final publicLeagues = snapshot.data!;
          if (publicLeagues.isEmpty) {
            return const Center(child: Text('Aktuell gibt es keine öffentlichen Ligen, denen du beitreten kannst.'));
          }

          return ListView.builder(
            itemCount: publicLeagues.length,
            itemBuilder: (context, index) {
              final league = publicLeagues[index];
              return ListTile(
                title: Text(league['name']),
                subtitle: Text('Startbudget: ${(league['starting_budget'] / 1000000).round()} Mio. €'),
                // ... im ListView.builder ...
                trailing: ElevatedButton(
                  child: const Text('Beitreten'),
                  onPressed: () async {
                    try {
                      await dataManagement.supabaseService.joinLeague(league['id']);

                      if (mounted) {
                        // Reveal Screen öffnen und auf Ergebnis warten
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => StarterTeamRevealScreen(
                            leagueId: league['id'],
                            startingBudget: (league['starting_budget'] as num).toDouble(),
                            leagueName: league['name'],
                          )),
                        );

                        // Wenn fertig, Hub schließen und ID an MainScreen senden
                        if (result != null && mounted) {
                          Navigator.of(context).pop(result);
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
