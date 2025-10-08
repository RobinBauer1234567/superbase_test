// lib/viewmodels/data_viewmodel.dart
import 'dart:convert';
import 'package:pool/pool.dart';
import 'package:premier_league/data_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DataManagement {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ApiService apiService = ApiService();
  final SupabaseService supabaseService = SupabaseService();
  final int seasonId;

  DataManagement({required this.seasonId});

  Future<void> collectNewData() async {
    print('start: collectNewData for season $seasonId');

    // **ÄNDERUNG HIER:** Übergib die seasonId an fetchAndStoreTeams
    await apiService.fetchAndStoreTeams(seasonId.toString());
    print('Teams gespeichert');

    await apiService.fetchAndStoreSpieltage(seasonId.toString());
    print('Spieltage für Saison $seasonId gespeichert');

    List<int> spieltage = await supabaseService.fetchAllSpieltagIds(seasonId);
    await Future.wait(spieltage.map((spieltag) async {
      await apiService.fetchAndStoreSpiele(spieltag, seasonId.toString());
      print('Spiele für Spieltag $spieltag gespeichert');
    }));

    await Future.delayed(const Duration(seconds: 5));
    await updateData();
    print('finish');
  }

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

  Future<void> updateData() async {
    List<int> spieltage = await supabaseService.fetchAllSpieltagIds(seasonId);
    print('Update für Saison $seasonId gestartet');

    final pool = Pool(50);
    final batches = _partition(spieltage, 5);

    for (final batch in batches) {
      await Future.wait(batch.map((spieltagId) async {
        final response = await _supabase
            .from('spieltag')
            .select('status')
            .eq('round', spieltagId)
            .eq('season_id', seasonId)
            .maybeSingle();

        if (response == null || response['status'] == null || response['status'] == 'final') {
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
                // **ÄNDERUNG HIER:** Übergib die seasonId
                await apiService.fetchAndStoreSpielerundMatchratings(
                    spielId, hometeamId, awayteamId, seasonId);
              }
            }
            spielStatusSpieltag.add(status);
          });
          gameUpdateFutures.add(future);
        }

        await Future.wait(gameUpdateFutures);

        if (spielStatusSpieltag.every((s) => s == 'final')) {
          await supabaseService.updateSpieltagStatus(spieltagId, 'final', seasonId);
        } else if (spielStatusSpieltag.every((s) => s == 'nicht gestartet')) {
          await supabaseService.updateSpieltagStatus(spieltagId, 'nicht gestartet', seasonId);
        } else if (spielStatusSpieltag.any((s) => s == 'nicht gestartet') ||
            spielStatusSpieltag.any((s) => s == 'läuft')) {
          await supabaseService.updateSpieltagStatus(spieltagId, 'läuft', seasonId);
        } else {
          await supabaseService.updateSpieltagStatus(spieltagId, 'beendet', seasonId);
        }

        print('Spieltag $spieltagId wurde geupdated');
      }));
      await Future.delayed(const Duration(seconds: 1));
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
    } else {
      spielstatus = 'final';
    }

    return spielstatus;
  }

  Future<void> updateRatingsForSingleGame(int spielId) async {
    // Diese Funktion bleibt gleich, da sie sich nur auf ein spezifisches Spiel bezieht.
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

      await apiService.fetchAndStoreSpielerundMatchratings(spielId, hometeamId, awayteamId, seasonId);

      print('Update für Spiel-ID: $spielId erfolgreich abgeschlossen.');
    } catch (error) {
      print('Fehler beim Aktualisieren der Ratings für Spiel $spielId: $error');
    }
  }
}