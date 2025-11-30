// lib/screens/leagues/transfer_market_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/screenelements/player_list_item.dart';
import 'package:premier_league/utils/color_helper.dart'; // Für Formatter
// lib/screens/leagues/transfer_market_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/screenelements/player_list_item.dart'; // WICHTIG
import 'package:premier_league/utils/color_helper.dart';
import 'package:premier_league/screens/player_screen.dart'; // Für Navigation
class TransferMarketScreen extends StatefulWidget {
  final int leagueId;
  const TransferMarketScreen({super.key, required this.leagueId});

  @override
  State<TransferMarketScreen> createState() => _TransferMarketScreenState();
}

class _TransferMarketScreenState extends State<TransferMarketScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _offers = [];
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadMarket();
  }

  Future<void> _loadMarket() async {
    setState(() => _isLoading = true);
    final service = Provider.of<DataManagement>(context, listen: false).supabaseService;
    final data = await service.fetchTransferMarket(widget.leagueId);
    if (mounted) {
      setState(() {
        _offers = data;
        _isLoading = false;
      });
    }
  }
  // --- ACTIONS ---

  // lib/screens/leagues/transfer_market_screen.dart

  Future<void> _generateSystemPlayers() async {
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    // Wir holen die seasonId aus dem Provider
    // (Achtung: seasonId ist in deinem Code oft dynamic/String, für RPC brauchen wir int)
    final int seasonId = int.tryParse(dataManagement.seasonId.toString()) ?? 0;

    await dataManagement.supabaseService.simulateSystemTransfers(widget.leagueId, seasonId);
    _loadMarket();
  }

  Future<void> _showSellDialog() async {
    // 1. Eigene Spieler laden, die noch NICHT auf dem Markt sind
    // Vereinfacht: Wir laden alle und filtern im UI oder lassen DB Fehler werfen
    final service = Provider.of<DataManagement>(context, listen: false).supabaseService;
    final myPlayers = await service.fetchUserLeaguePlayers(widget.leagueId);

    // Aktive Transfer-IDs sammeln, um Dopplung zu vermeiden
    final activeTransferPlayerIds = _offers.map((o) => o['player_id']).toList();
    final sellablePlayers = myPlayers.where((p) => !activeTransferPlayerIds.contains(p['id'])).toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView.builder(
        itemCount: sellablePlayers.length,
        itemBuilder: (context, index) {
          final p = sellablePlayers[index];
          return ListTile(
            leading: CircleAvatar(backgroundImage: NetworkImage(p['profilbild_url'] ?? '')),
            title: Text(p['name']),
            subtitle: Text("MW: ${_currencyFormat.format(p['marktwert'])}"),
            trailing: const Icon(Icons.sell, color: Colors.green),
            onTap: () {
              Navigator.pop(context);
              _showPriceInputDialog(p);
            },
          );
        },
      ),
    );
  }

  Future<void> _showPriceInputDialog(Map<String, dynamic> player) async {
    final controller = TextEditingController(text: (player['marktwert'] * 1.1).toInt().toString());

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("${player['name']} verkaufen"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Lege deinen Sofort-Kaufen Preis fest."),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Preis (€)", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            Text("Startgebot: ${_currencyFormat.format(player['marktwert'])} (Automatisch)", style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Abbrechen")),
          ElevatedButton(
            onPressed: () async {
              final price = int.tryParse(controller.text) ?? 0;
              if (price > 0) {
                await Provider.of<DataManagement>(context, listen: false).supabaseService.listPlayerOnMarket(widget.leagueId, player['id'], price);
                Navigator.pop(ctx);
                _loadMarket(); // Refresh
              }
            },
            child: const Text("Anbieten"),
          ),
        ],
      ),
    );
  }

  Future<void> _buyNow(int transferId, String playerName, int price) async {
    try {
      await Provider.of<DataManagement>(context, listen: false).supabaseService.buyPlayerNow(transferId);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$playerName für ${_currencyFormat.format(price)} gekauft!")));
      _loadMarket();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fehler: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _placeBid(int transferId, int minBid) async {
    final controller = TextEditingController(text: (minBid + 100000).toString());
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Gebot abgeben"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: "Dein Gebot (Min: ${_currencyFormat.format(minBid)})"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Abbrechen")),
          ElevatedButton(
            onPressed: () async {
              final amount = int.tryParse(controller.text) ?? 0;
              if (amount >= minBid) {
                await Provider.of<DataManagement>(context, listen: false).supabaseService.placeBid(transferId, amount);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gebot abgegeben!")));
              }
            },
            child: const Text("Bieten"),
          )
        ],
      ),
    );
  }
  Map<String, dynamic> _extractPlayerData(Map<String, dynamic> playerRaw) {
    // 1. Team Image
    String? teamImg;
    if (playerRaw['season_players'] != null && (playerRaw['season_players'] as List).isNotEmpty) {
      teamImg = playerRaw['season_players'][0]['team']['image_url'];
    }

    // 2. Score (Punkte)
    int score = 0;
    final seasonId = Provider.of<DataManagement>(context, listen: false).seasonId.toString();
    try {
      final dynamic stats = playerRaw['gesamtstatistiken'];
      dynamic seasonStats;
      if (stats is Map) {
        if (stats.containsKey(seasonId)) seasonStats = stats[seasonId];
      } else if (stats is List) {
        seasonStats = stats.firstWhere((e) => e['season_id'].toString() == seasonId, orElse: () => null);
      }
      if (seasonStats != null) score = seasonStats['gesamtpunkte'] ?? 0;
    } catch (_) {}

    return {
      'teamImageUrl': teamImg,
      'score': score,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: "sys_gen",
            backgroundColor: Colors.blueGrey,
            onPressed: _generateSystemPlayers,
            child: const Icon(Icons.refresh),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: "sell_btn",
            onPressed: _showSellDialog,
            label: const Text("Spieler verkaufen"),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadMarket,
        child: _offers.isEmpty
            ? const Center(child: Text("Der Markt ist leer."))
            : ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: _offers.length,
          itemBuilder: (context, index) {
            final offer = _offers[index];
            final player = offer['player'];
            final isSystem = offer['seller_id'] == null;

            // Extrahiere Teambild und Punkte für die Row
            final extraData = _extractPlayerData(player);

            // Zeitberechnung
            final expires = DateTime.parse(offer['expires_at']);
            final timeLeft = expires.difference(DateTime.now());
            String timeString = timeLeft.inHours > 0
                ? "${timeLeft.inHours} Std"
                : "${timeLeft.inMinutes} Min";
            Color timeColor = timeLeft.inHours < 2 ? Colors.red : Colors.orange.shade800;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias, // Damit Ripple Effekt nicht übersteht
              child: Column(
                children: [
                  // 1. DER SPIELER (PlayerListItem / PlayerRow)
                  PlayerListItem(
                    rank: index + 1, // Einfache Nummerierung
                    profileImageUrl: player['profilbild_url'],
                    playerName: player['name'],
                    teamImageUrl: extraData['teamImageUrl'],
                    marketValue: player['marktwert'], // Basis-Marktwert
                    score: extraData['score'],
                    maxScore: 2500, // Skalierung für Farbe
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: player['id'])));
                    },
                  ),

                  // Trennlinie zwischen Spieler und Markt-Infos
                  const Divider(height: 1, thickness: 1),

                  // 2. DER MARKTMECHANISMUS (Darunter)
                  Container(
                    color: Colors.grey.shade50, // Leicht abgesetzter Hintergrund
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    child: Column(
                      children: [
                        // Zeile A: Infos (Verkäufer & Timer)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(isSystem ? Icons.computer : Icons.person, size: 16, color: Colors.grey),
                                const SizedBox(width: 4),
                                Text(
                                  isSystem ? "Vom System" : "Von Manager",
                                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Icon(Icons.timer_outlined, size: 16, color: timeColor),
                                const SizedBox(width: 4),
                                Text(
                                  timeString,
                                  style: TextStyle(fontSize: 12, color: timeColor, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Zeile B: Aktionen (Bieten & Kaufen)
                        Row(
                          children: [
                            // Bieten Button
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  side: BorderSide(color: Colors.blue.shade200),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () => _placeBid(offer['id'], offer['min_bid_price']),
                                child: Column(
                                  children: [
                                    Text("GEBOT AB", style: TextStyle(fontSize: 10, color: Colors.blue.shade700, letterSpacing: 1)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _currencyFormat.format(offer['min_bid_price']),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Sofort Kaufen Button
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  backgroundColor: Colors.green.shade600,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                                onPressed: () => _buyNow(offer['id'], player['name'], offer['buy_now_price']),
                                child: Column(
                                  children: [
                                    const Text("SOFORT", style: TextStyle(fontSize: 10, color: Colors.white70, letterSpacing: 1)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _currencyFormat.format(offer['buy_now_price']),
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}