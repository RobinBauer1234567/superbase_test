import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data_service.dart' as legacy;

/// ApiService für den Sync-Worker mit robuster Team-/Wappen-Synchronisation.
/// Alle übrigen Methoden werden unverändert vom bestehenden ApiService geerbt.
class ApiService extends legacy.ApiService {
  static const Map<String, String> _teamSyncHeaders = {
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7',
    'X-Requested-With': 'XMLHttpRequest',
    'Origin': 'https://www.sofascore.com',
    'Referer': 'https://www.sofascore.com/',
  };

  @override
  Future<void> fetchAndStoreTeams(int tournamentId, int seasonId) async {
    final teamsUrl =
        '$baseUrl/unique-tournament/$tournamentId/season/$seasonId/teams';
    final response = await http.get(
      Uri.parse(teamsUrl),
      headers: _teamSyncHeaders,
    );

    if (response.statusCode == 429) {
      throw Exception('API_LIMIT_REACHED');
    }
    if (response.statusCode == 403) {
      throw Exception('API_ACCESS_DENIED');
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Fehler beim Abrufen der Teams: ${response.statusCode}',
      );
    }

    final parsedJson = json.decode(response.body);
    final List<dynamic> teamsJson = parsedJson['teams'] ?? [];
    final storage = supabaseService.supabase.storage.from('wappen');

    // Vorhandene Dateien nur einmal abfragen. Bereits gespeicherte Wappen
    // müssen dadurch nicht erneut von SofaScore heruntergeladen werden.
    final Set<String> storedLogoNames = <String>{};
    try {
      final objects = await storage.list(
        path: 'wappen',
        searchOptions: const SearchOptions(limit: 1000),
      );
      storedLogoNames.addAll(objects.map((object) => object.name));
    } catch (e) {
      // Wenn das Listing temporär nicht funktioniert, wird unten versucht,
      // das jeweilige Wappen normal von SofaScore zu laden.
      print('⚠️ Vorhandene Team-Wappen konnten nicht gelistet werden: $e');
    }

    final List<String> teamsWithoutLogo = <String>[];

    for (final teamData in teamsJson) {
      final int teamId = (teamData['id'] as num).toInt();
      final String teamName = teamData['name']?.toString() ?? 'Unbekannt';
      final String fileName = '$teamId.jpg';
      final String imagePath = 'wappen/$fileName';
      String? logoUrl;

      // Liegt das Wappen bereits im Storage, wird nur die öffentliche URL
      // wieder in team.image_url eingetragen. Das repariert die NULL-Werte.
      if (storedLogoNames.contains(fileName)) {
        logoUrl = storage.getPublicUrl(imagePath);
      } else {
        // Nur tatsächlich fehlende Wappen neu von SofaScore laden.
        try {
          final imageResponse = await http.get(
            Uri.parse('$baseUrl/team/$teamId/image'),
            headers: _teamSyncHeaders,
          );

          if (imageResponse.statusCode == 429) {
            throw Exception('API_LIMIT_REACHED');
          }
          if (imageResponse.statusCode == 403) {
            throw Exception('API_ACCESS_DENIED');
          }

          if (imageResponse.statusCode == 200 &&
              imageResponse.bodyBytes.isNotEmpty) {
            await storage.uploadBinary(
              imagePath,
              imageResponse.bodyBytes,
              fileOptions: const FileOptions(
                cacheControl: '3600',
                upsert: true,
              ),
            );
            logoUrl = storage.getPublicUrl(imagePath);
            storedLogoNames.add(fileName);
          } else {
            print(
              '⚠️ Kein Wappen für $teamName ($teamId) geladen. '
              'HTTP ${imageResponse.statusCode}',
            );
          }
        } catch (e) {
          if (e.toString().contains('API_LIMIT_REACHED') ||
              e.toString().contains('API_ACCESS_DENIED')) {
            rethrow;
          }
          print('⚠️ Fehler beim Wappen-Download für $teamName ($teamId): $e');
        }
      }

      // Eine bereits in der DB vorhandene URL bei temporären Fehlern behalten.
      if (logoUrl == null) {
        try {
          final existingTeam = await supabaseService.supabase
              .from('team')
              .select('image_url')
              .eq('id', teamId)
              .maybeSingle();
          final existingUrl = existingTeam?['image_url']?.toString().trim();
          if (existingUrl != null && existingUrl.isNotEmpty) {
            logoUrl = existingUrl;
          }
        } catch (e) {
          print('⚠️ Vorhandene image_url für Team $teamId nicht lesbar: $e');
        }
      }

      await supabaseService.saveTeam(teamId, teamName, logoUrl);
      await supabaseService.saveSeasonTeam(seasonId, teamId);

      if (logoUrl == null || logoUrl.isEmpty) {
        teamsWithoutLogo.add('$teamName ($teamId)');
      }
    }

    // Ein unvollständiger Wappen-Sync darf nicht mehr als COMPLETED gelten.
    if (teamsWithoutLogo.isNotEmpty) {
      throw Exception(
        'Team-Sync unvollständig: ${teamsWithoutLogo.length} Team(s) ohne '
        'Wappen-URL: ${teamsWithoutLogo.join(', ')}',
      );
    }

    print(
      '✅ Alle Teams inkl. Wappen (Turnier: $tournamentId, Saison: $seasonId) '
      'wurden gespeichert.',
    );
  }
}
