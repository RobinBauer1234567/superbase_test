// lib/screens/leagues/activity_feed_tab.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart'; // Pfad anpassen
import 'package:premier_league/models/league_activity.dart'; // Pfad anpassen

class ActivityFeedTab extends StatelessWidget {
  final int leagueId;

  const ActivityFeedTab({super.key, required this.leagueId});

  @override
  Widget build(BuildContext context) {
    final dataService = Provider.of<DataManagement>(context, listen: false).supabaseService;

    return StreamBuilder<List<LeagueActivity>>(
      stream: dataService.getLeagueActivities(leagueId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("Fehler beim Laden: ${snapshot.error}"));
        }

        final activities = snapshot.data ?? [];

        if (activities.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.newspaper, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text("Noch keine Aktivitäten in dieser Liga.", style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: activities.length,
          itemBuilder: (context, index) {
            final activity = activities[index];
            return _buildActivityCard(activity);
          },
        );
      },
    );
  }

  Widget _buildActivityCard(LeagueActivity activity) {
    IconData icon;
    Color color;
    String title;
    String description;

    final fmt = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);
    final date = DateFormat('dd.MM. HH:mm').format(activity.createdAt);

    switch (activity.type) {
      case 'JOIN':
        icon = Icons.person_add;
        color = Colors.green;
        title = "Neuer Manager";
        description = "${activity.content['user_name']} ist der Liga beigetreten.";
        break;
      case 'LEAVE':
        icon = Icons.person_remove_outlined;
        color = Colors.red;
        title = "Manager Verlassen";
        description = "${activity.content['user_name']} hat die Liga verlassen.";
        break;
      case 'LISTING':
        icon = Icons.sell;
        color = Colors.orange;
        title = "Transfermarkt";
        final price = activity.content['price'] ?? 0;
        description = "${activity.content['seller_name']} bietet ${activity.content['player_name']} für ${fmt.format(price)} an.";
        break;
      case 'TRANSFER':
        icon = Icons.handshake;
        color = Colors.blue;
        title = "Transfer";
        final price = activity.content['price'] ?? 0;
        final buyer = activity.content['buyer_name'];
        final seller = activity.content['seller_name'] ?? 'System';
        final player = activity.content['player_name'];
        description = "$buyer kauft $player von $seller für ${fmt.format(price)}.";
        break;
      default:
        icon = Icons.info;
        color = Colors.grey;
        title = "Info";
        description = "Unbekannte Aktivität";
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black54)),
                      Text(date, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(description, style: const TextStyle(fontSize: 15, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}