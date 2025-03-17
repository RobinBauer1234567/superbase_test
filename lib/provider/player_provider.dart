import 'package:flutter/material.dart';
import 'package:premier_league/models/player.dart';
import 'package:premier_league/data_service.dart';

class PlayerProvider with ChangeNotifier {
  List<Player> _players = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Player> get players => _players;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  Future<void> fetchPlayers(List <Player> players) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      FirestoreService firestoreService = FirestoreService();

      // 🔹 Spieler aus Firestore abrufen
      List<Player> storedPlayers = await firestoreService.getPlayers();
      List<Player> updatedPlayers = []; // Liste für Spieler mit neuen Daten

      for (var newPlayer in players) {
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