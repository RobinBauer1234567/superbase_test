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

  // NEU: Optionale Parameter für bestehende Gebote
  final int? currentBid;
  final VoidCallback? onWithdraw;

  const TransactionOverlay({
    super.key,
    required this.player,
    required this.type,
    required this.basePrice,
    required this.onConfirm,
    this.currentBid,
    this.onWithdraw,
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
  void initState() {
    super.initState();
    _activeBid = widget.currentBid; // Das Gebot vom Widget übernehmen

    int initValue = 0;
    if (widget.type == TransactionType.bid) {
      initValue = widget.basePrice + 1;
    } else if (widget.type == TransactionType.sell) {
      initValue = widget.basePrice + 3000000;
    }

    _controller = TextEditingController(text: initValue > 0 ? _currency.format(initValue).trim() : '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleWithdraw() {
    if (widget.onWithdraw != null) {
      widget.onWithdraw!(); // Datenbank-Logik im Parent aufrufen
      setState(() {
        _activeBid = null; // UI auf Eingabe-Modus umschalten
        // Optional: Controller zurücksetzen auf Mindestgebot
        int resetValue = widget.basePrice + 1;
        _controller.text = _currency.format(resetValue).trim();
      });
    }
  }

  void _handleConfirm() {
    if (widget.type == TransactionType.buy) {
      widget.onConfirm(widget.basePrice);
      Navigator.pop(context);
    } else {
      String cleanText = _controller.text.replaceAll('.', '');
      final price = int.tryParse(cleanText) ?? 0;

      if (price > 0) {
        widget.onConfirm(price);
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayFormat = NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 0);

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

            // --- UNTERER BEREICH ---
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                children: [
                  Text(
                    widget.type == TransactionType.buy ? "SOFORTKAUF" :
                    (showActiveBid ? "AKTUELLES GEBOT" : (widget.type == TransactionType.bid ? "GEBOT ABGEBEN" : "VERKAUFEN")),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 8),

                  if (widget.type == TransactionType.buy)
                    Text(

                          "Kaufen für ${displayFormat.format(widget.basePrice)}?",
                      style: const TextStyle(fontSize: 15, color: Colors.black87),
                      textAlign: TextAlign.center,
                    ),

                  const SizedBox(height: 10),

                  // --- ENTWEDER: ANZEIGE DES AKTUELLEN GEBOTS ---
                  if (showActiveBid)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50, // Farbig hinterlegt (Blau)
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayFormat.format(_activeBid),
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                              ),
                            ],
                          ),
                          // Der Button zum Entfernen
                          IconButton(
                            onPressed: _handleWithdraw,
                            icon: const Icon(Icons.delete_outline, size: 28),
                            color: Colors.red.shade400,
                          ),
                        ],
                      ),
                    )

                  // --- ODER: DAS EINGABEFELD & BUTTONS ---
                  else ...[
                    if (widget.type != TransactionType.buy) ...[
                      TextField(
                        controller: _controller,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          ThousandsSeparatorInputFormatter(),
                        ],
                        decoration: InputDecoration(
                          prefixText: "€ ",
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
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
                            backgroundColor: widget.type == TransactionType.sell ? Colors.blue.shade700 : Colors.green.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          child: Text(
                            widget.type == TransactionType.sell ? "ANBIETEN" : "GEBOT BESTÄTIGEN",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                        ),
                      ),
                  ],
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