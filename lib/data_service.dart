//match_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  final String baseUrl = 'https://www.sofascore.com/api/v1';
  final SupabaseService supabaseService = SupabaseService();
  final String tournamentId = '17';

  Future<void> fetchAndStoreTeams(String seasonId) async {
    final url = '$baseUrl/unique-tournament/$tournamentId/season/$seasonId/teams';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final parsedJson = json.decode(response.body);
      List<dynamic> teamsJson = parsedJson['teams'] ?? [];

      for (var teamData in teamsJson) {
        int teamId = teamData['id'];
        String teamName = teamData['name'];
        String? logoUrl;

        try {
          final imageResponse = await http.get(Uri.parse('https://www.sofascore.com/api/v1/team/$teamId/image'));
          if (imageResponse.statusCode == 200) {
            final imageBytes = imageResponse.bodyBytes;
            final imagePath = 'wappen/$teamId.jpg';

            await supabaseService.supabase.storage
                .from('wappen')
                .uploadBinary(
              imagePath,
              imageBytes,
              fileOptions: const FileOptions(
                cacheControl: '3600',
                upsert: true,
              ),
            );

            logoUrl = supabaseService.supabase.storage
                .from('wappen')
                .getPublicUrl(imagePath);
          }
        } catch (e) {
          print('Fehler beim Verarbeiten des Logos für Team-ID $teamId: $e');
        }

        await supabaseService.saveTeam(teamId, teamName, logoUrl);
        // NEU: Speichere die Beziehung in season_teams
        await supabaseService.saveSeasonTeam(int.parse(seasonId), teamId);
      }
      print('Alle Teams wurden erfolgreich in der Datenbank gespeichert.');
    } else {
      throw Exception("Fehler beim Abrufen der Teams: ${response.statusCode}");
    }
  }

  Future<void> fetchAndStoreSpieltage(String seasonId) async {
    final url = '$baseUrl/unique-tournament/$tournamentId/season/$seasonId/rounds';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final parsedJson = json.decode(response.body);
      List<dynamic> roundsJson = parsedJson['rounds'] ?? [];

      for (var round in roundsJson) {
        int roundNumber = int.tryParse(round['round'].toString()) ?? 0;
        await supabaseService.saveSpieltag(roundNumber, 'nicht gestartet', int.parse(seasonId));
      }
    } else {
      throw Exception("Fehler beim Abrufen der Spieltage: ${response.statusCode}");
    }
  }

  Future<void> fetchAndStoreSpiele(int round, String seasonId) async {
    final url = '$baseUrl/unique-tournament/$tournamentId/season/$seasonId/events/round/$round';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final parsedJson = json.decode(response.body);
      List<dynamic> eventsJson = parsedJson['events'] ?? [];
      for (var event in eventsJson) {
        if (event['status'] != null &&
            event['status']['code'] == 60 &&
            event['status']['description'] == "Postponed") {
          continue;
        }
        int matchId = event['id'];
        int homeTeamId = event['homeTeam']['id'];
        int awayTeamId = event['awayTeam']['id'];
        int timestampInt = event['startTimestamp'];
        DateTime startTimestamp = DateTime.fromMillisecondsSinceEpoch(timestampInt * 1000);
        String startTimeString = startTimestamp.toIso8601String();
        String status = event['status']['description'] ?? 'nicht gestartet';
        var homeScore = event['homeScore']?['current'] ?? 0;
        var awayScore = event['awayScore']?['current'] ?? 0;

        String ergebnis = (event['homeScore'] == null || event['awayScore'] == null)
            ? "Noch kein Ergebnis"
            : "$homeScore:$awayScore";

        await supabaseService.saveSpiel(
          matchId,
          startTimeString,
          homeTeamId,
          awayTeamId,
          ergebnis,
          status,
          round,
          int.parse(seasonId), // HINZUGEFÜGT
        );
      }
    } else {
      throw Exception("Fehler beim Abrufen der Spiele für Runde $round: ${response.statusCode}");
    }
  }

  Future<void> fetchAndStoreSpielerundMatchratings(int spielId, int hometeamId, int awayteamId, int seasonId) async {
    final url = 'https://www.sofascore.com/api/v1/event/$spielId/lineups';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      try {
        final parsedJson = json.decode(response.body);

        if (parsedJson['home'] == null || parsedJson['away'] == null) {
          print(">>> FEHLER bei Spiel $spielId: 'home' oder 'away' Sektion in API-Antwort nicht gefunden.");
          return;
        }

        final String homeFormation = parsedJson['home']?['formation'] ?? 'N/A';
        final String awayFormation = parsedJson['away']?['formation'] ?? 'N/A';
        await supabaseService.updateSpielFormation(spielId, homeFormation, awayFormation);

        List<dynamic> homePlayers = parsedJson['home']['players'] ?? [];
        List<dynamic> awayPlayers = parsedJson['away']['players'] ?? [];

        if (homePlayers.isEmpty || awayPlayers.isEmpty) {
          print(">>> WARNUNG bei Spiel $spielId: Eine der Spielerlisten ist leer.");
        }

        for (int i = 0; i < homePlayers.length; i++) {
          await processPlayerData(homePlayers[i], hometeamId, spielId, homeFormation, i, seasonId);
        }
        for (int i = 0; i < awayPlayers.length; i++) {
          await processPlayerData(awayPlayers[i], awayteamId, spielId, awayFormation, i, seasonId);
        }
        print("--- ERFOLGREICH gespeichert für Spiel-ID: $spielId ---");

      } catch (e) {
        print("!!! KRITISCHER FEHLER bei der Verarbeitung von Spiel $spielId: $e");
      }
    } else {
      print(">>> FEHLER bei Spiel $spielId: Konnte Aufstellung nicht von API laden (Statuscode: ${response.statusCode})");
    }
  }

  Future<void> processPlayerData(Map<String, dynamic> playerData, int teamId, int spielId, String formation, int formationIndex, int seasonId) async {
    var player = playerData['player'];
    int playerId = player['id'];
    String playerName = player['name'];
    String apiPosition = player['position'];
    String matchPosition = _getPositionFromFormation(formation, formationIndex);
    String finalPositionsToSave = apiPosition;
    String? imageUrl;

    try {
      final playerResponse = await supabaseService.supabase
          .from('spieler')
          .select('position')
          .eq('id', playerId)
          .maybeSingle();

      String currentPositions = apiPosition;
      if (playerResponse != null && playerResponse['position'] != null) {
        currentPositions = playerResponse['position'];
      }

      List<String> positionList = currentPositions.split(',').map((p) => p.trim()).toList();
      bool positionExists = positionList.contains(matchPosition);

      if(currentPositions.isEmpty){
        if(!['N/A', 'SUB'].contains(matchPosition)){
          finalPositionsToSave = matchPosition;
        } else {
          finalPositionsToSave = await getPlayerPosition(playerId);
        }
      } else if (!positionExists && !['N/A', 'SUB'].contains(matchPosition)) {
        finalPositionsToSave = '$currentPositions, $matchPosition';
      } else {
        finalPositionsToSave = currentPositions;
      }

      final imageResponse = await http.get(Uri.parse('https://www.sofascore.com/api/v1/player/$playerId/image'));
      if (imageResponse.statusCode == 200) {
        final imageBytes = imageResponse.bodyBytes;
        final imagePath = 'spielerbilder/$playerId.jpg';

        await supabaseService.supabase.storage
            .from('spielerbilder')
            .uploadBinary(
          imagePath,
          imageBytes,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: true,
          ),
        );
        imageUrl = supabaseService.supabase.storage
            .from('spielerbilder')
            .getPublicUrl(imagePath);
      }
    } catch (e) {
      print('Fehler beim Überprüfen der Spielerposition für ID $playerId: $e');
    }

    String primaryPosition = player['position'];
    double rating = playerData['statistics']?['rating'] ?? 6.0;
    int punktzahl = ((rating - 6) * 100).round();
    int ratingId = int.parse('$spielId$playerId');
    Map<String, dynamic> stats = playerData['statistics'] as Map<String, dynamic>? ?? {};
    int newRating = buildNewRating(primaryPosition, stats);

    await supabaseService.saveSpieler(playerId, playerName, finalPositionsToSave, teamId, imageUrl);
    // NEU: Beziehung speichern
    await supabaseService.saveSeasonPlayer(seasonId, playerId, teamId);
    await supabaseService.saveMatchrating(ratingId, spielId, playerId, punktzahl, stats, newRating, formationIndex, matchPosition);
  }

  String _getPositionFromFormation(String formation, int index) {
    if (index == 0) return 'TW'; // Index 0 (erster Spieler in der API-Liste) ist immer der Torwart.

    final parts = formation.split('-').map(int.tryParse).where((i) => i != null).cast<int>().toList();
    if (parts.length < 2) return 'N/A'; // Ungültige Formation

    final defenders = parts.first;
    final attackers = parts.last;
    final midfielders = parts.sublist(1, parts.length - 1);


    int defenseEndIndex = defenders;
    if (index > 0 && index <= defenseEndIndex) {
      int posIndex = index;
      if (defenders == 3) return 'IV';
      if (defenders == 4) {
        if (posIndex == 1) return 'RV';
        if (posIndex == 4) return 'LV';
        return 'IV';
      }
      if (defenders == 5) {
        if (posIndex == 1) return 'RV';
        if (posIndex == 5) return 'LV';
        return 'IV';
      }
    }

    int midfieldEndIndex = defenseEndIndex + midfielders.reduce((a, b) => a + b);
    if (index > defenseEndIndex && index <= midfieldEndIndex) {
      int posIndex = index - defenseEndIndex;
      if(midfielders.length == 1) {
        if (midfielders.first > 3){
          if (posIndex == 1) return 'RA';
          if (posIndex == midfielders.first) return 'LA';
        }
        return 'ZM';
      }

      if (posIndex <= midfielders.first){
        if (midfielders.first >= 3) {
          if(posIndex == 1) return 'RV';
          if(posIndex == midfielders.first) return 'LV';
        }
        if (midfielders.first == 3) return 'ZM';
        return 'ZDM';
      }
      if (posIndex <= midfielders[0] + midfielders[1]) {
        if (midfielders[1] >= 3) {
          if (posIndex == midfielders.first + 1) return 'RA';
          if (posIndex == midfielders[0] + midfielders[1]) return 'LA';
          if (midfielders[1] == 3) return 'ZOM';
          return 'ZM';
        }
        if (midfielders.length >= 3) return 'ZM';
        return 'ZOM';
      }
      if (posIndex <= midfielders[0] + midfielders[1]+ midfielders[2]){
        return 'ZOM';
      }
      return 'M';
    }

    int attackerEndIndex = midfieldEndIndex + attackers;
    if (index > midfieldEndIndex && index <= attackerEndIndex) {
      int posIndex = index - midfieldEndIndex;
      if (attackers <= 2) return 'ST';
      if (attackers == 3) {
        if (posIndex == 1) return 'RA';
        if (posIndex == 3) return 'LA';
        return 'ST';
      }
    }
    return 'SUB'; // Fallback für Ersatzspieler
  }

  int buildNewRating(String position, Map<String, dynamic> stats) {
    double bewertung = 0;

    if (position == 'G') {

      if (stats.containsKey('totalPass')) {
        bewertung += 0.002 * (stats['totalPass'] ?? 0);
      }
      if (stats.containsKey('accuratePass')) {
        bewertung += 0.015 * (stats['accuratePass'] ?? 0);
      }
      if (stats.containsKey('totalLongBalls')) {
        bewertung += 0.003 * (stats['totalLongBalls'] ?? 0);
      }
      if (stats.containsKey('accurateLongBalls')) {
        bewertung += 0.03 * (stats['accurateLongBalls'] ?? 0);
      }
      if (stats.containsKey('goalAssist')) {
        bewertung += 0.5 * (stats['goalAssist'] ?? 0);
      }
      if (stats.containsKey('aerialWon')) {
        bewertung += 0.08 * (stats['aerialWon'] ?? 0);
      }
      if (stats.containsKey('aerialLost')) {
        bewertung -= 0.05 * (stats['aerialLost'] ?? 0);
      }
      if (stats.containsKey('duelWon')) {
        bewertung += 0.02 * (stats['duelWon'] ?? 0);
      }
      if (stats.containsKey('duelLost')) {
        bewertung -= 0.02 * (stats['duelLost'] ?? 0);
      }
      if (stats.containsKey('challengeLost')) {
        bewertung -= 0.02 * (stats['challengeLost'] ?? 0);
      }
      if (stats.containsKey('totalContest')) {
        bewertung += 0.01 * (stats['totalContest'] ?? 0);
      }
      if (stats.containsKey('wonContest')) {
        bewertung += 0.02 * (stats['wonContest'] ?? 0);
      }
      if (stats.containsKey('interceptionWon')) {
        bewertung += 0.1 * (stats['interceptionWon'] ?? 0);
      }
      if (stats.containsKey('totalClearance')) {
        bewertung += 0.05 * (stats['totalClearance'] ?? 0);
      }
      if (stats.containsKey('errorLeadToAShot')) {
        bewertung -= 0.3 * (stats['errorLeadToAShot'] ?? 0);
      }
      if (stats.containsKey('errorLeadToAGoal')) {
        bewertung -= 0.75 * (stats['errorLeadToAGoal'] ?? 0);
      }
      if (stats.containsKey('wasFouled')) {
        bewertung += 0.02 * (stats['wasFouled'] ?? 0);
      }
      if (stats.containsKey('goodHighClaim')) {
        bewertung += 0.2 * (stats['goodHighClaim'] ?? 0);
      }
      if (stats.containsKey('totalKeeperSweeper')) {
        bewertung += 0.15 * (stats['totalKeeperSweeper'] ?? 0);
      }
      if (stats.containsKey('accurateKeeperSweeper')) {
        bewertung += 0.25 * (stats['accurateKeeperSweeper'] ?? 0);
      }
      if (stats.containsKey('expectedAssists')) {
        bewertung += 2 * (stats['expectedAssists'] ?? 0);
      }
      if (stats.containsKey('totalTackle')) {
        bewertung += 0.02 * (stats['totalTackle'] ?? 0);
      }
      if (stats.containsKey('lastManTackle')) {
        bewertung += 0.4 * (stats['lastManTackle'] ?? 0);
      }
      if (stats.containsKey('bigChanceCreated')) {
        bewertung += 0.15 * (stats['bigChanceCreated'] ?? 0);
      }
      if (stats.containsKey('penaltySave')) {
        bewertung += 0.75 * (stats['penaltySave'] ?? 0);
      }
      if (stats.containsKey('penaltyConceded')) {
        bewertung -= 0.5 * (stats['penaltyConceded'] ?? 0);
      }
      if (stats.containsKey('fouls')) {
        bewertung -= 0.05 * (stats['fouls'] ?? 0);
      }
      if (stats.containsKey('keyPass')) {
        bewertung += 0.15 * (stats['keyPass'] ?? 0);
      }
      if (stats.containsKey('punches')) {
        bewertung += 0.15 * (stats['punches'] ?? 0);
      }
      if (stats.containsKey('touches')) {
        bewertung += 0.001 * (stats['touches'] ?? 0);
      }
      if (stats.containsKey('possessionLostCtrl')) {
        bewertung -= 0.05 * (stats['possessionLostCtrl'] ?? 0);
      }

      // Spezifische Torhüter-Aktionen (neu hinzugefügt)
      if (stats.containsKey('saves')) {
        bewertung += 0.2 * (stats['saves'] ?? 0); // Wichtiger Punkt für Torhüter
      }
      if (stats.containsKey('goalsConceded')) {
        bewertung -= 0.15 * (stats['goalsConceded'] ?? 0); // Minuspunkte für Gegentore
      }
      if (stats.containsKey('cleanSheet')) {
        bewertung += 1 * (stats['cleanSheet'] ?? 0); // Punkte für "zu Null" spielen
      }
      if(stats.containsKey('shotsFaced')){
        bewertung += 0.02 * (stats['shotsFaced'] ?? 0);
      }

      return (bewertung*50).round();
    }
    else {
      return 0;
    }


    if (position == 'D') {
      if (stats.containsKey('totalPass')) bewertung += 0.005 * stats['totalPass'];
      if (stats.containsKey('accuratePass')) bewertung += 0.005 * stats['accuratePass'];
      if (stats.containsKey('totalLongBalls')) bewertung += 0.05 * stats['totalLongBalls'];
      if (stats.containsKey('accurateLongBalls')) bewertung += 0.05 * stats['accurateLongBalls'];
      if (stats.containsKey('goalAssist')) bewertung += 0.5 * stats['goalAssist'];
      if (stats.containsKey('goals')) bewertung += 1.0 * stats['goals'];
      if (stats.containsKey('totalCross')) bewertung += 0.05 * stats['totalCross'];
      if (stats.containsKey('accurateCross')) bewertung += 0.05 * stats['accurateCross'];
      if (stats.containsKey('aerialLost')) bewertung -= 0.05 * stats['aerialLost'];
      if (stats.containsKey('aerialWon')) bewertung += 0.1 * stats['aerialWon'];
      if (stats.containsKey('duelLost')) bewertung -= 0.05 * stats['duelLost'];
      if (stats.containsKey('duelWon')) bewertung += 0.1 * stats['duelWon'];
      if (stats.containsKey('dispossessed')) bewertung -= 0.1 * stats['dispossessed'];
      if (stats.containsKey('shotOffTarget')) bewertung -= 0.05 * stats['shotOffTarget'];
      if (stats.containsKey('totalClearance')) bewertung += 0.05 * stats['totalClearance'];
      if (stats.containsKey('clearanceOffLine')) bewertung -= 0.1 * stats['clearanceOffLine'];
      if (stats.containsKey('fouls')) bewertung -= 0.1 * stats['fouls'];
      if (stats.containsKey('touches')) bewertung += 0.01 * stats['touches'];
      if (stats.containsKey('possessionLostCtrl')) bewertung -= 0.05 * stats['possessionLostCtrl'];
      if (stats.containsKey('expectedAssists')) bewertung += 1.0 * stats['expectedAssists'];
      if (stats.containsKey('keyPass')) bewertung += 0.2 * stats['keyPass'];
      if (stats.containsKey('totalTackle')) bewertung += 0.1 * stats['totalTackle'];
      if (stats.containsKey('wonContest')) bewertung += 0.05 * stats['wonContest'];
      if (stats.containsKey('challengeLost')) bewertung -= 0.05 * stats['challengeLost'];
      if (stats.containsKey('outfielderBlock')) bewertung += 0.05 * stats['outfielderBlock'];
      if (stats.containsKey('interceptionWon')) bewertung += 0.1 * stats['interceptionWon'];
      if (stats.containsKey('lastManTackle')) bewertung += 0.2 * stats['lastManTackle'];
      if (stats.containsKey('bigChanceCreated')) bewertung += 0.2 * stats['bigChanceCreated'];
      if (stats.containsKey('bigChanceMissed')) bewertung -= 0.2 * stats['bigChanceMissed'];
      if (stats.containsKey('errorLeadToAShot')) bewertung -= 0.2 * stats['errorLeadToAShot'];
      if (stats.containsKey('errorLeadToAGoal')) bewertung -= 0.3 * stats['errorLeadToAGoal'];
    }

    if (position == 'M') {
      if (stats.containsKey('totalPass')) bewertung += 0.008 * stats['totalPass'];
      if (stats.containsKey('accuratePass')) bewertung += 0.017 * stats['accuratePass'];
      if (stats.containsKey('touches')) bewertung += 0.020 * stats['touches'];
      if (stats.containsKey('totalLongBalls')) bewertung += 0.025 * stats['totalLongBalls'];
      if (stats.containsKey('accurateLongBalls')) bewertung += 0.025 * stats['accurateLongBalls'];
      if (stats.containsKey('totalCross')) bewertung += 0.060 * stats['totalCross'];
      if (stats.containsKey('accurateCross')) bewertung += 0.120 * stats['accurateCross'];
      if (stats.containsKey('goalAssist')) bewertung += 0.400 * stats['goalAssist'];
      if (stats.containsKey('keyPass')) bewertung += 0.350 * stats['keyPass'];
      if (stats.containsKey('onTargetScoringAttempt')) bewertung += 0.200 * stats['onTargetScoringAttempt'];
      if (stats.containsKey('goals')) bewertung += 0.600 * stats['goals'];
      if (stats.containsKey('expectedAssists')) bewertung += 1.800 * stats['expectedAssists'];
      if (stats.containsKey('aerialLost')) bewertung -= 0.040 * stats['aerialLost'];
      if (stats.containsKey('aerialWon')) bewertung += 0.060 * stats['aerialWon'];
      if (stats.containsKey('duelLost')) bewertung -= 0.040 * stats['duelLost'];
      if (stats.containsKey('duelWon')) bewertung += 0.060 * stats['duelWon'];
      if (stats.containsKey('totalContest')) bewertung += 0.040 * stats['totalContest'];
      if (stats.containsKey('wonContest')) bewertung += 0.040 * stats['wonContest'];
      if (stats.containsKey('blockedScoringAttempt')) bewertung += 0.120 * stats['blockedScoringAttempt'];
      if (stats.containsKey('outfielderBlock')) bewertung += 0.100 * stats['outfielderBlock'];
      if (stats.containsKey('totalClearance')) bewertung += 0.080 * stats['totalClearance'];
      if (stats.containsKey('interceptionWon')) bewertung += 0.120 * stats['interceptionWon'];
      if (stats.containsKey('totalTackle')) bewertung += 0.120 * stats['totalTackle'];
      if (stats.containsKey('challengeLost')) bewertung -= 0.080 * stats['challengeLost'];
      if (stats.containsKey('fouls')) bewertung -= 0.040 * stats['fouls'];
      if (stats.containsKey('dispossessed')) bewertung -= 0.080 * stats['dispossessed'];
      if (stats.containsKey('totalOffside')) bewertung -= 0.040 * stats['totalOffside'];
      if (stats.containsKey('shotOffTarget')) bewertung -= 0.040 * stats['shotOffTarget'];
      if (stats.containsKey('errorLeadToAGoal')) bewertung -= 0.200 * stats['errorLeadToAGoal'];
      if (stats.containsKey('errorLeadToAShot')) bewertung -= 0.150 * stats['errorLeadToAShot'];
      if (stats.containsKey('bigChanceCreated')) bewertung += 0.350 * stats['bigChanceCreated'];
      if (stats.containsKey('bigChanceMissed')) bewertung -= 0.250 * stats['bigChanceMissed'];
      if (stats.containsKey('possessionLostCtrl')) bewertung -= 0.030 * stats['possessionLostCtrl'];
      if (stats.containsKey('penaltyWon')) bewertung += 0.300 * stats['penaltyWon'];
      if (stats.containsKey('clearanceOffLine')) bewertung += 0.080 * stats['clearanceOffLine'];
      if (stats.containsKey('hitWoodwork')) bewertung += 0.100 * stats['hitWoodwork'];
    }

    if (position == 'F') {
      if (stats.containsKey('totalPass')) bewertung += 0.005 * stats['totalPass'];
      if (stats.containsKey('accuratePass')) bewertung += 0.010 * stats['accuratePass'];
      if (stats.containsKey('totalLongBalls')) bewertung += 0.005 * stats['totalLongBalls'];
      if (stats.containsKey('accurateLongBalls')) bewertung += 0.015 * stats['accurateLongBalls'];
      if (stats.containsKey('keyPass')) bewertung += 0.200 * stats['keyPass'];
      if (stats.containsKey('goalAssist')) bewertung += 0.500 * stats['goalAssist'];
      if (stats.containsKey('expectedAssists')) bewertung += 1.000 * stats['expectedAssists'];
      if (stats.containsKey('expectedGoals')) bewertung += 1.000 * stats['expectedGoals'];
      if (stats.containsKey('totalCross')) bewertung -= 0.050 * stats['totalCross'];
      if (stats.containsKey('accurateCross')) bewertung += 0.200 * stats['accurateCross'];
      if (stats.containsKey('aerialWon')) bewertung += 0.100 * stats['aerialWon'];
      if (stats.containsKey('aerialLost')) bewertung -= 0.100 * stats['aerialLost'];
      if (stats.containsKey('duelWon')) bewertung += 0.050 * stats['duelWon'];
      if (stats.containsKey('duelLost')) bewertung -= 0.050 * stats['duelLost'];
      if (stats.containsKey('challengeLost')) bewertung -= 0.100 * stats['challengeLost'];
      if (stats.containsKey('dispossessed')) bewertung -= 0.150 * stats['dispossessed'];
      if (stats.containsKey('totalContest')) bewertung += 0.020 * stats['totalContest'];
      if (stats.containsKey('wonContest')) bewertung += 0.030 * stats['wonContest'];
      if (stats.containsKey('shotOffTarget')) bewertung -= 0.100 * stats['shotOffTarget'];
      if (stats.containsKey('onTargetScoringAttempt')) bewertung += 0.200 * stats['onTargetScoringAttempt'];
      if (stats.containsKey('blockedScoringAttempt')) bewertung -= 0.050 * stats['blockedScoringAttempt'];
      if (stats.containsKey('bigChanceCreated')) bewertung += 0.300 * stats['bigChanceCreated'];
      if (stats.containsKey('bigChanceMissed')) bewertung -= 0.300 * stats['bigChanceMissed'];
      if (stats.containsKey('errorLeadToAGoal')) bewertung -= 0.500 * stats['errorLeadToAGoal'];
      if (stats.containsKey('errorLeadToAShot')) bewertung -= 0.200 * stats['errorLeadToAShot'];
      if (stats.containsKey('hitWoodwork')) bewertung += 0.200 * stats['hitWoodwork'];
      if (stats.containsKey('penaltyWon')) bewertung += 0.500 * stats['penaltyWon'];
      if (stats.containsKey('penaltyMiss')) bewertung -= 0.300 * stats['penaltyMiss'];
      if (stats.containsKey('totalClearance')) bewertung += 0.030 * stats['totalClearance'];
      if (stats.containsKey('clearanceOffLine')) bewertung -= 0.100 * stats['clearanceOffLine'];
      if (stats.containsKey('interceptionWon')) bewertung += 0.100 * stats['interceptionWon'];
      if (stats.containsKey('totalTackle')) bewertung += 0.100 * stats['totalTackle'];
      if (stats.containsKey('outfielderBlock')) bewertung += 0.100 * stats['outfielderBlock'];
      if (stats.containsKey('touches')) bewertung += 0.005 * stats['touches'];
      if (stats.containsKey('possessionLostCtrl')) bewertung -= 0.050 * stats['possessionLostCtrl'];
      if (stats.containsKey('fouls')) bewertung -= 0.100 * stats['fouls'];
      if (stats.containsKey('totalOffside')) bewertung -= 0.100 * stats['totalOffside'];
    }

    return (bewertung * 100).round();
  }

  Future<String> getPlayerPosition(int playerId) async {
    int currentPage = 0;
    bool hasNextPage = true;

    while (hasNextPage) {
      // Schritt 1: Lade die URLs und die Paginierungs-Info für die aktuelle Seite
      final pageData = await _getLineupUrlsAndPageInfo(playerId, currentPage);
      final lineupUrls = pageData.urls;
      hasNextPage = pageData.hasNextPage; // Aktualisiere, ob es noch eine nächste Seite gibt
      // Schritt 2: Suche in den geladenen URLs nach der Position
      if (lineupUrls.isNotEmpty) {
        final position = await _findPositionInLineups(lineupUrls, playerId);

        // Überprüfe, ob eine Position gefunden wurde
        if (position != 'NOT_FOUND') {
          // Position gefunden! Gib das Ergebnis zurück und beende die Funktion.
          return position;
        }
      }
      currentPage++;
    }

    return 'Position konnte auf keiner der verfügbaren Seiten gefunden werden.';
  }

  Future<({List<String> urls, bool hasNextPage})> _getLineupUrlsAndPageInfo(int playerId, int page) async {
    final playerEventsUrl = 'https://www.sofascore.com/api/v1/player/$playerId/events/last/$page';
    final List<String> lineupUrls = [];

    final response = await http.get(Uri.parse(playerEventsUrl));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> events = data['events'] ?? [];
      final Map<String, dynamic> onBenchMap = data['onBenchMap'] ?? {};
      final Set<String> benchMatchIds = onBenchMap.keys.toSet();
      final bool hasNextPage = data['hasNextPage'] ?? false;

      for (var event in events) {
        final String eventIdString = event['id'].toString();
        if (!benchMatchIds.contains(eventIdString)) {
          final int eventId = event['id'];
          final String lineupUrl = 'https://www.sofascore.com/api/v1/event/$eventId/lineups';
          lineupUrls.add(lineupUrl);
        }
      }
      // Gib sowohl die URLs als auch die Info zur nächsten Seite zurück
      return (urls: lineupUrls, hasNextPage: hasNextPage);
    } else {
      throw Exception('Fehler beim Laden der Spieldaten für Seite $page: ${response.statusCode}');
    }
  }

  Future<String> _findPositionInLineups(List<String> lineupUrls, int playerId) async {
    for (final url in lineupUrls) {
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) continue;

        final data = json.decode(response.body);
        final List<Map<String, dynamic>> teams = [data['home'], data['away']];

        for (final teamData in teams) {
          final String formation = teamData['formation'];
          final List<dynamic> players = teamData['players'];

          for (int i = 0; i < players.length; i++) {
            if (players[i]['player']['id'] == playerId && i <= 10) {
              return _getPositionFromFormation(formation, i);
            }
          }
        }
      } catch (e) {
        continue;
      }
    }
    // Spezieller Rückgabewert, wenn nichts gefunden wurde
    return 'NOT_FOUND';
  }
}

