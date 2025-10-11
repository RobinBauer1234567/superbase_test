import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


  Color getColorForRating(num rating, int maxValue) {

    final effectiveMax = maxValue <= 0 ? 1.0 : maxValue;
    final t = (rating / effectiveMax).clamp(0.0, 1.0);

    final colorSequence = TweenSequence<Color?>([
      TweenSequenceItem(tween: ColorTween(begin: Colors.red.shade800, end: Colors.orange.shade700), weight: 40.0),
      TweenSequenceItem(tween: ColorTween(begin: Colors.orange.shade700, end: const Color(0xFFFFD700)), weight: 30.0),
      TweenSequenceItem(tween: ColorTween(begin: const Color(0xFFFFD700), end: Colors.lightGreen.shade500), weight: 30.0),
      TweenSequenceItem(tween: ColorTween(begin: Colors.lightGreen.shade500, end: Colors.green.shade500), weight: 30.0),
      TweenSequenceItem(tween: ColorTween(begin: Colors.green.shade500, end: Colors.teal.shade500), weight: 30.0),
      TweenSequenceItem(tween: ColorTween(begin: Colors.teal.shade500, end: Colors.purple.shade500), weight: 30.0),

    ]);
    return colorSequence.transform(t)!;
  }
