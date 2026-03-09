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

enum MarketMode { all, ownBids, ownOffers }

class TransferMarketScreen extends StatefulWidget {
  final int leagueId;
  const TransferMarketScreen({super.key, required this.leagueId});

  @override
  // WICHTIG: Das State-Objekt ist nun öffentlich (kein Unterstrich am Anfang)
  State<TransferMarketScreen> createState() => TransferMarketScreenState();
}

class TransferMarketScreenState extends State<TransferMarketScreen> {
  // SINGLETON: Erlaubt uns, von überall auf diesen State zuzugreifen!
  static TransferMarketScreenState? instance;

  bool _isLoading = true;
  List<Map<String, dynamic>> _offers = [];
  int _budget = 0;
  MarketMode _currentMode = MarketMode.all;

  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

  // NEU: Scroll Controller
  final ScrollController _scrollController = ScrollController();
  int? _pendingScrollPlayerId;

  @override
  void initState() {
    super.initState();
    instance = this; // Instanz global verfügbar machen
    _loadMarket();
  }

  @override
  void dispose() {
    if (instance == this) instance = null; // Instanz wieder freigeben
    _scrollController.dispose();
    super.dispose();
  }

  // NEU: Diese Funktion wird vom Activity Feed aufgerufen!
  void scrollToPlayer(int playerId) {
    _pendingScrollPlayerId = playerId;
    _attemptScroll();
  }

