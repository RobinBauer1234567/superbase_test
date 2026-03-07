// lib/screens/screenelements/transfer_details_overlay.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/models/league_activity.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/screenelements/player_list_item.dart';

class TransferDetailsOverlay extends StatelessWidget {
  final LeagueActivity activity;

  const TransferDetailsOverlay({super.key, required this.activity});

  Widget _buildManagerAvatar(String name, String? avatarUrl, Color color) {
    String initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    bool isSystem = name == 'System';

    return Column(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: isSystem ? Colors.grey.shade200 : color.withOpacity(0.15),
          backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
          child: (avatarUrl == null || avatarUrl.isEmpty)
              ? (isSystem
              ? const Icon(Icons.computer, color: Colors.black54, size: 28)
              : Text(initials, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 20)))
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = activity.content;
    final transferType = content['transfer_type'] ?? 'TRANSFER';
    final fmt = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

    final buyerName = content['buyer_name'] ?? 'System';
    final buyerAvatar = content['buyer_avatar_url'];
    final sellerName = content['seller_name'] ?? 'System';
    final sellerAvatar = content['seller_avatar_url'];

    final price = content['price'] ?? 0;
    final isSystemBuy = content['is_system_buy'] == true;
    final failedBid = content['failed_highest_bid'] == true;
    final transferId = content['transfer_id'];

    Color themeColor = transferType == 'SOFORTKAUF'
        ? Colors.teal
        : (transferType == 'KEINE GEBOTE' ? Colors.grey.shade600 : Colors.deepPurple);

    IconData typeIcon = Icons.handshake;
    if (transferType == 'AUKTION') typeIcon = Icons.gavel;
    if (transferType == 'SOFORTKAUF') typeIcon = Icons.flash_on;
    if (transferType == 'KEINE GEBOTE') typeIcon = Icons.timer_off;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: Container(
        color: Colors.white,
        height: MediaQuery.of(context).size.height * 0.80,
        child: Column(
          children: [
            // 1. KOPFZEILE
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: themeColor.withOpacity(0.1),
              child: Row(
                children: [
                  Icon(typeIcon, color: themeColor),
                  const SizedBox(width: 8),
                  Text(
                    transferType,
                    style: TextStyle(fontWeight: FontWeight.bold, color: themeColor, fontSize: 14),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                ],
              ),
            ),

            // 2. SPIELER
            PlayerListItem(
              rank: null,
              playerName: content['player_name'] ?? 'Unbekannt',
              profileImageUrl: content['profilbild_url'],
              teamImageUrl: content['team_image_url'],
              marketValue: content['marktwert'],
              score: content['score'] ?? 0,
              maxScore: 2500,
              isPlayed: true,
              position: content['position'] ?? 'N/A',
              id: content['player_id'] ?? 0,
              onTap: () {},
            ),

            Divider(height: 1, color: Colors.grey.shade200),

            // 3. TRANSFER GRAFIK
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(child: _buildManagerAvatar(sellerName, sellerAvatar, Colors.orange)),

                  Column(
                    children: [
                      Text(fmt.format(price), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(height: 2, width: 20, color: Colors.grey.shade300),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey.shade400),
                          ),
                          Container(height: 2, width: 20, color: Colors.grey.shade300),
                        ],
                      )
                    ],
                  ),

                  Expanded(child: _buildManagerAvatar(buyerName, buyerAvatar, Colors.blue)),
                ],
              ),
            ),

            // 4. BIETER-HISTORIE
            if (transferId != null) ...[
              Divider(height: 1, color: Colors.grey.shade200),

              if (failedBid)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.red.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Höhere Gebote wurden abgelehnt (Nicht genug Budget).",
                          style: TextStyle(color: Colors.red.shade900, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      )
                    ],
                  ),
                ),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.grey.shade50,
                child: const Text("ABGEGEBENE GEBOTE", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
              ),

              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: Provider.of<DataManagement>(context, listen: false).supabaseService.getTransferBids(transferId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                          child: Text("Keine Gebote abgegeben.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))
                      );
                    }

                    final bids = snapshot.data!;
                    return ListView.builder(
                      padding: const EdgeInsets.only(top: 0, bottom: 16),
                      itemCount: bids.length,
                      itemBuilder: (context, index) {
                        final bid = bids[index];
                        final bidAmount = bid['amount'];

                        // LOGIK FÜR INSOLVENZ:
                        // Wenn das System gekauft hat und es eine Auktion war -> Alle Bieter insolvent
                        // Ansonsten: Wenn das Gebot HÖHER war als der endgültige Preis -> Bieter insolvent
                        final bool isInsolvent = (isSystemBuy && transferType == 'AUKTION') || (!isSystemBuy && bidAmount > price);

                        // Gewinner markieren (gleicher Preis wie Endpreis und gleicher Name)
                        final bool isWinner = !isSystemBuy && bidAmount == price && bid['username'] == buyerName;

                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.grey.shade200,
                            backgroundImage: bid['avatar_url'] != null ? NetworkImage(bid['avatar_url']) : null,
                            child: bid['avatar_url'] == null
                                ? Text(bid['username'][0].toUpperCase(), style: const TextStyle(fontSize: 12, color: Colors.black54))
                                : null,
                          ),
                          title: Text(
                              bid['username'],
                              style: TextStyle(
                                fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
                                color: isInsolvent ? Colors.grey : Colors.black87,
                                decoration: isInsolvent ? TextDecoration.lineThrough : null,
                              )
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                  fmt.format(bid['amount']),
                                  style: TextStyle(
                                    fontWeight: isWinner ? FontWeight.bold : FontWeight.w500,
                                    color: isInsolvent ? Colors.red : (isWinner ? Colors.green.shade700 : Colors.black87),
                                    decoration: isInsolvent ? TextDecoration.lineThrough : null,
                                  )
                              ),
                              if (isInsolvent)
                                const Text("INSOLVENT", style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold))
                              else if (isWinner)
                                const Text("GEWONNEN", style: TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold))
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}