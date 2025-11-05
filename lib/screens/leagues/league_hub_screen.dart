// lib/screens/league_hub_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/data_service.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';

class LeagueHubScreen extends StatefulWidget {
  const LeagueHubScreen({super.key});

  @override
  State<LeagueHubScreen> createState() => _LeagueHubScreenState();
}

class _LeagueHubScreenState extends State<LeagueHubScreen> {

  void _showCreateLeagueDialog() {
    final formKey = GlobalKey<FormState>();
    String leagueName = '';
    double startingBudget = 100.0;
    bool isPublic = false; // Neuer Zustand für die Checkbox

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder( // Wichtig für die Checkbox
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Neue Liga gründen'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Name der Liga'),
                      validator: (value) => (value == null || value.isEmpty) ? 'Bitte einen Namen eingeben' : null,
                      onSaved: (value) => leagueName = value!,
                    ),
                    TextFormField(
                      decoration: const InputDecoration(labelText: 'Startbudget (in Mio. €)'),
                      keyboardType: TextInputType.number,
                      initialValue: '100',
                      validator: (value) => (value == null || double.tryParse(value) == null) ? 'Bitte eine Zahl eingeben' : null,
                      onSaved: (value) => startingBudget = double.parse(value!),
                    ),
                    CheckboxListTile(
                      title: const Text("Öffentliche Liga"),
                      value: isPublic,
                      onChanged: (bool? value) {
                        setDialogState(() {
                          isPublic = value ?? false;
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    )
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      formKey.currentState!.save();
                      final dataManagement = Provider.of<DataManagement>(context, listen: false);
                      try {
                        await dataManagement.supabaseService.createLeague(
                          name: leagueName,
                          startingBudget: startingBudget * 1000000,
                          seasonId: dataManagement.seasonId,
                          isPublic: isPublic,
                        );
                        Navigator.of(context).pop(true); // Signalisiert Erfolg
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text('Gründen'),
                ),
              ],
            );
          },
        );
      },
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
                subtitle: Text('Startbudget: ${league['starting_budget'] / 1000000} Mio.'),
                trailing: ElevatedButton(
                  child: const Text('Beitreten'),
                  onPressed: () async {
                    try {
                      await dataManagement.supabaseService.joinLeague(league['id']);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Du bist der Liga "${league['name']}" beigetreten!'), backgroundColor: Colors.green),
                      );
                      // Navigator.pop(context, true); // Schließt den Hub und signalisiert Erfolg
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
                      );
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