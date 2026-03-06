// lib/screens/leagues/activity_feed_tab.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/screens/screenelements/transfer_details_overlay.dart.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/models/league_activity.dart';
import 'package:premier_league/screens/screenelements/player_list_item.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/User/profile_screen.dart';
import 'package:premier_league/screens/leagues/transfer_market_screen.dart';

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
          padding: const EdgeInsets.all(16),
          itemCount: activities.length,
          itemBuilder: (context, index) {
            final activity = activities[index];
            return _buildActivityCard(context, activity);
          },
        );
      },
    );
  }

  Widget _buildActivityCard(BuildContext context, LeagueActivity activity) {
    final fmt = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);
    final date = DateFormat('dd.MM. HH:mm').format(activity.createdAt);

    IconData headerIcon;
    Color headerColor;
    String headerTitle;

    Widget middleContent; // Der dynamische Mittelteil (User oder Spieler)
    Widget bottomBarContent; // Die Fußzeile

    switch (activity.type) {
      case 'JOIN':
      case 'LEAVE':
        final isJoin = activity.type == 'JOIN';
        headerIcon = isJoin ? Icons.person_add : Icons.person_remove_outlined;
        headerColor = isJoin ? Colors.green : Colors.red;
        headerTitle = isJoin ? "NEUER MANAGER" : "AUSTRITT";

        final userName = activity.content['user_name'] ?? 'Unbekannt';
        final userId = activity.content['user_id'];
        final avatarUrl = activity.content['avatar_url'];
        final avatarText = userName.isNotEmpty ? userName[0].toUpperCase() : '?';

        middleContent = ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: headerColor.withOpacity(0.1),
            backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
            child: (avatarUrl == null || avatarUrl.isEmpty)
                ? Text(avatarText, style: TextStyle(color: headerColor, fontWeight: FontWeight.bold, fontSize: 16))
                : null,
          ),
          title: Text(userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          onTap: () {
            if (userId != null) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil konnte nicht gefunden werden.')));
            }
          },
        );

        // Bei Join/Leave brauchen wir kein extra InkWell für das BottomBar
        bottomBarContent = Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Text(
                  isJoin ? "Ist der Liga beigetreten" : "Hat die Liga verlassen",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)
              ),
            ],
          ),
        );
        break;
      case 'LISTING':
      case 'TRANSFER':
        final isListing = activity.type == 'LISTING';
        final transferType = activity.content['transfer_type'] ?? 'TRANSFER';

        if (isListing) {
          headerIcon = Icons.sell;
          headerColor = Colors.orange;
          headerTitle = "AUF DEM MARKT";
        } else {
          if (transferType == 'SOFORTKAUF') {
            headerIcon = Icons.flash_on;
            headerColor = Colors.teal;
            headerTitle = "SOFORTKAUF";
          } else if (transferType == 'AUKTION') {
            headerIcon = Icons.gavel;
            headerColor = Colors.deepPurple;
            headerTitle = "AUKTION";
          } else if (transferType == 'KEINE GEBOTE') {
            // NEU: Unsere Graue Kategorie für abgelaufene Angebote ohne Bieter
            headerIcon = Icons.timer_off;
            headerColor = Colors.grey.shade600;
            headerTitle = "KEINE GEBOTE";
          } else if (transferType == 'STARTSPIELER') {
            headerIcon = Icons.card_giftcard;
            headerColor = Colors.indigo;
            headerTitle = "STARTSPIELER";
          } else {
            headerIcon = Icons.handshake;
            headerColor = Colors.blue;
            headerTitle = "TRANSFER";
          }
        }

        final playerName = activity.content['player_name'] ?? 'Unbekannt';
        final playerId = activity.content['player_id'] ?? 0;
        final price = activity.content['price'] ?? 0;
        final seller = activity.content['seller_name'] ?? 'System';

        middleContent = PlayerListItem(
          rank: null,
          playerName: playerName,
          profileImageUrl: activity.content['profilbild_url'],
          teamImageUrl: activity.content['team_image_url'],
          marketValue: activity.content['marktwert'],
          score: activity.content['score'] ?? 0,
          maxScore: 2500,
          isPlayed: true,
          position: activity.content['position'] ?? 'N/A',
          id: playerId,
          onTap: () {
            if (playerId != 0) {
              Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: playerId)));
            }
          },
        );

        if (!isListing) {
          final buyer = activity.content['buyer_name'] ?? 'System';

          Widget innerBar = Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(seller == 'System' ? Icons.computer : Icons.person, size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Flexible(child: Text(seller, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: Icon(Icons.arrow_forward, size: 12, color: Colors.grey.shade400)
                      ),
                      Icon(buyer == 'System' ? Icons.computer : Icons.person, size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Flexible(child: Text(buyer, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: headerColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(fmt.format(price), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: headerColor)),
                ),
              ],
            ),
          );

          // NEU: 'KEINE GEBOTE' lässt sich nun auch für das Overlay anklicken
          if (transferType == 'SOFORTKAUF' || transferType == 'AUKTION' || transferType == 'TRANSFER' || transferType == 'KEINE GEBOTE') {
            bottomBarContent = InkWell(
              borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => TransferDetailsOverlay(activity: activity),
                );
              },
              child: innerBar,
            );
          } else {
            // Startspieler sind nicht klickbar
            bottomBarContent = innerBar;
          }

        } else {
          // BEI LISTING (Auf dem Markt): Navigiert zum Transfermarkt
          bottomBarContent = InkWell(
            onTap: () {
              final tabController = DefaultTabController.maybeOf(context);
              if (tabController != null) {
                tabController.animateTo(3);
                if (playerId != 0) {
                  Future.delayed(const Duration(milliseconds: 100), () {
                    TransferMarketScreenState.instance?.scrollToPlayer(playerId);
                  });
                }
              }
            },
            borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(seller == 'System' ? Icons.computer : Icons.person, size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text(seller, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(fmt.format(price), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                  ),
                ],
              ),
            ),
          );
        }
        break;
      default:
        headerIcon = Icons.info;
        headerColor = Colors.grey;
        headerTitle = "INFO";
        middleContent = const ListTile(title: Text("Unbekannte Aktivität"));
        bottomBarContent = const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Text("Keine weiteren Details")
        );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. KOPFZEILE
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Icon(headerIcon, size: 16, color: headerColor),
                const SizedBox(width: 6),
                Text(headerTitle, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: headerColor, letterSpacing: 0.5)),
                const Spacer(),
                Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(date, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
              ],
            ),
          ),

          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Divider(height: 1, color: Colors.grey.shade100)
          ),

          // 2. MITTLERE ZEILE
          middleContent,

          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Divider(height: 1, color: Colors.grey.shade100)
          ),

          // 3. FUSSZEILE (Padding und Klick-Logik sind nun individuell geregelt)
          bottomBarContent,
        ],
      ),
    );
  }
}