import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/provider/player_provider.dart';
import 'package:premier_league/models/player.dart';

class PlayerScreen extends StatefulWidget {
  @override
  _PlayerScreenState createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        Provider.of<PlayerProvider>(context, listen: false).fetchPlayers());
  }

  @override
  Widget build(BuildContext context) {
    final playerProvider = Provider.of<PlayerProvider>(context);

    return Scaffold(
      appBar: AppBar(title: Text("Top Spieler")),
      body: playerProvider.isLoading
          ? Center(child: CircularProgressIndicator())
          : playerProvider.errorMessage != null
          ? Center(child: Text(playerProvider.errorMessage!))
          : ListView.builder(
        itemCount: playerProvider.players.length,
        itemBuilder: (context, index) {
          final player = playerProvider.players[index];
          return ListTile(
            title: Text(player.name),
            subtitle: Text("${player.team} (${player.league})"),
            trailing: Text("Stat: ${player.statistic}"),
          );
        },
      ),
    );
  }
}
