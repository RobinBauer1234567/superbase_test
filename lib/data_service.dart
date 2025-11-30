//match_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

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

  Future<void> updateSpielData(int seasonId, int spielId, status) async {
    final url = '$baseUrl/event/$spielId';
    print (url);
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final parsedJson = json.decode(response.body);

        var homeScore = parsedJson['event']['homeScore']?['current'] ?? 0;
        var awayScore = parsedJson['event']['awayScore']?['current'] ?? 0;

        String ergebnis = (parsedJson['event']['homeScore'] == null ||
            parsedJson['event']['awayScore'] == null)
            ? "Noch kein Ergebnis"
            : "$homeScore:$awayScore";
        await supabaseService.updateSpiel(
            spielId,
            ergebnis,
            status
        );
      }

  }

  Future<void> fetchAndStoreSpielerundMatchratings(int spielId, int hometeamId, int awayteamId, int seasonId) async {
    final url = 'https://www.sofascore.com/api/v1/event/$spielId/lineups';
    final response = await http.get(Uri.parse(url));

    // --- KORREKTUR FÜR 404 ---
    // Wenn die API eine 404 (Not Found) zurückgibt, gibt es (noch) keine Aufstellung.
    if (response.statusCode == 404) {
      print(">>> INFO bei Spiel $spielId: Keine Aufstellung von API verfügbar (Statuscode: 404). Spiel wird übersprungen.");
      return; // Beende die Funktion hier, es gibt nichts zu verarbeiten.
    }
    // --- ENDE KORREKTUR 404 ---

    if (response.statusCode == 200) {
      try {
        final parsedJson = json.decode(response.body);

        if (parsedJson['home'] == null || parsedJson['away'] == null) {
          print(">>> FEHLER bei Spiel $spielId: 'home' oder 'away' Sektion in API-Antwort nicht gefunden.");
          return;
        }

        final String homeFormation = parsedJson['home']?['formation'] ?? 'N/A';
        final String awayFormation = parsedJson['away']?['formation'] ?? 'N/A';

        // --- KORREKTUR DER REIHENFOLGE ---
        // 1. Stelle sicher, dass die Formationen in der DB existieren, BEVOR du sie verwendest.
        await ensureFormationExists(homeFormation);
        await ensureFormationExists(awayFormation);

        // 2. Jetzt, da die Formationen garantiert existieren, aktualisiere das Spiel.
        // Der Foreign Key-Fehler wird nicht mehr auftreten.
        await supabaseService.updateSpielFormation(spielId, homeFormation, awayFormation);
        // --- ENDE KORREKTUR ---

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
    String matchPosition = await _getPositionFromFormation(formation, formationIndex);
    String finalPositionsToSave = '';
    String? imageUrl;
    int? marktwert;

    try {
      final playerResponse = await supabaseService.supabase
          .from('spieler')
          .select('position')
          .eq('id', playerId)
          .maybeSingle();

      String currentPositions = playerResponse?['position'] ?? '';

      List<String> positionList = (currentPositions.isNotEmpty)
          ? currentPositions.split(',').map((p) => p.trim()).toList()
          : [];

      positionList.remove('N/V');
      bool positionExists = positionList.contains(matchPosition);


      if (positionList.isEmpty) {
        if (!['N/A', 'SUB'].contains(matchPosition)) {
          finalPositionsToSave = matchPosition ?? '';
        } else {
          final fetchedPosition = await getPlayerPosition(playerId);
          finalPositionsToSave = fetchedPosition ?? '';
        }
      } else if (!positionExists && !['N/A', 'SUB'].contains(matchPosition)) {
        finalPositionsToSave = '$currentPositions, $matchPosition';
      } else {
        finalPositionsToSave = currentPositions;
      }
      final existingPlayer = await supabaseService.supabase
          .from('spieler')
          .select('marktwert')
          .eq('id', playerId)
          .maybeSingle();

      if (existingPlayer == null || existingPlayer['marktwert'] == null) {
        print('Initialisiere Marktwert für Spieler $playerId ...');
        marktwert = await _calculateInitialMarketValue(playerId);
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

    await supabaseService.saveSpieler(
        playerId,
        playerName,
        finalPositionsToSave,
        teamId,
        imageUrl,
        marktwert
    );
    await supabaseService.saveSeasonPlayer(seasonId, playerId, teamId);
    await supabaseService.saveMatchrating(ratingId, spielId, playerId, punktzahl, stats, newRating, formationIndex, matchPosition);
  }

  Future<String> _getPositionFromFormation(String formation, int index) async {
    if (index > 10) return 'SUB'; // Ersatzspieler
    if (index == 0) return 'TW'; // Torwart
    if (formation == 'N/A') return 'N/A'; // Keine Formation

    try {
      // 1. Prüfen, ob die Formation existiert
      final existing = await supabaseService.supabase
          .from('formation')
          .select('positionsliste')
          .eq('formation', formation)
          .maybeSingle();

      List<String> positionsList;

      if (existing != null && existing['positionsliste'] != null) {
        // Fall A: Formation existiert, nutze die Liste
        positionsList = List<String>.from(existing['positionsliste'] as List);
      } else {
        // Fall B: Formation existiert nicht, erstelle sie
        positionsList = await _createFormationEntry(formation);
      }

      // 4. Position aus der Liste zurückgeben
      if (index < positionsList.length) {
        return positionsList[index];
      }
      return 'N/A'; // Sollte nicht passieren
    } catch (e, st) {
      print('Error in _getPositionFromFormation: $e\n$st');
      // Fallback auf die reine Rechenfunktion bei DB-Fehler
      return ApiService()._computePositionFromFormation(formation, index);
    }
  }

  Future<List<String>> _createFormationEntry(String formation) async {
    // 2. Positionsliste berechnen
    final List<String> positionsList = List.generate(11, (i) {
      return _computePositionFromFormation(formation, i);
    });

    // 3. In DB speichern
    try {
      await supabaseService.supabase.from('formation').insert({
        'formation': formation,
        'positionsliste': positionsList,
      });
    } catch (e) {
      // Ignoriert den Fehler, wenn die Formation bereits existiert (Race Condition)
      if (e is PostgrestException && e.code == '23505') { // 23505 = unique_violation
        // Bereits von einem anderen Prozess hinzugefügt, alles gut.
      } else {
        print('Fehler beim Speichern der Formation $formation: $e');
      }
    }
    return positionsList;
  }
  Future<void> ensureFormationExists(String formation) async {
    if (formation == 'N/A' || formation.isEmpty) return; // 'N/A' nicht speichern

    // 1. Prüfen, ob die Formation bereits existiert
    final existing = await supabaseService.supabase
        .from('formation')
        .select('formation')
        .eq('formation', formation)
        .maybeSingle();

    // 2. Wenn nicht, erstelle sie
    if (existing == null) {
      await _createFormationEntry(formation);
    }
  }
  String _computePositionFromFormation(String formation, int index) {
    if (index == 0) return 'TW'; // Torwart

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
      final pageData = await _getLineupUrlsAndPageInfo(playerId, currentPage);
      final lineupUrls = pageData.urls;
      hasNextPage = pageData.hasNextPage;

      if (lineupUrls.isNotEmpty) {
        final position = await _findPositionInLineups(lineupUrls, playerId);
        if (position != 'NOT_FOUND') {
          return position;
        }
      }
      currentPage++;
    }

    final position = await guessPlayerPosition(playerId);
    return position ?? 'N/V';
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
          final String? formation = teamData['formation'];
          final List<dynamic>? players = teamData['players'];

          if (formation == null || players == null) continue;

          for (int i = 0; i < players.length; i++) {
            final player = players[i]['player'];
            if (player != null && player['id'] == playerId && i <= 10) {
              return _getPositionFromFormation(formation, i);
            }
          }
        }
      } catch (_) {
        continue;
      }
    }
    return 'NOT_FOUND';
  }

  Future<String> guessPlayerPosition(int playerId) async {
    try {
      final playerData = 'https://www.sofascore.com/api/v1/player/$playerId';
      final response = await http.get(Uri.parse(playerData));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // 🧩 Sichere Zuweisung
        final String? position = data['player']['position'] as String?;
        if (position == null) {
          print('⚠️ Keine Position gefunden für Spieler $playerId');
          return 'N/V';
        }


        switch (position) {
          case 'G':
            return 'TW';
          case 'D':
            return 'IV';
          case 'M':
            return 'ZM';
          case 'F':
            return 'ST';
          default:
            return 'N/V';
        }
      } else {
        print('⚠️ guessPlayerPosition Fehler HTTP ${response.statusCode}');
        return 'N/V';
      }
    } catch (e) {
      print('❌ Fehler in guessPlayerPosition($playerId): $e');
      return 'N/V';
    }
  }

  Future<http.Response> _throttledGet(String url) async {
    // 1. Pause vor JEDER Anfrage (z.B. 300ms), um die API nicht zu fluten
    await Future.delayed(const Duration(milliseconds: 300));

    int retryCount = 0;
    while (retryCount < 3) {
      try {
        final response = await http.get(Uri.parse(url));

        // Wenn erfolgreich, zurückgeben
        if (response.statusCode == 200) {
          return response;
        }
        // Wenn wir zu schnell waren (429) oder geblockt wurden (403), länger warten
        else if (response.statusCode == 429 || response.statusCode == 403) {
          print('⚠️ API-Limit erreicht ($url). Warte 5 Sekunden...');
          await Future.delayed(const Duration(seconds: 5));
          retryCount++;
        } else {
          // Anderer Fehler -> Abbruch
          return response;
        }
      } catch (e) {
        print('Netzwerkfehler: $e. Retry...');
        await Future.delayed(const Duration(seconds: 2));
        retryCount++;
      }
    }
    throw Exception('Failed to fetch $url after retries');
  }

  Future<int?> _calculateInitialMarketValue(int playerId) async {
    try {
      final response = await _throttledGet('https://www.sofascore.com/api/v1/player/$playerId/events/last/0');

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final List<dynamic> events = data['events'] ?? [];

      final recentEvents = events.toList();
      if (recentEvents.isEmpty) return null;

      List<int> punkte = [];

      // 2. Details (Rating) für jedes dieser Spiele holen
      for (var event in recentEvents) {
        String eventId = event['id'].toString();
        // AUCH HIER: Gedrosselter Aufruf für die Lineups
        final lineupResp = await _throttledGet('https://www.sofascore.com/api/v1/event/$eventId/lineups');

        if (lineupResp.statusCode == 200) {
          final lineupData = json.decode(lineupResp.body);
          // Finde den Spieler in Heim- oder Auswärtsteam
          final allPlayers = [
            ...(lineupData['home']?['players'] ?? []),
            ...(lineupData['away']?['players'] ?? [])
          ];

          final playerStats = allPlayers.firstWhere(
                  (p) => p['player']['id'] == playerId,
              orElse: () => null
          );

          if (playerStats != null) {
            double rating = playerStats['statistics']?['rating'] ?? 6.0;
            // Deine Punkteformel
            punkte.add(((rating - 6) * 100).round());
          }
        }
      }

      if (punkte.isEmpty) return null;

      // Durchschnitt berechnen
      double avgPoints = punkte.reduce((a, b) => a + b) / punkte.length;
      double calculatedMarktwert =  15000 * pow(avgPoints, 1.5) + 1000000;
      return calculatedMarktwert.round();

    } catch (e) {
      print('Fehler bei Marktwertberechnung für $playerId: $e');
      return null;
    }
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
        'status': 'nicht gestartet',
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

  Future<void> updateSpiel(int spielId,String ergebnis, String neuerStatus) async {
    await supabase.from('spiel').update({'ergebnis': ergebnis}).eq('id', spielId);
    await supabase.from('spiel').update({'status': neuerStatus}).eq('id', spielId);
  }

  Future<void> updateSpieltagStatus(int round, String neuerStatus, int seasonId) async {
    await supabase.from('spieltag').update({'status': neuerStatus}).eq('round', round).eq('season_id', seasonId);
  }

  Future<void> saveSpieler(int id, String name, String position, int teamId, String? profilbildUrl, int? marktwert) async {
    try {
      final updateData = {'id': id, 'name': name, 'position': position};
      if (profilbildUrl != null) {
        updateData['profilbild_url'] = profilbildUrl;
      }
      if (marktwert != null) {
        updateData['marktwert'] = marktwert;
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

  Future<Map<String, List<String>>> fetchFormationsFromDb({SupabaseClient? client}) async {
    final supabase = client ?? Supabase.instance.client;

    try {
      final response = await supabase
          .from('formation')
          .select('formation, positionsliste');

      // Falls Supabase ein Fehlerobjekt statt List zurückgibt, fange das auf:
      if (response == null) return {};

      final Map<String, List<String>> result = {};

      // response ist üblicherweise List<Map<String, dynamic>>
      if (response is List) {
        for (final row in response) {
          if (row == null) continue;
          final String? name = (row['formation'] ?? row['formation_name'])?.toString();
          final dynamic rawPositions = row['positionsliste'];

          if (name == null) continue;

          List<String> positions = [];

          if (rawPositions == null) {
            // nichts vorhanden => skip
            continue;
          }

          // Falls DB schon ein JSON-Array zurückgibt
          if (rawPositions is List) {
            positions = rawPositions.map((e) => e.toString()).toList();
          } else if (rawPositions is String) {
            // rawPositions könnte ein JSON-encoded string oder ein CSV-String sein
            // Versuch JSON zuerst:
            try {
              final decoded = jsonDecode(rawPositions);
              if (decoded is List) {
                positions = decoded.map((e) => e.toString()).toList();
              } else if (decoded is String) {
                // selten: JSON-string mit Komma-liste
                positions = decoded.split(',').map((s) => s.trim()).toList();
              } else {
                // fallback
                positions = rawPositions.split(',').map((s) => s.trim()).toList();
              }
            } catch (_) {
              // kein JSON -> als Komma-getrennte Liste parsen
              positions = rawPositions.split(',').map((s) => s.trim()).toList();
            }
          } else {
            // Sonstiger Typ (z.B. Map) -> versuche vernünftige Extraktion
            try {
              final jsonString = jsonEncode(rawPositions);
              final decoded = jsonDecode(jsonString);
              if (decoded is List) {
                positions = decoded.map((e) => e.toString()).toList();
              }
            } catch (_) {
              // leave empty
            }
          }

          if (positions.isNotEmpty) {
            result[name] = positions;
          }
        }
      }

      return result;
    } catch (e, st) {
      // debug-Ausgabe, falls nötig
      print('fetchFormationsFromDb error: $e\n$st');
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getPublicLeagues() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    try {
      // Hole zuerst die IDs der Ligen, in denen der User bereits ist
      final userLeaguesResponse = await supabase
          .from('league_members')
          .select('league_id')
          .eq('user_id', user.id);

      final List<int> joinedLeagueIds = userLeaguesResponse.map<int>((e) => e['league_id'] as int).toList();

      var query = supabase
          .from('leagues')
          .select()
          .eq('is_public', true);

      // Filtere die Ligen heraus, in denen der User schon ist
      if (joinedLeagueIds.isNotEmpty) {
        query = query.not('id', 'in', joinedLeagueIds);
      }

      final publicLeaguesResponse = await query;
      return List<Map<String, dynamic>>.from(publicLeaguesResponse);

    } catch (error) {
      print('Fehler beim Laden öffentlicher Ligen: $error');
      return [];
    }
  }


  Future<int> createLeague({required String name, required double startingBudget, required int seasonId, required bool isPublic, required int? squadLimit, required int numStartingPlayers, required double startingTeamValue,}) async {
    try {
      // Wir erwarten jetzt einen Rückgabewert (die ID)
      final response = await supabase.rpc('create_league_and_add_admin', params: {
        'league_name': name,
        'start_budget': startingBudget,
        's_id': seasonId,
        'is_league_public': isPublic,
        'squad_limit': squadLimit,
        'num_starting_players': numStartingPlayers,
        'starting_team_value': startingTeamValue,
      });
      return response as int;
    } catch (error) {
      print('Fehler beim Erstellen der Liga: $error');
      throw Exception('Liga konnte nicht erstellt werden: $error');
    }
  }

  Future<void> joinLeague(int leagueId) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Nicht angemeldet');

    try {
      await supabase.rpc('join_league', params: {'p_league_id': leagueId});
    } catch (error) {
      print('Fehler beim Beitreten: $error');
      throw Exception('Fehler beim Beitreten der Liga: $error');
    }
  }

  Future<List<Map<String, dynamic>>> getLeagueRanking(int leagueId) async {
    try {
      final response = await supabase.rpc(
        'get_league_ranking',
        params: {'p_league_id': leagueId},
      );
      // Die RPC-Antwort ist direkt die Liste der Ergebnisse
      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      print('Fehler beim Laden des Rankings: $error');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getLeaguesForUser() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    try {
      // 'id' wird jetzt explizit mit abgefragt
      final response = await supabase
          .from('league_members')
          .select('id, leagues(*), position')
          .eq('user_id', user.id)
          .order('position', ascending: true);

      // Explizite Typ-Umwandlung, um den Fehler zu beheben
      final leaguesData = List<Map<String, dynamic>>.from(response);

      return leaguesData.map((entry) {
        // Sicherstellen, dass die verknüpften Liga-Daten korrekt behandelt werden
        final leagueData = entry['leagues'] as Map<String, dynamic>? ?? {};

        return {
          ...leagueData, // Fügt alle Daten der Liga hinzu (id, name, etc.)
          'position': entry['position'], // Fügt die Sortierposition hinzu
          'league_member_id': entry['id'], // Fügt die ID der Mitgliedschaft hinzu
        };
      }).toList();

    } catch (error) {
      print('Fehler beim Laden der Ligen: $error');
      return [];
    }
  }

  Future<void> updateUserLeagueOrder(List<Map<String, dynamic>> orderedLeagues) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Wir gehen die Liste durch und senden für jede Liga ein separates Update.
      // Das ist effizient und umgeht das Problem mit der ID-Spalte.
      for (int i = 0; i < orderedLeagues.length; i++) {
        final league = orderedLeagues[i];
        await supabase
            .from('league_members')
            .update({'position': i}) // Setze die neue Position
            .match({'user_id': user.id, 'league_id': league['id']}); // Finde die korrekte Zeile
      }
    } catch (error) {
      print('Fehler beim Speichern der Liga-Reihenfolge: $error');
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
      // Wir werfen den Fehler weiter, damit der Aufrufer ihn bemerkt
      throw error;
    }
  }

  Future<List<Map<String, dynamic>>> fetchPlayerGameHistoryForSeason({required int playerId, required int teamId, required int seasonId,}) async {
    try {
      final response = await supabase
          .from('spiel')
          .select('''
            id,
            round,
            status,
            hometeam:team!spiel_hometeam_id_fkey(name, image_url),
            awayteam:team!spiel_awayteam_id_fkey(name, image_url),
            hometeam_score,
            awayteam_score,
            matchrating (
              punkte,
              match_position
            )
          ''')
          .eq('season_id', seasonId)
          .or('hometeam_id.eq.$teamId,awayteam_id.eq.$teamId')
      // Filtere die verschachtelte matchrating-Tabelle nach unserem Spieler
          .eq('matchrating.spieler_id', playerId)
          .order('round', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Fehler in fetchPlayerGameHistoryForSeason: $e');
      return [];
    }
  }
// Füge das zu deiner SupabaseService Klasse hinzu


  Future<List<Map<String, dynamic>>> fetchUserLeaguePlayers(int leagueId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final response = await supabase
          .from('league_players')
          .select('''
          formation_index, 
          player:spieler(
            *, 
            gesamtstatistiken,
            season_players!inner(team:team(*))
          )
        ''')
          .eq('league_id', leagueId)
          .eq('user_id', user.id);

      // Wir flachen die Struktur etwas ab, damit der Rest der App wie gewohnt funktioniert
      return List<Map<String, dynamic>>.from(response.map((e) {
        final player = e['player'] as Map<String, dynamic>;
        final team = (player['season_players'] as List).isNotEmpty
            ? player['season_players'][0]['team']
            : null;

        return {
          ...player,
          'formation_index': e['formation_index'], // <--- WICHTIG: Der Index aus der DB
          'team_image_url': team?['image_url'],
          'team_name': team?['name'],
        };
      }));
    } catch (e) {
      print('Fehler beim Laden des Kaders: $e');
      return [];
    }
  }

  Future<String?> fetchUserFormation(int leagueId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final response = await supabase
          .from('league_members')
          .select('formation')
          .eq('league_id', leagueId)
          .eq('user_id', user.id)
          .maybeSingle();

      return response?['formation'] as String?;
    } catch (e) {
      print('Fehler beim Laden der Formation: $e');
      return null;
    }
  }

  Future<void> updateUserFormation(int leagueId, String formation) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase
          .from('league_members')
          .update({'formation': formation})
          .eq('league_id', leagueId)
          .eq('user_id', user.id);
    } catch (e) {
      print('Fehler beim Speichern der Formation: $e');
    }
  }

  Future<void> saveTeamLineup(int leagueId, List<Map<String, dynamic>> lineupUpdates) async {
    try {
      await supabase.rpc('save_lineup', params: {
        'p_league_id': leagueId,
        'p_updates': lineupUpdates,
      });
    } catch (e) {
      print("Fehler beim Speichern der Aufstellung RPC: $e");
      // Fallback falls RPC noch nicht existiert (nicht empfohlen für Produktion, aber gut zum Testen):
      // Man könnte hier einzeln updaten, aber RPC ist viel besser.
    }
  }
  // 2. Gebot abgeben
  Future<void> placeBid(int transferId, int amount) async {
    try {
      await supabase.from('transfer_bids').insert({
        'transfer_id': transferId,
        'bidder_id': supabase.auth.currentUser!.id,
        'amount': amount,
      });
    } catch (e) {
      print("Fehler beim Bieten: $e");
      throw e; // Weiterwerfen für UI-Handling
    }
  }

  // 3. Sofortkauf (RPC Aufruf)
  Future<void> buyPlayerNow(int transferId) async {
    try {
      await supabase.rpc('buy_player_now', params: {'p_transfer_id': transferId});
    } catch (e) {
      print("Fehler beim Sofortkauf: $e");
      throw e;
    }
  }

  // 4. Spieler auf den Markt stellen (Verkaufen)
  Future<void> listPlayerOnMarket(int leagueId, int playerId, int price) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Hole aktuellen Marktwert für min_bid
    final playerRes = await supabase.from('spieler').select('marktwert').eq('id', playerId).single();
    final int mw = playerRes['marktwert'];

    await supabase.from('transfer_market').insert({
      'league_id': leagueId,
      'player_id': playerId,
      'seller_id': user.id,
      'buy_now_price': price, // User Wunschpreis
      'min_bid_price': mw,    // Startgebot ist immer Marktwert
      'expires_at': DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
      'is_active': true,
    });
  }

  // 5. TEST-FUNKTION: System-Spieler generieren (ruft deinen RPC auf)
// lib/data_service.dart

  // 5. TEST-FUNKTION: System-Spieler generieren
  Future<void> simulateSystemTransfers(int leagueId, int seasonId) async { // <--- seasonId hinzugefügt
    await supabase.rpc('generate_daily_transfers', params: {
      'p_league_id': leagueId,
      'p_season_id': seasonId, // <--- Parameter übergeben
      'p_amount': 5
    });
  }
  // 1. Transfermarkt laden (Nur aktive Angebote)
  Future<List<Map<String, dynamic>>> fetchTransferMarket(int leagueId) async {
    try {
      final response = await supabase
          .from('transfer_market')
          .select('''
            *,
            player:spieler(
              *,
              season_players(team(image_url)), 
              gesamtstatistiken
            )
          ''')
          .eq('league_id', leagueId)
          .eq('is_active', true)
          .order('expires_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("Fehler beim Laden des Transfermarkts: $e");
      return [];
    }
  }
}