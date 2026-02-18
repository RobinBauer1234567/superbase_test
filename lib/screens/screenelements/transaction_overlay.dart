// lib/screens/screenelements/transaction_overlay.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:premier_league/screens/screenelements/match_screen/formations.dart';

enum TransactionType { buy, bid, sell }

class TransactionOverlay extends StatefulWidget {
  final PlayerInfo player;
  final TransactionType type;
  final int basePrice;
  final Function(int finalPrice) onConfirm;

  final VoidCallback? onQuickSell;
  final int? currentBid;
  final Future<void> Function()? onWithdraw;
  const TransactionOverlay({
    super.key,
    required this.player,
    required this.type,
    required this.basePrice,
    required this.onConfirm,
    this.currentBid,
    this.onWithdraw,
    this.onQuickSell, // <-- NEU
  });

  @override
  State<TransactionOverlay> createState() => _TransactionOverlayState();
}

class _TransactionOverlayState extends State<TransactionOverlay> {
  late TextEditingController _controller;
  final NumberFormat _currency = NumberFormat.currency(locale: 'de_DE', symbol: '', decimalDigits: 0);

  // Lokaler State um zu steuern, ob das Gebot noch angezeigt wird oder gelöscht wurde
  int? _activeBid;

  @override
// lib/screens/screenelements/transaction_overlay.dart

  @override
  void initState() {
    super.initState();
    _activeBid = widget.currentBid;

    int initValue = 0;

    // Sicherheit: Falls basePrice negativ sein sollte
    int safeBase = widget.basePrice > 0 ? widget.basePrice : 0;

    if (widget.type == TransactionType.bid) {
      // Wenn schon ein Gebot da ist, nimm das, sonst Mindestgebot + 1
      if (_activeBid != null) {
        initValue = _activeBid!;
      } else {
        initValue = safeBase + 1;
      }
    } else if (widget.type == TransactionType.sell) {
      // Beim Verkaufen: Marktwert + 3 Mio als Vorschlag
      initValue = safeBase + 3000000;
    }

    // Formatierung in try-catch, damit das Widget auch bei Locale-Fehlern aufgeht
    try {
      String text = initValue > 0 ? _currency.format(initValue).trim() : '';
      _controller = TextEditingController(text: text);
    } catch (e) {
      // Fallback: Leeres Feld, aber kein Absturz
      _controller = TextEditingController(text: '');
    }
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  Future<void> _handleQuickSell() async {
    if (widget.onQuickSell != null) {
      widget.onQuickSell!();
      // Wir schließen hier NICHT selbst, das macht der Parent (wie beim Bieten)
    }
  }

  Future<void> _handleWithdraw() async {
    if (widget.onWithdraw != null) {
      try {
        // WARTEN, bis die Datenbank fertig ist
        await widget.onWithdraw!();

        // Erst wenn kein Fehler kam, aktualisieren wir die UI
        if (mounted) {
          setState(() {
            _activeBid = null; // UI wechselt zurück zum Eingabefeld
            // Controller zurücksetzen (optional)
            int resetValue = widget.basePrice + 1;
            _controller.text = _currency.format(resetValue).trim();
          });
        }
      } catch (e) {
        // Falls ein Fehler passiert (z.B. Internet weg), bleiben wir im "Gebot"-Modus
        // und zeigen den Fehler an (das macht meistens schon der Parent-Screen)
        debugPrint("Fehler beim Zurückziehen: $e");
      }
    }
  }
// lib/screens/screenelements/transaction_overlay.dart

  void _handleConfirm() {
    if (widget.type == TransactionType.buy) {
      widget.onConfirm(widget.basePrice);
      // Navigator.pop(context); // ENTFERNEN
    } else {
      String cleanText = _controller.text.replaceAll('.', '');
      final price = int.tryParse(cleanText) ?? 0;

      if (price > 0) {
        widget.onConfirm(price);
        // Navigator.pop(context); // ENTFERNEN
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    final displayFormat = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);
    final int quickSellPrice = (widget.basePrice * 0.95).floor();
    // Prüfen, ob wir die "Aktuelles Gebot"-Ansicht zeigen sollen
    final bool showActiveBid = widget.type == TransactionType.bid && _activeBid != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 10,
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- KOPFBEREICH ---
            SizedBox(
              height: 260, // Etwas Höhe reduziert, da das Badge weg ist
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 1. Hintergrund
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.blueGrey.shade900, Colors.blueGrey.shade700],
                      ),
                    ),
                  ),

