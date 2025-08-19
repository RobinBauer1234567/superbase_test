import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:pool/pool.dart'; // Import für die Pool-Klasse
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

    // SCHRITT 1: Teams abrufen
    await apiService.fetchAndStoreTeams();
    print('Teams gespeichert');

    // SCHRITT 2: Spieltage abrufen
    await apiService.fetchAndStoreSpieltage();
    print('spieltage gespeichert');

    // SCHRITT 3: Spiele für jeden Spieltag abrufen und sicherstellen, dass alles gespeichert ist
    List<int> spieltage = await supabaseService.fetchAllSpieltagIds();
    await Future.wait(spieltage.map((spieltag) async {
      await apiService.fetchAndStoreSpiele(spieltag);
      print('spiele für Spieltag $spieltag gespeichert');
    }));

    // Kurze Pause, um der Datenbank Zeit zur Synchronisierung zu geben
    await Future.delayed(const Duration(seconds: 5));

    // SCHRITT 4: Daten aktualisieren
    await updateData();
    print('finish');
  }

  /// Teilt eine Liste in kleinere Teillisten (Batches) einer bestimmten Größe auf.
  List<List<T>> _partition<T>(List<T> list, int size) {
    if (list.isEmpty) return [];
    final partitions = <List<T>>[];
    final partitionCount = (list.length / size).ceil();
    for (var i = 0; i < partitionCount; i++) {
      final start = i * size;
      final end = (start + size < list.length) ? start + size : list.length;
      partitions.add(list.sublist(start, end));
    }
    return partitions;
  }

  /// **Die optimierte updateData-Funktion**
  Future<void> updateData() async {
    List<int> spieltage = await supabaseService.fetchAllSpieltagIds();
    print('Update gestartet');

    // Erstellt einen Pool, der die Anzahl gleichzeitiger Anfragen begrenzt (z.B. auf 10)
    // Dieser Wert kann je nach Bedarf angepasst werden.
    final pool = Pool(50);
    final batches = _partition(spieltage, 5); // Spieltage in 5er-Batches verarbeiten

    for (final batch in batches) {
      await Future.wait(batch.map((spieltagId) async {
        final response = await _supabase
            .from('spieltag')
            .select('status')
            .eq('round', spieltagId)
            .maybeSingle();

        if (response == null || response['status'] == null || response['status'] == 'final') {
          if (response != null && response['status'] == 'final') {
            print('Spieltag: $spieltagId ist bereits final');
          } else {
            print('Kein Status für Spieltag $spieltagId gefunden.');
          }
          return;
        }

        final spieleResponse = await _supabase
            .from('spiel')
            .select('id, status, heimteam_id, auswärtsteam_id')
            .eq('round', spieltagId);

        List<String> spielStatusSpieltag = [];
        List<Future> gameUpdateFutures = [];

        for (final spielData in spieleResponse) {
          final future = pool.withResource(() async {
            int spielId = spielData['id'];
            String status = spielData['status'] ?? 'unbekannt';
            int hometeamId = spielData['heimteam_id'] ?? -1;
            int awayteamId = spielData['auswärtsteam_id'] ?? -1;

            if (status != 'final') {
              String neuerStatus = await getSpielStatus(spielId);
              if (status != neuerStatus) {
                await supabaseService.updateSpielStatus(spielId, neuerStatus);
                status = neuerStatus;
              }
              if (neuerStatus != 'nicht gestartet') {
                await apiService.fetchAndStoreSpielerundMatchratings(
                    spielId, hometeamId, awayteamId);
              }
            }
            spielStatusSpieltag.add(status);
          });
          gameUpdateFutures.add(future);
        }

        await Future.wait(gameUpdateFutures);

        // Spieltag-Status setzen
        if (spielStatusSpieltag.every((s) => s == 'final')) {
          await supabaseService.updateSpieltagStatus(spieltagId, 'final');
        } else if (spielStatusSpieltag.every((s) => s == 'nicht gestartet')) {
          await supabaseService.updateSpieltagStatus(spieltagId, 'nicht gestartet');
        } else if (spielStatusSpieltag.any((s) => s == 'nicht gestartet') ||
            spielStatusSpieltag.any((s) => s == 'läuft')) {
          await supabaseService.updateSpieltagStatus(spieltagId, 'läuft');
        } else {
          await supabaseService.updateSpieltagStatus(spieltagId, 'beendet');
        }

        print('Spieltag $spieltagId wurde geupdated');
      }));
      await Future.delayed(const Duration(seconds: 1)); // Kurze Pause zwischen den Batches
    }
  }

  Future<String> getSpielStatus(spielId) async {
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

  Future<void> updateRatingsForSingleGame(int spielId) async {
    print('Starte Update für Spiel-ID: $spielId');
    try {
      final spielResponse = await _supabase
          .from('spiel')
          .select('heimteam_id, auswärtsteam_id')
          .eq('id', spielId)
          .single();

      final hometeamId = spielResponse['heimteam_id'];
      final awayteamId = spielResponse['auswärtsteam_id'];

      if (hometeamId == null || awayteamId == null) {
        print('Fehler: Team-IDs für Spiel $spielId konnten nicht gefunden werden.');
        return;
      }

      await apiService.fetchAndStoreSpielerundMatchratings(spielId, hometeamId, awayteamId);

      print('Update für Spiel-ID: $spielId erfolgreich abgeschlossen.');
    } catch (error) {
      print('Fehler beim Aktualisieren der Ratings für Spiel $spielId: $error');
    }
  }

}