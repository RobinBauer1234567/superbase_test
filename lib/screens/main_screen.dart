// lib/screens/main_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/team_screen.dart';
import 'package:premier_league/screens/premier_league/premier_league_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';

// Enum zur Definition des Suchfilters
enum SearchFilter { players, teams }

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  Timer? _debounce;

  // Zustandsvariable für den Suchfilter, standardmäßig "Spieler"
  SearchFilter _searchFilter = SearchFilter.players;

  // Diese Funktion bleibt unverändert, sie ist bereits korrekt.
  Future<List<Widget>> _fetchSuggestions(String query, SearchFilter filter) async {
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final seasonId = dataManagement.seasonId;

    if (query.trim().isEmpty) {
      return [];
    }

    final completer = Completer<List<Map<String, dynamic>>>();
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final supabase = Supabase.instance.client;
        final List<Map<String, dynamic>> combinedResults = [];

        if (filter == SearchFilter.players) {
          final response = await supabase
              .from('season_players')
              .select('spieler:spieler(id, name, profilbild_url)')
              .eq('season_id', seasonId)
              .ilike('spieler.name', '%$query%');

          for (var player in response) {
            if (player['spieler'] != null) {
              combinedResults.add({...player['spieler'], 'type': 'player'});
            }
          }
        } else {
          final response = await supabase
              .from('season_teams')
              .select('teams:team(id, name, image_url)')
              .eq('season_id', seasonId)
              .ilike('teams.name', '%$query%');

          for (var team in response) {
            if (team['teams'] != null) {
              combinedResults.add({...team['teams'], 'type': 'team'});
            }
          }
        }

        completer.complete(combinedResults);
      } catch (e) {
        print("Fehler bei der Suche: $e");
        completer.complete([]);
      }
    });

    final results = await completer.future;

    return results.map((result) {
      final isTeam = result['type'] == 'team';
      final imageUrl = isTeam ? result['image_url'] : result['profilbild_url'];
      Widget leadingWidget;

      if (imageUrl != null) {
        leadingWidget = CircleAvatar(
          backgroundImage: NetworkImage(imageUrl),
        );
      } else {
        leadingWidget = CircleAvatar(
            child: Icon(isTeam ? Icons.shield : Icons.person)
        );
      }

      return ListTile(
        leading: leadingWidget,
        title: Text(result['name']),
        onTap: () {
          Navigator.of(context).pop();
          if (isTeam) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TeamScreen(teamId: result['id'])),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PlayerScreen(playerId: result['id'])),
            );
          }
        },
      );
    }).toList();
  }

  static final List<Widget> _widgetOptions = <Widget>[
    const PremierLeagueScreen(),
    const Center(child: Text('Managerliga 1 Inhalt')),
    const Center(child: Text('Managerliga 2 Inhalt')),
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.network(
            'https://rcfetlzldccwjnuabfgj.supabase.co/storage/v1/object/sign/Overlay/untitled-0.png?token=eyJraWQiOiJzdG9yYWdlLXVybC1zaWduaW5nLWtleV82YmI3OGQ3Mi0wYmJkLTQ5MWMtOTNmYy1iZTY0NjIxMTk4ZTQiLCJhbGciOiJIUzI1NiJ9.eyJ1cmwiOiJPdmVybGF5L3VudGl0bGVkLTAucG5nIiwiaWF0IjoxNzU1OTQwMzU2LCJleHAiOjE5MTM2MjAzNTZ9.8R1Fp_FT171tqVbNcfUgkMvo65GexfqvUyOBOKHxTPc',
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.shield),
          ),
        ),
        title: SearchAnchor.bar(
          // KORREKTUR: Der gesamte Builder gibt jetzt eine Liste zurück `[ ... ]`
          suggestionsBuilder: (context, controller) {
            return [
              StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
                  Widget buildFilterButtons() {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.person, size: 18),
                            label: const Text('Spieler'),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: _searchFilter == SearchFilter.players ? Colors.white : Theme.of(context).colorScheme.onSurface,
                              backgroundColor: _searchFilter == SearchFilter.players ? Theme.of(context).colorScheme.primary : Colors.grey[300],
                            ),
                            onPressed: () {
                              setState(() {
                                _searchFilter = SearchFilter.players;
                              });
                            },
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.shield, size: 18),
                            label: const Text('Teams'),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: _searchFilter == SearchFilter.teams ? Colors.white : Theme.of(context).colorScheme.onSurface,
                              backgroundColor: _searchFilter == SearchFilter.teams ? Theme.of(context).colorScheme.primary : Colors.grey[300],
                            ),
                            onPressed: () {
                              setState(() {
                                _searchFilter = SearchFilter.teams;
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }

                  return FutureBuilder<List<Widget>>(
                    future: _fetchSuggestions(controller.text, _searchFilter),
                    builder: (context, snapshot) {
                      if (controller.text.isEmpty) {
                        return Column(
                          children: [
                            buildFilterButtons(),
                            const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Gib einen Namen ein..."))),
                          ],
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Column(
                          children: [
                            buildFilterButtons(),
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ],
                        );
                      }

                      final suggestions = snapshot.data ?? [];
                      return ListView(
                        shrinkWrap: true,
                        children: [
                          buildFilterButtons(),
                          if (suggestions.isEmpty)
                            const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Keine Ergebnisse gefunden."))),
                          ...suggestions,
                        ],
                      );
                    },
                  );
                },
              ),
            ];
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle, size: 30),
            onPressed: () {},
          ),
        ],
        backgroundColor: Colors.white,
        elevation: 1.0,
      ),
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.sports_soccer), label: 'Premier League'),
          BottomNavigationBarItem(icon: Icon(Icons.groups), label: 'Liga 1'),
          BottomNavigationBarItem(icon: Icon(Icons.groups), label: 'Liga 2'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
      ),
    );
  }
}