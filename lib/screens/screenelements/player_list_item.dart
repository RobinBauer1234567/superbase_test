// lib/screens/screenelements/player_list_item.dart
import 'package:flutter/material.dart';
import 'package:premier_league/utils/color_helper.dart';

class PlayerListItem extends StatelessWidget {
  final int rank;
  final String? profileImageUrl;
  final String playerName;
  final String? teamImageUrl;
  final int score;
  final int maxScore;
  final VoidCallback onTap;

  const PlayerListItem({
    super.key,
    required this.rank,
    this.profileImageUrl,
    required this.playerName,
    this.teamImageUrl,
    required this.score,
    required this.maxScore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 80,
        child: Row(
          children: [
            Text(
              '$rank.',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey),
            ),
            const SizedBox(width: 10),
            CircleAvatar(
              backgroundImage:
              profileImageUrl != null ? NetworkImage(profileImageUrl!) : null,
              child: profileImageUrl == null ? const Icon(Icons.person) : null,
            ),
          ],
        ),
      ),
      title: Text(playerName),
      trailing: SizedBox(
        width: 80,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (teamImageUrl != null)
              Image.network(
                teamImageUrl!,
                width: 24,
                height: 24,
                errorBuilder: (c, e, s) => const Icon(Icons.shield, size: 24),
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
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}