class SupabaseService {
  final SupabaseClient supabase = Supabase.instance.client;

  Future<void> saveSpieltag(int round, String status, int seasonId) async {
    try {
      await supabase.from('spieltag').upsert(
          {
            'round': round,
            'status': status,
            'season_id': seasonId,
          },
          onConflict: 'round, season_id'
      );
    } catch (error) {
      print('Fehler beim Speichern des Spieltags: $error');
    }
  }

  Future<List<int>> fetchAllSpieltagIds(int seasonId) async {
    try {
      final response = await supabase.from('spieltag').select('round').eq('season_id', seasonId);
      return response.map<int>((row) => row['round'] as int).toList();
    } catch (error) {
      print('Fehler beim Abrufen der Spieltag-IDs: $error');
      return [];
    }
  }

  Future<void> saveTeam(int id, String name, String? imageUrl) async {
    try {
      final Map<String, dynamic> teamData = {'id': id, 'name': name};
      if (imageUrl != null) {
        teamData['image_url'] = imageUrl;
      }
      await supabase.from('team').upsert(teamData, onConflict: 'id');
    } catch (error) {
      print('Fehler beim Speichern des Teams: $error');
    }
  }

  Future<void> saveSeasonTeam(int seasonId, int teamId) async {
    try {
      await supabase.from('season_teams').upsert({
        'season_id': seasonId,
        'team_id': teamId,
      }, onConflict: 'season_id, team_id');
    } catch (error) {
      print('Fehler beim Speichern der Team-Saison-Beziehung: $error');
    }
  }

