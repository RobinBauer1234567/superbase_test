import 'package:flutter/material.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'package:premier_league/utils/color_helper.dart';

class ParsedMatchdayTeamData {
  final String formation;
  final List<PlayerInfo> fieldPlayers;
  final List<PlayerInfo> substitutePlayers;
  final List<int> frozenPlayerIds;

  const ParsedMatchdayTeamData({
    required this.formation,
    required this.fieldPlayers,
    required this.substitutePlayers,
    required this.frozenPlayerIds,
  });
}

int toInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int getPositionOrder(String? position) {
  if (position == null) return 99;
  final pos = position.toUpperCase();
  if (pos.contains('GK') || pos.contains('TW')) return 0;
  if (pos.contains('IV') || pos.contains('RV') || pos.contains('LV')) return 2;
  if (pos.contains('ZDM') || pos.contains('ZM') || pos.contains('ZOM')) return 3;
  if (pos.contains('ST') || pos.contains('RF') || pos.contains('LF')) return 4;
  return 5;
}

ParsedMatchdayTeamData parseMatchdayTeamData(
  Map<String, dynamic> matchdayData,
  Map<String, List<String>> allFormations,
) {
  final pointsData = matchdayData['points_data'] ?? {};
  final playersData = matchdayData['players'] as List<dynamic>? ?? [];

  final teamFormation = pointsData['formation'] ?? '4-4-2';
  final positions = allFormations[teamFormation] ?? List.filled(11, 'POS');

  final field = List<PlayerInfo>.generate(11, (index) {
    if (index == 0) {
      return const PlayerInfo(
        id: -1,
        name: 'TW',
        position: 'TW',
        rating: 0,
        goals: 0,
        assists: 0,
        ownGoals: 0,
      );
    }
    return PlayerInfo(
      id: -1 - index,
      name: positions[index],
      position: positions[index],
      rating: 0,
      goals: 0,
      assists: 0,
      ownGoals: 0,
    );
  });

  final bench = <PlayerInfo>[];
  final frozenIds = <int>[];

  for (final pd in playersData) {
    final spieler = pd['spieler'];
    if (spieler == null) continue;

    final pId = toInt(spieler['id']);
    final fIndex = toInt(pd['formation_index'], fallback: 99);
    final rating = toInt(pd['points'], fallback: 0);

    final playerLocked = pd['is_locked'] ?? false;
    if (playerLocked) {
      frozenIds.add(pId);
    }

    final team = spieler['team'];
    final analytics = spieler['spieler_analytics'];
    int mw = 0;
    int totalSeasonPoints = 0;
    int matchesPlayed = 0;

    if (analytics is Map) {
      mw = toInt(analytics['marktwert']);
      matchesPlayed = toInt(analytics['anzahl_spiele']);
      final stats = analytics['gesamtstatistiken'];
      if (stats is Map) totalSeasonPoints = toInt(stats['gesamtpunkte']);
    } else if (analytics is List && analytics.isNotEmpty) {
      mw = toInt(analytics[0]['marktwert']);
      matchesPlayed = toInt(analytics[0]['anzahl_spiele']);
      final stats = analytics[0]['gesamtstatistiken'];
      if (stats is Map) totalSeasonPoints = toInt(stats['gesamtpunkte']);
    }

    final playerInfo = PlayerInfo(
      id: pId,
      name: (spieler['name'] ?? 'Unbekannt').toString(),
      position: spieler['position'] ?? 'N/A',
      profileImageUrl: spieler['profilbild_url'],
      rating: rating,
      totalSeasonPoints: totalSeasonPoints,
      matchCount: matchesPlayed,
      goals: 0,
      assists: 0,
      ownGoals: 0,
      teamImageUrl: team != null ? team['image_url'] : null,
      marketValue: mw,
      teamName: team != null ? team['name'] : null,
    );

    if (fIndex >= 0 && fIndex <= 10) {
      field[fIndex] = playerInfo;
    } else {
      bench.add(playerInfo);
    }
  }

  bench.sort((a, b) => getPositionOrder(a.position).compareTo(getPositionOrder(b.position)));

  return ParsedMatchdayTeamData(
    formation: teamFormation,
    fieldPlayers: field,
    substitutePlayers: bench,
    frozenPlayerIds: frozenIds,
  );
}

Widget buildMatchdayPlayerCard(
  BuildContext context,
  Map<String, dynamic> playerData, {
  required void Function(int playerId) onPlayerTap,
}) {
  final spieler = playerData['spieler'] ?? {};
  final avatarUrl = spieler['profilbild_url'] ?? '';
  final playerId = toInt(spieler['id']);

  final isLocked = playerData['is_locked'] == true;
  final points = playerData['points'] ?? 0;

  final pointsColor = isLocked ? getColorForRating(points, 250) : Colors.grey;
  final pointsText = isLocked ? '$points' : '-';

  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: Colors.grey.shade200,
        backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
        child: avatarUrl.isEmpty ? Icon(Icons.person, color: Colors.grey.shade400) : null,
      ),
      title: Text(
        spieler['name'] ?? 'Unbekannt',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Text(
        spieler['position'] ?? 'N/A',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isLocked ? pointsColor.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isLocked ? pointsColor.withOpacity(0.3) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          pointsText,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isLocked ? pointsColor : Colors.grey.shade600,
          ),
        ),
      ),
      onTap: () {
        if (playerId > 0) {
          onPlayerTap(playerId);
        }
      },
    ),
  );
}

List<Widget> buildTeamPlayerListSections(
  BuildContext context,
  Map<String, dynamic> currentMatchdayData, {
  required void Function(int playerId) onPlayerTap,
  EdgeInsets startHeaderPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  EdgeInsets benchHeaderPadding = const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
}) {
  final players = List<Map<String, dynamic>>.from(currentMatchdayData['players']);
  players.sort((a, b) => (a['formation_index'] as int).compareTo(b['formation_index'] as int));

  final startingXI = players.where((p) => (p['formation_index'] as int) <= 10).toList();
  final bench = players.where((p) => (p['formation_index'] as int) > 10).toList();

  final items = <Widget>[];
  if (startingXI.isNotEmpty) {
    items.add(
      Padding(
        padding: startHeaderPadding,
        child: const Text(
          'Startelf',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
        ),
      ),
    );
    items.addAll(
      startingXI.map(
        (p) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: buildMatchdayPlayerCard(context, p, onPlayerTap: onPlayerTap),
        ),
      ),
    );
  }
  if (bench.isNotEmpty) {
    items.add(
      Padding(
        padding: benchHeaderPadding,
        child: const Text(
          'Bank',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
        ),
      ),
    );
    items.addAll(
      bench.map(
        (p) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: buildMatchdayPlayerCard(context, p, onPlayerTap: onPlayerTap),
        ),
      ),
    );
  }
  return items;
}