                  // 2. Close Button
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),

                  // 3. Inhalt (Zentriert)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 12),
                        Hero(
                          tag: 'trans_avatar_${widget.player.id}',
                          child: PlayerAvatar(
                            player: widget.player,
                            teamColor: Colors.white,
                            radius: 50,
                            showDetails: false,
                            showPositions: false,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // NAME
                        Text(
                          widget.player.name,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                          textAlign: TextAlign.center,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),

                        const SizedBox(height: 8),


                        Text(widget.player.position, style: TextStyle(color: Colors.white70)),
                        const SizedBox(height: 16),

                        // Mini-Stats
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildStatItem("Punkte", "${widget.player.rating}"),
                            const SizedBox(width: 24),
                            _buildStatItem("Marktwert", displayFormat.format(widget.basePrice)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                children: [
                  // Dynamischer Titel
                  Text(
                    widget.type == TransactionType.buy ? "SOFORTKAUF" :
                    (showActiveBid ? "GEBOT BEARBEITEN" : (widget.type == TransactionType.bid ? "GEBOT ABGEBEN" : "VERKAUFEN")),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 8),

                  // Info Text
                  Text(
                    widget.type == TransactionType.buy
                        ? "Kaufen für ${displayFormat.format(widget.basePrice)}?"
                        : widget.type == TransactionType.bid
                        ? "Mindestgebot: ${displayFormat.format(widget.basePrice)}"
                        : "Lege einen Preis fest.",
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 24),

                  // --- EINGABEFELD ---
                  // Wir zeigen das Feld jetzt IMMER an (außer bei Sofortkauf)
                  // Aber wir stylen es unterschiedlich, je nachdem ob 'showActiveBid' true ist.
                  if (widget.type != TransactionType.buy) ...[
                    TextField(
                      controller: _controller,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          // Wenn aktives Gebot: Text Blau, sonst Schwarz
                          color: showActiveBid ? Colors.blue.shade900 : Colors.black87
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        ThousandsSeparatorInputFormatter(),
                      ],
                      decoration: InputDecoration(
                        prefixText: "€ ",
                        filled: true,
                        // HIER: Hintergrundfarbe ändern (Blau vs Grau)
                        fillColor: showActiveBid ? Colors.blue.shade50 : Colors.grey.shade50,

                        // HIER: Blauer Rand bei aktivem Gebot
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: showActiveBid ? BorderSide(color: Colors.blue.shade200) : BorderSide.none
                        ),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: showActiveBid ? BorderSide(color: Colors.blue.shade400, width: 2) : BorderSide.none // Beim Fokus etwas dicker
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),

                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),

                        // HIER: Der "Zurückziehen"-Button IM Feld
                        suffixIcon: showActiveBid
                            ? Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: IconButton(
                            onPressed: _handleWithdraw,
                            icon: const Icon(Icons.delete_outline),
                            color: Colors.red.shade400,
                            tooltip: "Gebot zurückziehen",
                          ),
                        )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // --- BUTTONS ---
                  if (widget.type == TransactionType.buy)
                    _SwipeToConfirm(
                      onConfirmed: _handleConfirm,
                      label: "Ziehen zum Kaufen",
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _handleConfirm,
                        style: ElevatedButton.styleFrom(
                          // Button Farbe: Blau beim Verkaufen, sonst Grün (oder Orange für Gebot)
                          backgroundColor: widget.type == TransactionType.sell ? Colors.blue.shade700 : Colors.green.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(
                          widget.type == TransactionType.sell ? "ANBIETEN" :
                          (showActiveBid ? "GEBOT ÄNDERN" : "GEBOT BESTÄTIGEN"), // Text ändert sich!
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                        ),
                      ),
                    ),
                  if (widget.type == TransactionType.sell && widget.onQuickSell != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _handleQuickSell,
                        icon: const Icon(Icons.flash_on, size: 18, color: Colors.orange),
                        label: Text(
                          "Sofortverkauf: ${displayFormat.format(quickSellPrice)}",
                          style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.orange.shade200),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          backgroundColor: Colors.orange.shade50.withOpacity(0.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Verkauf an System (95% MW)",
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    )
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label.toUpperCase(), style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.6), letterSpacing: 0.5)),
      ],
    );
  }
}

// --- Helper Klasse für 1.000er Punkte (unverändert) ---
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  static final NumberFormat _formatter = NumberFormat.decimalPattern('de_DE');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }
    String newText = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    int value = int.parse(newText);
    String formatted = _formatter.format(value);
    int selectionIndex = formatted.length - (newValue.text.length - newValue.selection.end);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: selectionIndex),
    );
  }
}

// --- _SwipeToConfirm (unverändert) ---
class _SwipeToConfirm extends StatefulWidget {
  final VoidCallback onConfirmed;
  final String label;
  const _SwipeToConfirm({required this.onConfirmed, required this.label});
  @override
  State<_SwipeToConfirm> createState() => _SwipeToConfirmState();
}
class _SwipeToConfirmState extends State<_SwipeToConfirm> {
  double _dragValue = 0.0;
  bool _confirmed = false;
  @override
  Widget build(BuildContext context) {
    const height = 56.0; const padding = 4.0;
    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth;
      final sliderWidth = maxWidth - height;
      return Container(height: height, width: maxWidth, decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green.shade200)),
        child: Stack(children: [
          Center(child: Text(_confirmed ? "ERFOLGREICH" : widget.label.toUpperCase(), style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 13))),
          Positioned(left: padding + (_dragValue * sliderWidth), top: padding, bottom: padding,
            child: GestureDetector(
              onHorizontalDragUpdate: (d) { if(!_confirmed) setState(() { _dragValue += d.primaryDelta! / sliderWidth; _dragValue = _dragValue.clamp(0.0, 1.0); }); },
              onHorizontalDragEnd: (d) { if(!_confirmed) { if(_dragValue > 0.85) { setState(() { _dragValue = 1.0; _confirmed = true; }); widget.onConfirmed(); } else { setState(() => _dragValue = 0.0); } } },
              child: Container(width: height-(padding*2), decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0,2))]), child: Icon(_confirmed?Icons.check:Icons.arrow_forward_rounded, color: Colors.white)),
            ),
          ),
        ],
        ),
      );
    },
    );
  }
}