  Future<void> saveSpiel(int id, String datum, int heimteamId, int auswartsteamId, String ergebnis, String status, int round, int seasonId) async {
    try {
      await supabase.from('spiel').upsert({
        'id': id,
        'datum': datum,
        'heimteam_id': heimteamId,
        'auswärtsteam_id': auswartsteamId,
        'ergebnis': ergebnis,
        'round': round,
        'status': null,
        'season_id': seasonId,
      },
          onConflict: 'id'
      );
    } catch (error) {
      print('Fehler beim Speichern des Spiels: $error');
    }
  }

  Future <DateTime> fetchSpieldatum (spielId) async {
    final response = await supabase.from('spiel').select('datum').eq('id', spielId).single();
    return DateTime.parse(response['datum']);
  }

  Future<void> updateSpielStatus(int spielId, String neuerStatus) async {
    await supabase.from('spiel').update({'status': neuerStatus}).eq('id', spielId);
  }

  Future<void> updateSpieltagStatus(int round, String neuerStatus, int seasonId) async {
    await supabase.from('spieltag').update({'status': neuerStatus}).eq('round', round).eq('season_id', seasonId);
  }

  Future<void> saveSpieler(int id, String name, String position, int teamId, String? profilbildUrl) async {
    try {
      final updateData = {'id': id, 'name': name, 'position': position};
      if (profilbildUrl != null) {
        updateData['profilbild_url'] = profilbildUrl;
      }
      await supabase.from('spieler').upsert(updateData, onConflict: 'id');
    } catch (error) {
      print('Fehler beim Speichern des Spielers: $error');
    }
  }

