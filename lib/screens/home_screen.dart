//player_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/provider/player_provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/player_screen.dart';
class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() =>
        Provider.of<DataManagement>(context, listen: false).collectNewData());
  }

  @override
  Widget build(BuildContext context) {
    final playerProvider = Provider.of<PlayerProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text("Spielerübersicht")),
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
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlayerScreen(player: player),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
