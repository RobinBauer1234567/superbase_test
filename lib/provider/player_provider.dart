import 'package:flutter/material.dart';
import 'package:premier_league/models/player.dart';
import 'package:premier_league/match_service.dart';

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
      FirestoreService firestoreService = FirestoreService();
      ApiService apiService = ApiService();
      MatchService matchService = MatchService();

      List<int> matchIds = await matchService.collectNewData();
      List<Player> allNewPlayers = []; // Liste für alle neu geladenen Spieler

      // 🔹 Spieler aus der API für jede Match-ID abrufen
      for (var matchId in matchIds) {
        List<Player> newPlayers = await apiService.fetchTopPlayers(matchId);
        allNewPlayers.addAll(newPlayers);
      }

      // 🔹 Spieler aus Firestore abrufen
      List<Player> storedPlayers = await firestoreService.getPlayers();
      List<Player> updatedPlayers = []; // Liste für Spieler mit neuen Daten

      for (var newPlayer in allNewPlayers) {
        // Prüfen, ob Spieler bereits existiert
        Player? existingPlayer = storedPlayers.firstWhere(
              (p) => p.name == newPlayer.name,
          orElse: () => newPlayer, // Falls nicht vorhanden, nehme den neuen
        );

        // 🔹 Alle neuen MatchRatings hinzufügen oder aktualisieren
        for (var matchId in newPlayer.matchRatings.keys) {
          existingPlayer.addOrUpdateMatchRating(
              matchId, newPlayer.matchRatings[matchId]!);
        }

        updatedPlayers.add(
            existingPlayer); // Spieler zur Speicherliste hinzufügen
      }

      // 🔹 Aktualisierte Spieler in Firestore speichern
      if (updatedPlayers.isNotEmpty) {
        await firestoreService.savePlayer(updatedPlayers);
      }

      // 🔹 Spieler aus Firestore neu laden
      _players = await firestoreService.getPlayers();
    } catch (error) {
      _errorMessage = "Fehler beim Laden der Spieler: $error";
    }

    _isLoading = false;
    notifyListeners();
  }
}