  Future<void> saveSeasonPlayer(int seasonId, int playerId, int teamId) async {
    try {
      await supabase.from('season_players').upsert({
        'season_id': seasonId,
        'player_id': playerId,
        'team_id': teamId,
      }, onConflict: 'season_id, player_id');
    } catch (error) {
      print('Fehler beim Speichern der Spieler-Saison-Beziehung: $error');
    }
  }

  Future<void> saveMatchrating(int id, int spielId, int spielerId, int rating, statistics, int newRating, int formationIndex, String matchPosition) async {
    try {
      await supabase.from('matchrating').upsert({
        'id': id,
        'spiel_id': spielId,
        'spieler_id': spielerId,
        'punkte': rating,
        'statistics': statistics,
        'neuepunkte': newRating,
        'formationsindex': formationIndex,
        'match_position': matchPosition,
      }, onConflict: 'id');
    } catch (error) {
      print("!!! DATENBANK-FEHLER beim Speichern des Matchratings für Spieler $spielerId in Spiel $spielId: $error");
    }
  }

  Future<void> updateSpielFormation(int spielId, String homeFormation, String awayFormation) async {
    try {
      await supabase.from('spiel').update({
        'hometeam_formation': homeFormation,
        'awayteam_formation': awayFormation,
      }).eq('id', spielId);
    } catch (error) {
      print('Fehler beim Speichern der Formationen: $error');
    }
  }

  Future<List<int>> fetchSpielIdsForRound(int round) async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase.from('spiel').select('id').eq('round', round);
      return response.map<int>((spiel) => spiel['id'] as int).toList();
    } catch (error) {
      print('Fehler beim Abrufen der Spiel-IDs: $error');
      return [];
    }
  }

  Future<int> getSpieleranzahl(int spielId, int heimTeamId, int auswaertsTeamId) async {
    final data = await Supabase.instance.client
        .from('spieler')
        .select('*, matchrating!inner(formationsindex, match_position)')
        .eq('matchrating.spiel_id', spielId)
        .filter('team_id', 'in', '($heimTeamId, $auswaertsTeamId)');

    print("--- DEBUG: Rohdaten von Supabase erhalten (${data.length} Spieler) ---");
    return data.length;
  }
}
