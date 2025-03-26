//match_service.dart
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:premier_league/models/player.dart';
import 'package:premier_league/models/match.dart';
import 'package:premier_league/data_service.dart';
import 'package:premier_league/provider/player_provider.dart';

class DataManagement extends ChangeNotifier{
  ApiService apiService = ApiService();
  SupabaseService supabaseService = SupabaseService();
  PlayerProvider playerProvider = PlayerProvider();

  Future<void> collectNewData() async {
    List<Spieltag> spieltage = await apiService.fetchSpieltage();
    List<Spiel> spiele = [];
    for (var spieltag in spieltage) {
      List<Spiel> neueSpiele =
          await apiService.fetchSpieleForRound(spieltag.roundNumber);
      for (var neuesSpiel in neueSpiele) {
        spiele.add(neuesSpiel);
        spieltag.addSpiel(neuesSpiel);
        supabaseService.saveSpiel(neuesSpiel, neuesSpiel.matchId);
      }
      supabaseService.saveSpieltag(spieltag);
    }
    await updateData();
    print('finish');
  }

  Future<void> updateData() async {
    print("updateData() gestartet");
    print("Vor getSpieltage()");
    List<Spieltag> spieltage = await supabaseService.getSpieltage();
    print("Nach getSpieltage(): $spieltage");
    List <Player> players = [];
    for (var spieltag in spieltage) {
      //if (spieltag.status == SpielStatus.finalStatus) break;
      List<Spiel> spiele = await supabaseService.getSpieleBySpieltag(spieltag.roundNumber);
      print(spiele);
      for (var spiel in spiele) {
        if (spiel.status != SpielStatus.finalStatus) {
          SpielStatus spielStatus =
              await apiService.fetchSpielstatus(spiel.matchId);
          if (spielStatus == SpielStatus.notPlayed) {
            spiel.setStatus(SpielStatus.notPlayed);
          } else {
            List <Player> playersPerGame = await apiService.fetchLineups(spiel.matchId);
            for (var playerPerGame in playersPerGame){
              players.add(playerPerGame);
            }
            if (spielStatus == SpielStatus.live) {
              spiel.setStatus(SpielStatus.live);
            } else if (spielStatus == SpielStatus.provisional) {
              spiel.setStatus(SpielStatus.provisional);
            } else {
              spiel.setStatus(SpielStatus.finalStatus);
            }
          }
        } else break;
      }
    }
    playerProvider.fetchPlayers(players);
    notifyListeners();
  }
}