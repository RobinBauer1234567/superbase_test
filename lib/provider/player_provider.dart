import 'package:flutter/material.dart';
import 'package:premier_league/models/player.dart';
import 'package:premier_league/api_service.dart';

class PlayerProvider with ChangeNotifier {
  List<Player> _players = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Player> get players => _players;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> fetchPlayers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      ApiService apiService = ApiService();
      _players = await apiService.fetchTopPlayers(); // ✅ Korrekte Methode aufrufen
    } catch (error) {
      _errorMessage = "Fehler beim Laden der Spieler: $error";
    }

    _isLoading = false;
    notifyListeners();
    print("Spieleranzahl geladen: ${_players.length}");

  }

}
