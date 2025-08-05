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

  Future<void> updateRatingsForSingleGame(int spielId) async {
    print('Starte Update für Spiel-ID: $spielId');
    try {
      // 1. Hole die Team-IDs für das spezifische Spiel
      final spielResponse = await _supabase
          .from('spiel')
          .select('heimteam_id, auswärtsteam_id')
          .eq('id', spielId)
          .single(); // .single() erwartet genau einen Datensatz

      final hometeamId = spielResponse['heimteam_id'];
      final awayteamId = spielResponse['auswärtsteam_id'];

      if (hometeamId == null || awayteamId == null) {
        print('Fehler: Team-IDs für Spiel $spielId konnten nicht gefunden werden.');
        return;
      }

      // 2. Rufe die bestehende Funktion auf, um die neuesten Spieler- und Rating-Daten
      // von der API zu holen und in Supabase zu speichern (upsert aktualisiert sie).
      await apiService.fetchAndStoreSpielerundMatchratings(spielId, hometeamId, awayteamId);

      print('Update für Spiel-ID: $spielId erfolgreich abgeschlossen.');
    } catch (error) {
      print('Fehler beim Aktualisieren der Ratings für Spiel $spielId: $error');
    }
  }

  Future<void> aggregateUniversalStats() async {
    print('Starte Aggregation der Universal Stats für spezifische Positionen...');
    try {
      // 1. Alle relevanten Match-Ratings mit Position und Statistiken abrufen
      final allRatings = await _supabase
          .from('matchrating')
          .select('match_position, statistics');

      // 2. Map zur Zwischenspeicherung der aggregierten Daten erstellen
      final Map<String, Map<String, dynamic>> aggregatedData = {};

      // 3. Alle Match-Ratings durchlaufen und die Stats pro Position aufaddieren
      for (final rating in allRatings) {
        final position = rating['match_position'] as String?;
        final stats = rating['statistics'] as Map<String, dynamic>?;

        // Überspringe, falls Position oder Stats ungültig sind
        if (position == null || stats == null || ['SUB', 'N/A', ''].contains(position)) {
          continue;
        }

        // Initialisiere den Eintrag für die Position, falls er noch nicht existiert
        aggregatedData.putIfAbsent(position, () => {'statistics': <String, double>{}, 'anzahl': 0});

        // Die einzelnen Statistik-Werte aufaddieren
        final currentStats = aggregatedData[position]!['statistics'] as Map<String, double>;
        stats.forEach((key, value) {
          double statValue = 0;
          if (value is num) {
            statValue = value.toDouble();
          } else if (value is Map && value.containsKey('total')) {
            statValue = (value['total'] as num? ?? 0).toDouble();
          }
          currentStats[key] = (currentStats[key] ?? 0.0) + statValue;
        });

        // Die Anzahl der Spiele für diese Position um 1 erhöhen
        aggregatedData[position]!['anzahl'] = (aggregatedData[position]!['anzahl'] as int) + 1;
      }

      // 4. Die finalen, aggregierten Daten in die 'universal_stats'-Tabelle speichern
      for (final entry in aggregatedData.entries) {
        final position = entry.key;
        final stats = entry.value['statistics'] as Map<String, double>;
        final anzahl = entry.value['anzahl'] as int;

        final Map<String, num> finalStats = stats.map((key, value) => MapEntry(key, value));

        await supabaseService.saveUniversalStats(position, finalStats, anzahl);
      }

      print('Aggregation der Universal Stats erfolgreich abgeschlossen.');
    } catch (error) {
      print('Ein Fehler ist bei der Aggregation der Universal Stats aufgetreten: $error');
    }
  }
}