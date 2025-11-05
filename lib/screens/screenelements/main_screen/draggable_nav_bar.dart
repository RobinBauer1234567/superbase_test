// lib/widgets/draggable_nav_bar.dart
import 'package:flutter/material.dart';

// Das NavItem-Datenmodell wird um einen speziellen Klick-Handler erweitert
class NavItem {
  final Widget icon;
  final String label;
  final bool isDraggable;
  final double? fixedWidth;
  final VoidCallback? onMoreTap; // Spezieller Handler für den "Mehr"-Button

  NavItem({
    required this.icon,
    required this.label,
    this.isDraggable = false,
    this.fixedWidth,
    this.onMoreTap,
  });
}

// Die Haupt-Navigationsleiste
class DraggableNavBar extends StatelessWidget {
  final List<NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final void Function(int oldIndex, int newIndex) onReorder;

  const DraggableNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      padding: EdgeInsets.zero, // Wichtig für nahtlosen Look
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(items.length, (index) {
          final item = items[index];
          final navItemWidget = _DraggableNavItem(
            key: ValueKey('nav_item_$index'),
            item: item,
            isSelected: index == currentIndex,
            index: index,
            onTap: item.onMoreTap ?? () => onTap(index),
            onReorder: onReorder,
          );

          if (item.fixedWidth != null) {
            return SizedBox(width: item.fixedWidth, child: navItemWidget);
          } else {
            return Expanded(child: navItemWidget);
          }
        }),
      ),
    );
  }
}

// Das Widget für ein einzelnes Navigations-Element
class _DraggableNavItem extends StatefulWidget {
  final NavItem item;
  final bool isSelected;
  final int index;
  final VoidCallback onTap;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _DraggableNavItem({
    super.key,
    required this.item,
    required this.isSelected,
    required this.index,
    required this.onTap,
    required this.onReorder,
  });

  @override
  _DraggableNavItemState createState() => _DraggableNavItemState();
}

class _DraggableNavItemState extends State<_DraggableNavItem> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.02), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.02, end: -0.02), weight: 50),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isSelected ? Theme.of(context).primaryColor : Colors.grey;

    final content = Container(
      decoration: BoxDecoration(
        color: widget.isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.transparent,
      ),
      child: InkWell(
        onTap: widget.onTap,
        // --- ANPASSUNG: Hover-Effekte entfernen ---
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.grey.withOpacity(0.1),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            widget.item.icon,
            Text(widget.item.label, style: TextStyle(color: color, fontSize: 12), overflow: TextOverflow.ellipsis)
          ],
        ),
      ),
    );

    if (widget.item.isDraggable) {
      return DragTarget<int>(
        builder: (context, candidateData, rejectedData) {
          return LongPressDraggable<int>(
            data: widget.index,
            onDragStarted: () => _controller.repeat(reverse: true),
            onDragEnd: (details) => _controller.reset(),
            feedback: Material(color: Colors.transparent, child: content),
            childWhenDragging: Opacity(opacity: 0.3, child: content),
            child: RotationTransition(
              turns: _animation,
              child: content,
            ),
          );
        },
        onAccept: (draggedIndex) {
          widget.onReorder(draggedIndex, widget.index);
        },
      );
    }

    return content;
  }
}