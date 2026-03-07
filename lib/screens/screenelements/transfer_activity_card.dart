import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/screens/screenelements/player_list_item.dart';

class TransferActivityCard extends StatelessWidget {
  final Map<String, dynamic> content;
  final DateTime createdAt;
  final VoidCallback? onPlayerTap;
  final VoidCallback? onDetailsTap;
  final bool showDetailsTap;
  final String datePattern;

  const TransferActivityCard({
    super.key,
    required this.content,
    required this.createdAt,
    this.onPlayerTap,
    this.onDetailsTap,
    this.showDetailsTap = true,
    this.datePattern = 'dd.MM. HH:mm',
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);
    final date = DateFormat(datePattern).format(createdAt);

    final transferType = (content['transfer_type'] ?? 'TRANSFER').toString();
    final headerData = _headerForTransferType(transferType);

    final playerName = content['player_name'] ?? 'Unbekannt';
    final playerId = content['player_id'] ?? 0;
    final price = content['price'] ?? 0;
    final seller = content['seller_name'] ?? 'System';
    final buyer = content['buyer_name'] ?? 'System';

    final detailsEnabled = showDetailsTap && _supportsDetailsOverlay(transferType) && onDetailsTap != null;

    Widget footer = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(seller == 'System' ? Icons.computer : Icons.person, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    seller,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  child: Icon(Icons.arrow_forward, size: 12, color: Colors.grey.shade400),
                ),
                Icon(buyer == 'System' ? Icons.computer : Icons.person, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    buyer,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: headerData.color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(
              fmt.format(price),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: headerData.color),
            ),
          ),
        ],
      ),
    );

    if (detailsEnabled) {
      footer = InkWell(
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
        onTap: onDetailsTap,
        child: footer,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Icon(headerData.icon, size: 16, color: headerData.color),
                const SizedBox(width: 6),
                Text(
                  headerData.title,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: headerData.color, letterSpacing: 0.5),
                ),
                const Spacer(),
                Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Text(date, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Divider(height: 1, color: Colors.grey.shade100),
          ),
          PlayerListItem(
            rank: null,
            playerName: playerName,
            profileImageUrl: content['profilbild_url'],
            teamImageUrl: content['team_image_url'],
            marketValue: content['marktwert'],
            score: content['score'] ?? 0,
            maxScore: 2500,
            isPlayed: true,
            position: content['position'] ?? 'N/A',
            id: playerId,
            onTap: onPlayerTap,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Divider(height: 1, color: Colors.grey.shade100),
          ),
          footer,
        ],
      ),
    );
  }

  bool _supportsDetailsOverlay(String transferType) {
    return transferType == 'SOFORTKAUF' || transferType == 'AUKTION' || transferType == 'TRANSFER' || transferType == 'KEINE GEBOTE';
  }

  _TransferHeaderData _headerForTransferType(String transferType) {
    if (transferType == 'SOFORTKAUF') {
      return const _TransferHeaderData(Icons.flash_on, Colors.teal, 'SOFORTKAUF');
    }
    if (transferType == 'AUKTION') {
      return const _TransferHeaderData(Icons.gavel, Colors.deepPurple, 'AUKTION');
    }
    if (transferType == 'KEINE GEBOTE') {
      return _TransferHeaderData(Icons.timer_off, Colors.grey.shade600, 'KEINE GEBOTE');
    }
    if (transferType == 'STARTSPIELER') {
      return const _TransferHeaderData(Icons.card_giftcard, Colors.indigo, 'STARTSPIELER');
    }
    return const _TransferHeaderData(Icons.handshake, Colors.blue, 'TRANSFER');
  }
}

class _TransferHeaderData {
  final IconData icon;
  final Color color;
  final String title;

  const _TransferHeaderData(this.icon, this.color, this.title);
}
