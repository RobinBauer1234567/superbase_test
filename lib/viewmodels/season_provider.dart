// lib/viewmodels/season_provider.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Season {
  final int id;
  final String name;

  Season({required this.id, required this.name});
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
    final response = await _supabase.from('season').select().order('name', ascending: false);
    _seasons = response.map((s) => Season(id: s['id'], name: s['name'])).toList();

    final activeSeasonResponse = await _supabase.from('season').select('id, name').eq('is_active', true).single();
    if (activeSeasonResponse != null) {
      _selectedSeason = Season(id: activeSeasonResponse['id'], name: activeSeasonResponse['name']);
    } else if (_seasons.isNotEmpty) {
      _selectedSeason = _seasons.first;
    }

    notifyListeners();
  }

  void changeSeason(Season newSeason) {
    _selectedSeason = newSeason;
    notifyListeners(); // Benachrichtigt alle Widgets, die auf Änderungen hören
  }
}