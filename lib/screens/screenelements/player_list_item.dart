// lib/screens/screenelements/player_list_item.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/utils/color_helper.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';

class PlayerListItem extends StatelessWidget {
  final int rank;
  final String? profileImageUrl;
  final String playerName;
  final String? teamImageUrl;
  final int score;
  final int maxScore;
  final int? marketValue;
  final VoidCallback onTap;

  final String position;
  final int id;
  final int goals;
  final int assists;
  final int ownGoals;
  final Color? teamColor;

  const PlayerListItem({
    super.key,
    required this.rank,
    this.profileImageUrl,
    required this.playerName,
    this.teamImageUrl,
    required this.score,
    required this.maxScore,
    this.marketValue,
    required this.onTap,
    required this.position,
    this.id = 0,
    this.goals = 0,
    this.assists = 0,
    this.ownGoals = 0,
    this.teamColor,
  });

  String _formatMarketValue(int? value) {
    if (value == null) return '-';
    final formatter = NumberFormat.decimalPattern('de_DE');
    return '${formatter.format(value)} €';
  }

  @override
  Widget build(BuildContext context) {
    final playerInfo = PlayerInfo(
      id: id,
      name: playerName,
      position: position,
      profileImageUrl: profileImageUrl,
      rating: score,
      goals: goals,
      assists: assists,
      ownGoals: ownGoals,
      maxRating: maxScore,
    );

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      leading: SizedBox(
        // KORREKTUR: Mehr Platz, damit nichts abschneidet
        width: 90,
        child: Row(
          mainAxisSize: MainAxisSize.min, // WICHTIG
          children: [
            SizedBox(
              width: 25,
              child: Text(
                '$rank.',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 4),

            // KORREKTUR: Kompakter Avatar ohne Name/Rating
            PlayerAvatar(
              player: playerInfo,
              teamColor: teamColor ?? Colors.blueGrey,
              radius: 20,
              showDetails: false, // <--- Das verhindert den Overflow nach unten!
            ),
          ],
        ),
      ),
      title: Text(playerName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: (teamImageUrl != null && marketValue != null)
          ? Text(_formatMarketValue(marketValue), style: const TextStyle(fontSize: 12, color: Colors.grey))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (teamImageUrl != null)
            Image.network(
              teamImageUrl!,
              width: 24,
              height: 24,
              errorBuilder: (c, e, s) => const Icon(Icons.shield, size: 24),
            )
          else if (marketValue != null)
            Text(
              _formatMarketValue(marketValue),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),

          const SizedBox(width: 8),

          Container(
            width: 40,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: getColorForRating(score, maxScore),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              score.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}