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

  // Nimmt jetzt auch die avatarUrl entgegen
  Widget _buildManagerAvatar(String name, String? avatarUrl, Color color) {
    String initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    bool isSystem = name == 'System';

    return Column(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: isSystem ? Colors.grey.shade200 : color.withOpacity(0.15),
          // NEU: Wenn eine URL da ist, lade das Profilbild!
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
    final isAuktion = transferType == 'AUKTION';
    final fmt = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

    final buyerName = content['buyer_name'] ?? 'System';
    final buyerAvatar = content['buyer_avatar_url']; // NEU
    final sellerName = content['seller_name'] ?? 'System';
    final sellerAvatar = content['seller_avatar_url']; // NEU

    final price = content['price'] ?? 0;
    final failedBid = content['failed_highest_bid'] == true;
    final transferId = content['transfer_id'];

    Color themeColor = transferType == 'SOFORTKAUF' ? Colors.teal : Colors.deepPurple;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: Container(
        color: Colors.white,
        // NEU: Das Overlay zwingend auf 80% der Bildschirmhöhe strecken!
        height: MediaQuery.of(context).size.height * 0.80,
        child: Column(
          children: [
            // 1. KOPFZEILE
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: themeColor.withOpacity(0.1),
              child: Row(
                children: [
                  Icon(isAuktion ? Icons.gavel : Icons.flash_on, color: themeColor),
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

            // 4. BIETER-HISTORIE (Jetzt IMMER sichtbar, nimmt gesamten restlichen Platz ein)
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
                          "Höchstbietender hatte nicht genug Budget. Transfer gescheitert / an System.",
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

              // NEU: Expanded füllt den gesamten verbleibenden Platz bis ganz nach unten auf!
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
                      padding: const EdgeInsets.only(top: 0, bottom: 16), // Padding fürs Ende der Liste
                      itemCount: bids.length,
                      itemBuilder: (context, index) {
                        final bid = bids[index];
                        final isHighest = index == 0;
                        final isFailedHighest = isHighest && failedBid;

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
                                fontWeight: isHighest ? FontWeight.bold : FontWeight.normal,
                                color: isFailedHighest ? Colors.grey : Colors.black87,
                                decoration: isFailedHighest ? TextDecoration.lineThrough : null,
                              )
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                  fmt.format(bid['amount']),
                                  style: TextStyle(
                                    fontWeight: isHighest ? FontWeight.bold : FontWeight.w500,
                                    color: isFailedHighest ? Colors.red : (isHighest ? Colors.green.shade700 : Colors.black87),
                                    decoration: isFailedHighest ? TextDecoration.lineThrough : null,
                                  )
                              ),
                              if (isFailedHighest)
                                const Text("INSOLVENT", style: TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold))
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