import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:premier_league/utils/season_order.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Discovers exactly one season per tournament: the newest season currently
/// returned by SofaScore. Historical seasons are never imported by discovery;
/// initialized historical rows already stored in Supabase remain untouched.
class LatestSeasonDiscoveryService {
  LatestSeasonDiscoveryService({
    SupabaseClient? supabase,
    http.Client? httpClient,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _httpClient = httpClient ?? http.Client();

  final SupabaseClient _supabase;
  final http.Client _httpClient;

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 '
        'Mobile/15E148 Safari/604.1',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7',
  };

  Future<void> checkLatestSeason(int tournamentId) async {
    final uri = Uri.parse(
      'https://api.sofascore.com/api/v1/unique-tournament/$tournamentId/seasons',
    );

    final response = await _httpClient
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 429) {
      throw Exception('API_LIMIT_REACHED');
    }
    if (response.statusCode == 403) {
      throw Exception('API_ACCESS_DENIED');
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Season-Check fehlgeschlagen: HTTP ${response.statusCode}',
      );
    }

    final decoded = json.decode(utf8.decode(response.bodyBytes));
    final raw = decoded['seasons'];
    if (raw is! List || raw.isEmpty) {
      throw const FormatException('Keine gültige Saisonliste erhalten');
    }

    final discovered = raw
        .map(
          (season) => discoveredSeason(
            tournamentId,
            Map<String, dynamic>.from(season as Map),
          ),
        )
        .toList(growable: false);

    final latest = sortedSeasons(discovered).first;

    // Ignore duplicates so an already initialized/current row can never have
    // its lifecycle flags reset by discovery.
    await _supabase.from('season').upsert(
      latest,
      onConflict: 'id',
      ignoreDuplicates: true,
    );
  }
}
