import 'package:flutter/material.dart';
import 'package:premier_league/models/player.dart';

class PlayerScreen extends StatelessWidget {
  final Player player;

  PlayerScreen({required this.player});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(player.name)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Team: ${player.team}", style: TextStyle(fontSize: 18)),
            Text("Position: ${player.position}", style: TextStyle(fontSize: 18)),
            Text("Liga: ${player.league}", style: TextStyle(fontSize: 18)),
            SizedBox(height: 16),
            Text("Match Ratings:", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView(
                children: player.matchRatings.entries.map((entry) {
                  return ListTile(
                    title: Text("Match ID: ${entry.key}"),
                    trailing: Text("Rating: ${entry.value.toStringAsFixed(1)}"),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
