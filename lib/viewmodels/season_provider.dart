// lib/viewmodels/season_provider.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Season {
  final int id;
  final String name;
  final int tournamentId; // NEU

  Season({required this.id, required this.name, required this.tournamentId});
}

class SeasonProvider with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Season> _seasons = [];
  Season? _selectedSeason;

  List<Season> get seasons => _seasons;
  Season? get selectedSeason => _selectedSeason;

  SeasonProvider() {
    _loadSeasons();
  }

  Future<void> _loadSeasons() async {
    // Wir fragen nun auch die tournament_id ab
    final response = await _supabase.from('season').select('id, name, tournament_id').order('name', ascending: false);

    _seasons = response.map((s) => Season(
        id: s['id'],
        name: s['name'],
        tournamentId: s['tournament_id'] ?? 17 // Fallback auf 17 für bestehende Ligen
    )).toList();

    final activeSeasonResponse = await _supabase.from('season').select('id, name, tournament_id').eq('is_active', true).maybeSingle();

    if (activeSeasonResponse != null) {
      _selectedSeason = Season(
          id: activeSeasonResponse['id'],
          name: activeSeasonResponse['name'],
          tournamentId: activeSeasonResponse['tournament_id'] ?? 17
      );
    } else if (_seasons.isNotEmpty) {
      _selectedSeason = _seasons.first;
    }

    notifyListeners();
  }

  void changeSeason(Season newSeason) {
    _selectedSeason = newSeason;
    notifyListeners();
  }
}