  // NEU: Führt das eigentliche Scrollen aus
  void _attemptScroll() {
    if (_pendingScrollPlayerId != null && _displayedOffers.isNotEmpty) {
      final targetId = _pendingScrollPlayerId;
      final index = _displayedOffers.indexWhere((o) => o['player']['id'] == targetId);

      if (index != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            // Geschätzte Höhe einer Karte inkl. Margin (ca. 195 Pixel)
            final offset = index * 195.0;
            final maxScroll = _scrollController.position.maxScrollExtent;

            _scrollController.animateTo(
              offset > maxScroll ? maxScroll : offset,
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeInOut,
            );
          }
        });
      }
      _pendingScrollPlayerId = null; // Zurücksetzen
    }
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  int _getMarktwert(dynamic playerMap) {
    if (playerMap == null) return 0;
    final analytics = playerMap['spieler_analytics'];
    if (analytics is List && analytics.isNotEmpty) {
      return _toInt(analytics[0]['marktwert']);
    } else if (analytics is Map) {
      return _toInt(analytics['marktwert']);
    }
    return 0;
  }

  Map<String, dynamic> _getStats(dynamic playerMap) {
    if (playerMap == null) return <String, dynamic>{};
    final analytics = playerMap['spieler_analytics'];
    final stats = analytics is Map ? analytics['gesamtstatistiken'] : null;
    if (stats is Map<String, dynamic>) return stats;
    if (stats is Map) return Map<String, dynamic>.from(stats);
    return <String, dynamic>{};
  }

  Future<void> _loadMarket() async {
    setState(() => _isLoading = true);
    final service = Provider.of<DataManagement>(context, listen: false).supabaseService;

    try {
      final data = await service.fetchTransferMarket(widget.leagueId);
      final budget = await service.fetchUserBudget(widget.leagueId);

      if (mounted) {
        setState(() {
          _offers = data;
          _budget = budget;
          _isLoading = false;
        });
        // NEU: Nach dem Laden schauen, ob wir scrollen müssen!
        _attemptScroll();
      }
    } catch (e, stacktrace) {
      print("🚨 CRASH IM TRANSFERMARKT: $e");
      print("📍 STACKTRACE: $stacktrace");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _displayedOffers {
    final currentUserId = Provider.of<DataManagement>(context, listen: false).supabaseService.supabase.auth.currentUser?.id;
    if (currentUserId == null) return _offers;

    switch (_currentMode) {
      case MarketMode.all:
        return _offers.where((o) => o['seller_id'] != currentUserId).toList();
      case MarketMode.ownOffers:
        return _offers.where((o) => o['seller_id'] == currentUserId).toList();
      case MarketMode.ownBids:
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
      case MarketMode.all: return Icons.language;
      case MarketMode.ownBids: return Icons.gavel;
      case MarketMode.ownOffers: return Icons.outbox;
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
            subtitle: Text("MW: ${_currencyFormat.format(_getMarktwert(p))}"),
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
    final int safeMarktwert = _getMarktwert(playerMap);
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
          onConfirm: (price) async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              Navigator.of(ctx, rootNavigator: true).pop();
              await Provider.of<DataManagement>(context, listen: false)
                  .supabaseService.listPlayerOnMarket(widget.leagueId, player.id, price);
              if (mounted) {
                messenger.showSnackBar(const SnackBar(content: Text("Spieler auf den Markt gesetzt!"), backgroundColor: Colors.green));
                _loadMarket();
              }
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fehler: $e"), backgroundColor: Colors.red));
            }
          },
          onQuickSell: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              Navigator.of(ctx, rootNavigator: true).pop();
              await Provider.of<DataManagement>(context, listen: false)
                  .supabaseService.sellPlayerToSystem(widget.leagueId, player.id);
              if (mounted) {
                messenger.showSnackBar(const SnackBar(content: Text("Spieler erfolgreich verkauft!"), backgroundColor: Colors.green));
                _loadMarket();
              }
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fehler: $e"), backgroundColor: Colors.red));
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
          try {
            await Provider.of<DataManagement>(context, listen: false)
                .supabaseService.withdrawBid(offer['id']);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Gebot zurückgezogen."), duration: Duration(seconds: 1))
              );
            }
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fehler: $e"), backgroundColor: Colors.red));
            rethrow;
          }
        },
        onConfirm: (amount) async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await Provider.of<DataManagement>(context, listen: false)
                .supabaseService.placeBid(offer['id'], amount);
            if (!mounted) return;
            Navigator.of(context, rootNavigator: true).pop();
            messenger.showSnackBar(const SnackBar(content: Text("Gebot erfolgreich abgegeben!"), backgroundColor: Colors.green));
          } catch (e) {
            if (mounted) messenger.showSnackBar(SnackBar(content: Text("Fehler: $e"), backgroundColor: Colors.red));
          }
        },
      ),
    );

    if (mounted) _loadMarket();
  }

  Map<String, dynamic> _extractPlayerData(Map<String, dynamic> playerRaw) {
    String? teamImg;
    final seasonPlayers = playerRaw['season_players'];
    if (seasonPlayers is Map && seasonPlayers['team'] is Map) {
      teamImg = seasonPlayers['team']['image_url'];
    } else if (seasonPlayers is List && seasonPlayers.isNotEmpty) {
      teamImg = seasonPlayers[0]['team']?['image_url'];
    }

    int score = 0;
    try {
      final stats = _getStats(playerRaw);
      score = _toInt(stats['gesamtpunkte']);
    } catch (_) {}

    return {'teamImageUrl': teamImg, 'score': score};
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Provider.of<DataManagement>(context, listen: false).supabaseService.supabase.auth.currentUser?.id;
    final displayedList = _displayedOffers;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,

      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, -2))
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: _getModeTitle(),
                child: IconButton(
                  icon: Icon(_getModeIcon(), color: Theme.of(context).primaryColor, size: 28),
                  onPressed: _toggleMode,
                ),
              ),
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

      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
            child: Text(
              _getModeTitle().toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1.0),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _loadMarket,
              child: displayedList.isEmpty
                  ? Center(child: Text("Hier ist aktuell nichts los.", style: TextStyle(color: Colors.grey.shade600)))
                  : ListView.builder(
                controller: _scrollController, // NEU: Controller hier einbinden!
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: displayedList.length,
                itemBuilder: (context, index) {
                  final offer = displayedList[index];
                  final player = offer['player'];
                  final isSystem = offer['seller_id'] == null;
                  final isOwnOffer = offer['seller_id'] == currentUserId;
                  final extraData = _extractPlayerData(player);

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
                        PlayerListItem(
                          rank: index + 1,
                          profileImageUrl: player['profilbild_url'],
                          playerName: player['name'],
                          teamImageUrl: extraData['teamImageUrl'],
                          marketValue: _getMarktwert(player),
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
                              if (isOwnOffer)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                                  child: const Center(
                                    child: Text("Dein Spieler ist auf dem Markt", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                )
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
                                              color: hasBid ? Colors.blue.shade50 : Colors.transparent,
                                              border: Border.all(color: hasBid ? Colors.blue.shade300 : Colors.grey.shade300),
                                              borderRadius: BorderRadius.circular(12)
                                          ),
                                          child: Column(
                                            children: [
                                              Text(hasBid ? "DEIN GEBOT" : "GEBOT AB",
                                                  style: TextStyle(fontSize: 9, color: hasBid ? Colors.blue.shade700 : Colors.grey.shade600, letterSpacing: 0.5, fontWeight: FontWeight.bold)
                                              ),
                                              const SizedBox(height: 2),
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