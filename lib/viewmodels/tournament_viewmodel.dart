// lib/viewmodels/tournament_viewmodel.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TournamentViewModel extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  // Hier speichern wir alle Ligen, die der Global Scout in der DB gefunden hat
  List<Map<String, dynamic>> allTournaments = [];

  // Das aktuell ausgewählte Turnier und die dazugehörige Saison
  Map<String, dynamic>? selectedTournament;
  Map<String, dynamic>? selectedSeason;

  bool isLoading = true;

  TournamentViewModel() {
    // Sobald die Klasse aufgerufen wird, laden wir die Daten aus Supabase
    fetchTournaments();
  }

  /// Lädt alle Turniere und deren Saisons aus der Datenbank
  Future<void> fetchTournaments() async {
    isLoading = true;
    notifyListeners();

    try {
      // Genialer Supabase-Trick: Wir laden das Turnier UND die verknüpfte Saison auf einmal!
      final response = await _supabase
          .from('tournaments')
          .select('*, season(*)');

      allTournaments = List<Map<String, dynamic>>.from(response);

      // Wenn wir Ligen gefunden haben und noch keine ausgewählt ist,
      // setzen wir einen klugen Standardwert.
      if (allTournaments.isNotEmpty && selectedTournament == null) {
        // Wir suchen zuerst nach einer Liga, die bereits aktiv ist
        final activeTournaments = allTournaments.where((t) {
          final seasons = List<Map<String, dynamic>>.from(t['season'] ?? []);
          return seasons.any((s) => s['is_active'] == true);
        }).toList();

        if (activeTournaments.isNotEmpty) {
          _selectDefault(activeTournaments.first);
        } else {
          _selectDefault(allTournaments.first); // Fallback auf die allererste gefundene Liga
        }
      }
    } catch (e) {
      print('❌ Fehler beim Laden der Turniere: $e');
    }

    isLoading = false;
    notifyListeners(); // Sagt dem Frontend: "Die Ligen sind da, bitte UI aktualisieren!"
  }

  /// Hilfsfunktion, um das Standard-Turnier zu setzen
  void _selectDefault(Map<String, dynamic> tournament) {
    selectedTournament = tournament;
    final seasons = List<Map<String, dynamic>>.from(tournament['season'] ?? []);
    if (seasons.isNotEmpty) {
      // Wir bevorzugen die aktive Saison, sonst nehmen wir einfach die erste
      selectedSeason = seasons.firstWhere(
              (s) => s['is_active'] == true,
          orElse: () => seasons.first
      );
    }
  }

  /// Diese Methode rufen wir später auf, wenn der User im Bottom Sheet eine andere Liga antippt
  void selectTournament(int tournamentId, int seasonId) {
    selectedTournament = allTournaments.firstWhere((t) => t['id'] == tournamentId);
    final seasons = List<Map<String, dynamic>>.from(selectedTournament?['season'] ?? []);
    selectedSeason = seasons.firstWhere((s) => s['id'] == seasonId);

    // UI benachrichtigen, dass eine neue Liga gewählt wurde!
    notifyListeners();
  }

  /// Hilfreiche Getter, damit unser UI den Code schön lesbar hält
  int? get currentTournamentId => selectedTournament?['id'];
  int? get currentSeasonId => selectedSeason?['id'];
  String get currentTournamentName => selectedTournament?['name'] ?? 'Lade Turniere...';
  String? get currentTournamentLogo => selectedTournament?['image_url'];

  bool get isCurrentActive => selectedSeason?['is_active'] == true;
  bool get isCurrentInitialized => selectedSeason?['is_initialized'] == true;
}