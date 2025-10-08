// lib/screens/main_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/team_screen.dart';
import 'package:premier_league/screens/premier_league/premier_league_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  Timer? _debounce;

  // Wir machen die Suchfunktion asynchron und geben die Ergebnisse direkt zurück.
  Future<List<Widget>> _fetchSuggestions(String query) async {
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final seasonId = dataManagement.seasonId;

    if (query
        .trim()
        .isEmpty) {
      return [];
    }

    // Debouncing direkt in der Suchfunktion
    final completer = Completer<List<Map<String, dynamic>>>();
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final supabase = Supabase.instance.client;

        final responses = await Future.wait([
          supabase
              .from('season_teams')
              .select('teams:team(id, name, image_url)')
              .eq('season_id', seasonId)
              .ilike('teams.name', '%$query%')
              .limit(5),
          supabase
              .from('season_players')
              .select('spieler:spieler(id, name, profilbild_url)')
              .eq('season_id', seasonId)
              .ilike('spieler.name', '%$query%')
              .limit(10)
        ]);


        final List<Map<String, dynamic>> combinedResults = [];
        final teams = responses[0] as List;
        final players = responses[1] as List;

        for (var team in teams) {
          combinedResults.add({...team, 'type': 'team'});
        }
        for (var player in players) {
          combinedResults.add({...player, 'type': 'player'});
        }

        completer.complete(combinedResults);
      } catch (e) {
        print("Fehler bei der Suche: $e");
        completer.complete([]); // Leere Liste bei Fehler zurückgeben
      }
    });

    final results = await completer.future;

    // Wandelt die Daten in eine klickbare Liste von Widgets um
    // Wandelt die Daten in eine klickbare Liste von Widgets um
    return results.map((result) {
      final isTeam = result['type'] == 'team';

      Widget leadingWidget;
      if (result['image_url'] != null) {
        // Teams
        leadingWidget = Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(
              image: NetworkImage(result['image_url']),
              fit: BoxFit.cover,
            ),
          ),
        );
      } else if (result['profilbild_url'] != null) {   // <-- nicht profileImageUrl
        // Spieler
        leadingWidget = Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(
              image: NetworkImage(result['profilbild_url']),
              fit: BoxFit.cover,
            ),
          ),
        );
      } else {
        leadingWidget = Icon(isTeam ? Icons.shield : Icons.person, size: 40);
      }


      return ListTile(
        leading: leadingWidget,
        title: Text(result['name']),
        onTap: () {
          Navigator.of(context).pop(); // Schließt die Suchansicht
          if (isTeam) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TeamScreen(teamId: result['id']),
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlayerScreen(playerId: result['id']),
              ),
            );
          }
        },
      );
    }).toList();
  }

    // Die Hauptseiten der App
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
        // SearchAnchor ist der einfachste Weg, eine Suche zu implementieren
        title: SearchAnchor.bar(
          suggestionsBuilder: (context, controller) async {
            // Zeigt einen Ladeindikator, während wir auf das Debouncing und die DB-Abfrage warten
            if (controller.text.isEmpty) {
              return [const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Gib einen Namen ein...")))];
            }
            // Diese Funktion wird nun direkt aufgerufen und gibt die Liste der Widgets zurück
            final results = await _fetchSuggestions(controller.text);
            if (results.isEmpty) {
              return [const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("Keine Ergebnisse gefunden.")))];
            }
            return results;
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
