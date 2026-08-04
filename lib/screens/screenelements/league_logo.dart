import 'package:flutter/material.dart';

class LeagueLogo extends StatelessWidget {
  final String? imageUrl;
  final double radius;

  const LeagueLogo({super.key, required this.imageUrl, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey.shade200,
      backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
      child: hasImage
          ? null
          : Icon(
              Icons.groups,
              size: radius,
              color: Colors.black54,
            ),
    );
  }
}
