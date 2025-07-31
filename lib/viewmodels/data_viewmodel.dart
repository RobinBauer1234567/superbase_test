//match_service.dart
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:premier_league/models/player.dart';
import 'package:premier_league/models/match.dart';
import 'package:premier_league/data_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DataManagement {
  final SupabaseClient _supabase = Supabase.instance.client;
  ApiService apiService = ApiService();
  SupabaseService supabaseService = SupabaseService();

  Future<void> collectNewData() async {
    print('start: collectnewData');
    await apiService.fetchAndStoreSpieltage();
    print('spieltage gespeichert');
    List<int> spieltage = await supabaseService.fetchAllSpieltagIds();
    await Future.wait(spieltage.map((spieltag) async {
      await apiService.fetchAndStoreSpiele(spieltag);
      print('spiele für Spieltag $spieltag gespeichert');
    }));
    await updateData();
    print('finish');
  }

  Future<void> updateData() async {
    List<int> spieltage = await supabaseService.fetchAllSpieltagIds();
    print('Update gestartet');

    await Future.wait(spieltage.map((spieltagId) async {
      final response = await _supabase
          .from('spieltag')
          .select('status')
          .eq('round', spieltagId)
          .maybeSingle();

      if (response == null || response['status'] == null) {
        print('Kein Status für Spieltag $spieltagId gefunden.');
        return;
      }

      String spieltagStatus = response['status'];
      if (spieltagStatus == 'final') {
        print('Spieltag: $spieltagId ist bereits final');
        return;
      }

      List<int> spiele = await supabaseService.fetchSpielIdsForRound(spieltagId);

      // ⚡ Parallel alle Spiele abfragen
      List<Map<String, dynamic>?> spielDaten = await Future.wait(
        spiele.map((spiel) async {
          return await _supabase
              .from('spiel')
              .select('id, status, heimteam_id, auswärtsteam_id')
              .eq('id', spiel)
              .maybeSingle();
        }),
      );

      List<String> spielStatusSpieltag = [];

      // ⚡ Parallel alle Spiele verarbeiten
      await Future.wait(spielDaten.map((spielResponse) async {
        if (spielResponse == null) return;

        String status = spielResponse['status'] ?? 'unbekannt';
        int hometeamId = spielResponse['heimteam_id'] ?? -1;
        int awayteamId = spielResponse['auswärtsteam_id'] ?? -1;
        int spielId = spielResponse['id'];

        if (status != 'final') {
          String neuerStatus = await getSpielStatus(spielId);
          if (status != neuerStatus) {
            await supabaseService.updateSpielStatus(spielId, neuerStatus);
            status = neuerStatus;
          }
          if (neuerStatus != 'nicht gestartet'){
            await apiService.fetchAndStoreSpielerundMatchratings(spielId, hometeamId, awayteamId);
          }
        }

        spielStatusSpieltag.add(status);
      }));

      // ✅ Spieltag-Status setzen
      if (spielStatusSpieltag.every((s) => s == 'final')) {
        await supabaseService.updateSpieltagStatus(spieltagId, 'final');
      } else if (spielStatusSpieltag.every((s) => s == 'nicht gestartet')) {
        await supabaseService.updateSpieltagStatus(spieltagId, 'nicht gestartet');
      } else if (spielStatusSpieltag.any((s) => s == 'nicht gestartet') || spielStatusSpieltag.any((s) => s == 'läuft')) {
        await supabaseService.updateSpieltagStatus(spieltagId, 'läuft');
      } else {
        await supabaseService.updateSpieltagStatus(spieltagId, 'beendet');
      }

      print('Spieltag $spieltagId wurde geupdated');
    }));
  }



  Future <String> getSpielStatus (spielId) async {
    String spielstatus;
    DateTime spielDatum = await supabaseService.fetchSpieldatum(spielId);
    DateTime jetzt = DateTime.now();
    Duration differenz = jetzt.difference(spielDatum);

    if (differenz.inHours <= 0) {
      spielstatus = 'nicht gestartet';
    } else if (differenz.inHours < 2) {
      spielstatus = 'läuft';
    } else if (differenz.inHours < 24) {
      spielstatus = 'beendet';
    } else if (differenz.inHours >= 24) {
      spielstatus = 'final';
    } else {
      spielstatus = 'unklar';
    }

    return spielstatus;
  }
}