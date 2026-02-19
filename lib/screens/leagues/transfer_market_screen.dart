// lib/screens/leagues/transfer_market_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/viewmodels/data_viewmodel.dart';
import 'package:premier_league/screens/screenelements/player_list_item.dart';
import 'package:premier_league/screens/player_screen.dart';
import 'package:premier_league/screens/screenelements/transaction_overlay.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';
import 'dart:async';

// NEU: Enum für die drei Listen-Zustände
enum MarketMode { all, ownBids, ownOffers }

class TransferMarketScreen extends StatefulWidget {
  final int leagueId;
  const TransferMarketScreen({super.key, required this.leagueId});

  @override
  State<TransferMarketScreen> createState() => _TransferMarketScreenState();
}

class _TransferMarketScreenState extends State<TransferMarketScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _offers = [];
  int _budget = 0; // NEU: Speichert das Budget
  MarketMode _currentMode = MarketMode.all; // NEU: Startet mit "Alle Spieler"

  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadMarket();
  }

  Future<void> _loadMarket() async {
    setState(() => _isLoading = true);
    final service = Provider.of<DataManagement>(context, listen: false).supabaseService;

    // Wir laden gleichzeitig den Markt und das Budget
    final data = await service.fetchTransferMarket(widget.leagueId);
    final budget = await service.fetchUserBudget(widget.leagueId);

    if (mounted) {
      setState(() {
        _offers = data;
        _budget = budget;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _displayedOffers {
    final currentUserId = Provider.of<DataManagement>(context, listen: false).supabaseService.supabase.auth.currentUser?.id;
    if (currentUserId == null) return _offers;

    switch (_currentMode) {
      case MarketMode.all:
      // Zeigt alle Spieler, AUSSER die, die man gerade selbst verkauft
        return _offers.where((o) => o['seller_id'] != currentUserId).toList();

      case MarketMode.ownOffers:
      // Zeigt NUR die selbst angebotenen Spieler
        return _offers.where((o) => o['seller_id'] == currentUserId).toList();

      case MarketMode.ownBids:
      // Zeigt NUR die Spieler, auf die man bereits geboten hat
        return _offers.where((o) {
          final bids = o['transfer_bids'] as List<dynamic>? ?? [];
          return bids.any((b) => b['bidder_id'] == currentUserId);
        }).toList();
    }
  }

  void _toggleMode() {
    setState(() {
      if (_currentMode == MarketMode.all) {
        _currentMode = MarketMode.ownBids;
      } else if (_currentMode == MarketMode.ownBids) {
        _currentMode = MarketMode.ownOffers;
      } else {
        _currentMode = MarketMode.all;
      }
    });
  }

  IconData _getModeIcon() {
    switch (_currentMode) {
      case MarketMode.all: return Icons.language; // Weltkugel für "Alle"
      case MarketMode.ownBids: return Icons.gavel; // Hammer für "Eigene Gebote"
      case MarketMode.ownOffers: return Icons.outbox; // Outbox für "Eigene Verkäufe"
    }
  }

  String _getModeTitle() {
    switch (_currentMode) {
      case MarketMode.all: return "Alle Spieler";
      case MarketMode.ownBids: return "Meine Gebote";
      case MarketMode.ownOffers: return "Meine Verkäufe";
    }
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
            subtitle: Text("MW: ${_currencyFormat.format(p['spieler_analytics']?['marktwert'] ?? 0)}"),
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
    final int safeMarktwert = (playerMap['spieler_analytics']?['marktwert'] as num?)?.toInt() ?? 0;
    final extraData = _extractPlayerData(playerMap);

    final player = PlayerInfo(
      id: playerMap['id'],
      name: playerMap['name'] ?? 'Unbekannt',
      position: playerMap['position'] ?? '',
      profileImageUrl: playerMap['profilbild_url'],
      rating: extraData['score'] ?? 0,
      goals: 0, assists: 0, ownGoals: 0,
      teamImageUrl: extraData['teamImageUrl'],
    );

    // Context für Navigation sichern
    final dialogContextCompleter = Completer<BuildContext>();

    await showDialog(
      context: context,
      builder: (ctx) {
        if (!dialogContextCompleter.isCompleted) {
          dialogContextCompleter.complete(ctx);
        }
        return TransactionOverlay(
          player: player,
          type: TransactionType.sell,
          basePrice: safeMarktwert,

          // 1. Normaler Verkauf (Auktion)
          onConfirm: (price) async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              // Dialog schließen
              Navigator.of(ctx, rootNavigator: true).pop();

              // API Call
              await Provider.of<DataManagement>(context, listen: false)
                  .supabaseService.listPlayerOnMarket(widget.leagueId, player.id, price);

              if (mounted) {
                messenger.showSnackBar(const SnackBar(content: Text("Spieler auf den Markt gesetzt!"), backgroundColor: Colors.green));
                _loadMarket();
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fehler: $e"), backgroundColor: Colors.red));
              }
            }
          },

          // 2. NEU: Schnellverkauf (Direkt an System)
          onQuickSell: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              // Dialog schließen
              Navigator.of(ctx, rootNavigator: true).pop();

              // API Call für Schnellverkauf
              await Provider.of<DataManagement>(context, listen: false)
                  .supabaseService.sellPlayerToSystem(widget.leagueId, player.id);

              if (mounted) {
                messenger.showSnackBar(const SnackBar(content: Text("Spieler erfolgreich verkauft!"), backgroundColor: Colors.green));
                _loadMarket(); // Liste neu laden
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fehler: $e"), backgroundColor: Colors.red));
              }
            }
          },
        );
      },
    );
  }

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

  void _openBidOverlay(Map<String, dynamic> offer, PlayerInfo playerInfo) async {
    final currentUserId = Provider.of<DataManagement>(context, listen: false).supabaseService.supabase.auth.currentUser?.id;
    final bids = offer['transfer_bids'] as List<dynamic>? ?? [];

    final myBid = bids.firstWhere(
            (b) => b['bidder_id'] == currentUserId,
        orElse: () => null
    );

    final int? currentBidAmount = myBid != null ? (myBid['amount'] as int) : null;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TransactionOverlay(
        player: playerInfo,
        type: TransactionType.bid,
        basePrice: offer['min_bid_price'],
        currentBid: currentBidAmount,

        onWithdraw: () async {
          // ... (Hier bleibt dein Withdraw Code unverändert) ...
        },

        // --- HIER IST DIE ÄNDERUNG ---
        onConfirm: (amount) async {
          // 1. Messenger sichern
          final messenger = ScaffoldMessenger.of(context);

          try {
            await Provider.of<DataManagement>(context, listen: false)
                .supabaseService
                .placeBid(offer['id'], amount);

            // 2. Prüfen ob mounted
            if (!mounted) return;

            // 3. WICHTIG: Dialog schließen!
            Navigator.of(context, rootNavigator: true).pop();

            // 4. Feedback
            messenger.showSnackBar(
                const SnackBar(content: Text("Gebot erfolgreich abgegeben!"), backgroundColor: Colors.green)
            );
          } catch (e) {
            if (mounted) {
              messenger.showSnackBar(
                  SnackBar(content: Text("Fehler: $e"), backgroundColor: Colors.red)
              );
            }
          }
        },
      ),
    );

    if (mounted) {
      _loadMarket();
    }
  }

  Map<String, dynamic> _extractPlayerData(Map<String, dynamic> playerRaw) {
    String? teamImg;
    if (playerRaw['season_players'] != null && (playerRaw['season_players'] as List).isNotEmpty) {
      teamImg = playerRaw['season_players'][0]['team']['image_url'];
    }
    int score = 0;
    final seasonId = Provider.of<DataManagement>(context, listen: false).seasonId.toString();
    try {
      final dynamic stats = playerRaw['spieler_analytics']?['gesamtstatistiken'];
      dynamic seasonStats;
      if (stats is Map) {
        if (stats.containsKey(seasonId)) seasonStats = stats[seasonId];
      } else if (stats is List) {
        seasonStats = stats.firstWhere((e) => e['season_id'].toString() == seasonId, orElse: () => null);
      }
      if (seasonStats != null) score = seasonStats['gesamtpunkte'] ?? 0;
    } catch (_) {}

    return {'teamImageUrl': teamImg, 'score': score};
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Provider.of<DataManagement>(context, listen: false).supabaseService.supabase.auth.currentUser?.id;
    final displayedList = _displayedOffers;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,

      // --- NEU: DIE LEISTE IST JETZT UNTEN (bottomNavigationBar) ---
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              // Der Schatten zeigt jetzt nach OBEN (Offset y = -2)
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, -2))
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Links: Toggle Button für Ansicht
              Tooltip(
                message: _getModeTitle(),
                child: IconButton(
                  icon: Icon(_getModeIcon(), color: Theme.of(context).primaryColor, size: 28),
                  onPressed: _toggleMode,
                ),
              ),

              // Mitte: Budget Anzeige
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Dein Budget", style: TextStyle(fontSize: 10, color: Colors.grey.shade600, letterSpacing: 0.5)),
                  Text(
                    _currencyFormat.format(_budget),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ],
              ),

              // Rechts: Spieler Verkaufen (Dezentes Plus/Kreuz)
              Tooltip(
                message: "Spieler verkaufen",
                child: IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 28),
                  color: Colors.green.shade700,
                  onPressed: _showSellDialog,
                ),
              ),
            ],
          ),
        ),
      ),

      // --- DER RESTLICHE BILDSCHIRM (body) ---
      body: Column(
        children: [
          // Info-Zeile für den aktuellen Modus jetzt oben über der Liste
          Padding(
            padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
            child: Text(
              _getModeTitle().toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1.0),
            ),
          ),

          // --- DIE LISTE ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _loadMarket,
              child: displayedList.isEmpty
                  ? Center(child: Text("Hier ist aktuell nichts los.", style: TextStyle(color: Colors.grey.shade600)))
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: displayedList.length,
                itemBuilder: (context, index) {
                  final offer = displayedList[index];
                  final player = offer['player'];
                  final isSystem = offer['seller_id'] == null;
                  final isOwnOffer = offer['seller_id'] == currentUserId;
                  final extraData = _extractPlayerData(player);

                  // NEU: Prüfen, ob wir ein Gebot haben und wie hoch es ist
                  final bids = offer['transfer_bids'] as List<dynamic>? ?? [];
                  final myBid = bids.firstWhere((b) => b['bidder_id'] == currentUserId, orElse: () => null);
                  final bool hasBid = myBid != null;
                  final int? myBidAmount = hasBid ? myBid['amount'] as int : null;

                  final expires = DateTime.parse(offer['expires_at']);
                  final timeLeft = expires.difference(DateTime.now());
                  String timeString = timeLeft.inHours > 0 ? "${timeLeft.inHours} Std" : "${timeLeft.inMinutes} Min";
                  Color timeColor = timeLeft.inHours < 2 ? Colors.red : Colors.orange.shade800;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 1,
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
                          marketValue: player['spieler_analytics']?['marktwert'],
                          score: extraData['score'],
                          maxScore: 2500,
                          position: player['position'] ?? 'N/A',
                          id: player['id'],
                          goals: 0, assists: 0, ownGoals: 0,
                          teamColor: Colors.blueGrey,
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: player['id'])));
                          },
                        ),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Divider(height: 1, color: Colors.grey.shade100),
                        ),

                        // 2. MARKT-BEREICH
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(isSystem ? Icons.computer : Icons.person, size: 14, color: Colors.grey.shade400),
                                  const SizedBox(width: 6),
                                  Text(
                                    isSystem ? "System" : (isOwnOffer ? "Du (Verkäufer)" : "Manager"),
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                  ),
                                  const Spacer(),
                                  Icon(Icons.timer_outlined, size: 14, color: timeColor),
                                  const SizedBox(width: 4),
                                  Text(timeString, style: TextStyle(fontSize: 11, color: timeColor, fontWeight: FontWeight.bold)),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // WENN ES DAS EIGENE ANGEBOT IST: Keine Buttons anzeigen
                              if (isOwnOffer)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                                  child: const Center(
                                    child: Text("Dein Spieler ist auf dem Markt", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                )
                              // ANSONSTEN: Kaufen & Bieten Buttons anzeigen
                              else
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () {
                                          final pInfo = PlayerInfo(
                                            id: player['id'], name: player['name'], position: player['position'] ?? '',
                                            profileImageUrl: player['profilbild_url'], rating: extraData['score'],
                                            goals: 0, assists: 0, ownGoals: 0,
                                          );
                                          _openBidOverlay(offer, pInfo);
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          decoration: BoxDecoration(
                                            // NEU: Dezenter blauer Hintergrund, falls geboten!
                                              color: hasBid ? Colors.blue.shade50 : Colors.transparent,
                                              border: Border.all(color: hasBid ? Colors.blue.shade300 : Colors.grey.shade300),
                                              borderRadius: BorderRadius.circular(12)
                                          ),
                                          child: Column(
                                            children: [
                                              // NEU: Text ändert sich zu "DEIN GEBOT"
                                              Text(hasBid ? "DEIN GEBOT" : "GEBOT AB",
                                                  style: TextStyle(fontSize: 9, color: hasBid ? Colors.blue.shade700 : Colors.grey.shade600, letterSpacing: 0.5, fontWeight: FontWeight.bold)
                                              ),
                                              const SizedBox(height: 2),
                                              // NEU: Zeigt den eigenen Gebotsbetrag an, falls vorhanden
                                              Text(_currencyFormat.format(hasBid ? myBidAmount : offer['min_bid_price']),
                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: hasBid ? Colors.blue.shade900 : Colors.black87)
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () {
                                          final pInfo = PlayerInfo(
                                            id: player['id'], name: player['name'], position: player['position'] ?? '',
                                            profileImageUrl: player['profilbild_url'], rating: extraData['score'],
                                            goals: 0, assists: 0, ownGoals: 0,
                                          );
                                          _openBuyOverlay(offer, pInfo);
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          decoration: BoxDecoration(color: Colors.green.shade50, border: Border.all(color: Colors.green.shade200), borderRadius: BorderRadius.circular(12)),
                                          child: Column(
                                            children: [
                                              Text("SOFORT KAUFEN", style: TextStyle(fontSize: 9, color: Colors.green.shade700, letterSpacing: 0.5, fontWeight: FontWeight.bold)),
                                              const SizedBox(height: 2),
                                              Text(_currencyFormat.format(offer['buy_now_price']), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green.shade900)),
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
          ),
        ],
      ),
    );
  }
}