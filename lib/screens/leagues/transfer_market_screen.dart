// lib/screens/leagues/transfer_market_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/screenelements/player_list_item.dart';
import 'package:premier_league/utils/color_helper.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/screenelements/transaction_overlay.dart'; // <--- NEU
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';

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

  Future<void> _generateSystemPlayers() async {
    final dataManagement = Provider.of<DataManagement>(context, listen: false);
    final int seasonId = int.tryParse(dataManagement.seasonId.toString()) ?? 0;
    await dataManagement.supabaseService.simulateSystemTransfers(widget.leagueId, seasonId);
    _loadMarket();
  }

  Future<void> _showSellDialog() async {
    final service = Provider.of<DataManagement>(context, listen: false).supabaseService;
    final myPlayers = await service.fetchUserLeaguePlayers(widget.leagueId);

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


  Future<void> _buyNow(int transferId, String playerName, int price) async {
    try {
      await Provider.of<DataManagement>(context, listen: false).supabaseService.buyPlayerNow(transferId);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$playerName für ${_currencyFormat.format(price)} gekauft!"), backgroundColor: Colors.green));
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

  // --- HELPER FÜR DATEN EXTRAKTION ---
  Map<String, dynamic> _extractPlayerData(Map<String, dynamic> playerRaw) {
    String? teamImg;
    if (playerRaw['season_players'] != null && (playerRaw['season_players'] as List).isNotEmpty) {
      teamImg = playerRaw['season_players'][0]['team']['image_url'];
    }

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

  // Helper für die eigentliche Kauf-Transaktion
  Future<void> _executeBuy(int transferId, String playerName, int price) async {
    try {
      await Provider.of<DataManagement>(context, listen: false).supabaseService.buyPlayerNow(transferId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$playerName gekauft!"), backgroundColor: Colors.green));
        _loadMarket();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fehler: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _showPriceInputDialog(Map<String, dynamic> playerMap) async {
    final player = PlayerInfo(
      id: playerMap['id'],
      name: playerMap['name'],
      position: playerMap['position'] ?? '',
      profileImageUrl: playerMap['profilbild_url'],
      rating: 0,
      goals: 0, assists: 0, ownGoals: 0,
      teamImageUrl: playerMap['team_image_url'], // WICHTIG: Damit das Wappen angezeigt wird!
    );

    // HIER ÄNDERUNG: showDialog statt showModalBottomSheet
    await showDialog(
      context: context,
      builder: (ctx) => TransactionOverlay(
        player: player,
        type: TransactionType.sell,
        basePrice: playerMap['marktwert'] ?? 0,
        onConfirm: (price) async {
          await Provider.of<DataManagement>(context, listen: false).supabaseService.listPlayerOnMarket(widget.leagueId, player.id, price);
          _loadMarket();
        },
      ),
    );
  }

  // 2. Kaufen Overlay
  void _openBuyOverlay(Map<String, dynamic> offer, PlayerInfo playerInfo) {
    showDialog(
      context: context,
      builder: (ctx) => TransactionOverlay(
        player: playerInfo,
        type: TransactionType.buy,
        basePrice: offer['buy_now_price'],
        onConfirm: (price) => _executeBuy(offer['id'], playerInfo.name, price),
      ),
    );
  }

  // 3. Bieten Overlay
  void _openBidOverlay(Map<String, dynamic> offer, PlayerInfo playerInfo) {
    showDialog(
      context: context,
      builder: (ctx) => TransactionOverlay(
        player: playerInfo,
        type: TransactionType.bid,
        basePrice: offer['min_bid_price'],
        onConfirm: (amount) async {
          await Provider.of<DataManagement>(context, listen: false).supabaseService.placeBid(offer['id'], amount);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gebot abgegeben!")));
        },
      ),
    );
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: _offers.length,
          itemBuilder: (context, index) {
            final offer = _offers[index];
            final player = offer['player'];
            final isSystem = offer['seller_id'] == null;

            final extraData = _extractPlayerData(player);

            final expires = DateTime.parse(offer['expires_at']);
            final timeLeft = expires.difference(DateTime.now());
            String timeString = timeLeft.inHours > 0
                ? "${timeLeft.inHours} Std"
                : "${timeLeft.inMinutes} Min";
            Color timeColor = timeLeft.inHours < 2 ? Colors.red : Colors.orange.shade800;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 1, // Weniger Schatten für cleaneren Look
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  // 1. DER SPIELER
                  PlayerListItem(
                    rank: index + 1,
                    profileImageUrl: player['profilbild_url'],
                    playerName: player['name'],
                    teamImageUrl: extraData['teamImageUrl'],
                    marketValue: player['marktwert'],
                    score: extraData['score'],
                    maxScore: 2500,
                    position: player['position'] ?? 'N/A',
                    id: player['id'],
                    goals: 0,
                    assists: 0,
                    ownGoals: 0,
                    teamColor: Colors.blueGrey,
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: player['id'])));
                    },
                  ),

                  // Trennlinie (optional, sehr fein)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Divider(height: 1, color: Colors.grey.shade100),
                  ),

                  // 2. MARKT-BEREICH (Neues, dezentes Design)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      children: [
                        // Info-Zeile (Verkäufer & Timer)
                        Row(
                          children: [
                            Icon(isSystem ? Icons.computer : Icons.person, size: 14, color: Colors.grey.shade400),
                            const SizedBox(width: 6),
                            Text(
                              isSystem ? "System" : "Manager",
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                            ),
                            const Spacer(),
                            Icon(Icons.timer_outlined, size: 14, color: timeColor),
                            const SizedBox(width: 4),
                            Text(
                              timeString,
                              style: TextStyle(fontSize: 11, color: timeColor, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Action-Buttons (Side-by-Side)
                        Row(
                          children: [
                            // BIETEN BUTTON (Dezent, Outlined)
                            Expanded(
                              child: InkWell(
                                // NEUER AUFRUF:
                                onTap: () {
                                  // PlayerInfo für Overlay bauen (aus den vorhandenen Daten)
                                  final pInfo = PlayerInfo(
                                    id: player['id'],
                                    name: player['name'],
                                    position: player['position'] ?? '',
                                    profileImageUrl: player['profilbild_url'],
                                    rating: extraData['score'],
                                    goals: 0, assists: 0, ownGoals: 0,
                                  );
                                  _openBidOverlay(offer, pInfo);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      Text("GEBOT AB", style: TextStyle(fontSize: 9, color: Colors.grey.shade600, letterSpacing: 0.5, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 2),
                                      Text(
                                        _currencyFormat.format(offer['min_bid_price']),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 12),

                            // KAUFEN BUTTON (Hervorgehoben, aber leicht)
                            Expanded(
                              child: InkWell(
                                // NEUER AUFRUF:
                                onTap: () {
                                  final pInfo = PlayerInfo(
                                    id: player['id'],
                                    name: player['name'],
                                    position: player['position'] ?? '',
                                    profileImageUrl: player['profilbild_url'],
                                    rating: extraData['score'],
                                    goals: 0, assists: 0, ownGoals: 0,
                                  );
                                  _openBuyOverlay(offer, pInfo);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50, // Sehr heller Hintergrund
                                    border: Border.all(color: Colors.green.shade200),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      Text("SOFORT KAUFEN", style: TextStyle(fontSize: 9, color: Colors.green.shade700, letterSpacing: 0.5, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 2),
                                      Text(
                                        _currencyFormat.format(offer['buy_now_price']),
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green.shade900),
                                      ),
                                    ],
                                  ),
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