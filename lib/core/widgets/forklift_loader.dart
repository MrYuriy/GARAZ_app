import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n.dart';

/// The loading animation: the app's forklift reverses across with a pallet on
/// its forks (as with a load that blocks the view), drops it on the way, drives
/// on, notices, goes forward for it, lifts it and reverses off — then again
/// from the left. With animations turned off it stands still.
class ForkliftLoader extends StatefulWidget {
  const ForkliftLoader({super.key, this.width = 280, this.onFirstLoop});

  final double width;

  /// Called once, when the first full loop has played (at once when
  /// animations are turned off).
  final VoidCallback? onFirstLoop;

  @override
  State<ForkliftLoader> createState() => _ForkliftLoaderState();
}

class _ForkliftLoaderState extends State<ForkliftLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 6000));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = 0.1;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onFirstLoop?.call());
      return;
    }
    // One loop to the end, then report it and keep going.
    _c.forward().whenComplete(() {
      if (!mounted) return;
      widget.onFirstLoop?.call();
      _c.repeat();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: tr('Ładowanie…'),
      child: SizedBox(
        width: widget.width,
        height: _Scene.height,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) =>
                _Scene(t: _c.value, width: widget.width, color: scheme.primary, ground: scheme.outlineVariant),
          ),
        ),
      ),
    );
  }
}

/// Where everything is at moment [t] (0..1) of the loop.
class _Scene extends StatelessWidget {
  const _Scene({required this.t, required this.width, required this.color, required this.ground});

  static const height = 84.0;
  static const size = 56.0; // the forklift icon
  static const groundY = height - 6; // the floor line
  static const lift = 7.0; // how high the forks carry the pallet

  final double t;
  final double width;
  final Color color;
  final Color ground;

  // Phases of the loop.
  static const _dropAt = 0.30, _fallEnd = 0.36, _stopAt = 0.46, _backAt = 0.54, _backEnd = 0.68, _liftEnd = 0.75;

  static double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final xStart = -size - 30;
    final xDrop = width * 0.22;
    final xFar = width * 0.55;
    final xEnd = width + 30;

    // Forklift position (left edge of the icon).
    double fx;
    bool moving = true;
    if (t < _dropAt) {
      fx = _lerp(xStart, xDrop, _seg(t, 0, _dropAt));
    } else if (t < _stopAt) {
      fx = _lerp(xDrop, xFar, Curves.easeOut.transform(_seg(t, _dropAt, _stopAt)));
    } else if (t < _backAt) {
      fx = xFar;
      moving = false;
    } else if (t < _backEnd) {
      fx = _lerp(xFar, xDrop, Curves.easeInOut.transform(_seg(t, _backAt, _backEnd)));
    } else if (t < _liftEnd) {
      fx = xDrop;
      moving = false;
    } else {
      fx = _lerp(xDrop, xEnd, Curves.easeIn.transform(_seg(t, _liftEnd, 1)));
    }

    // Pallet: on the forks, falling, on the floor, lifted again. The forks
    // trail on the left, so the pallet's left edge sits this far from the
    // forklift's: its right edge just short of the mast.
    const forkOffset = size * 0.24 - _Pallet.width;
    double px, py, tilt = 0;
    final onForksY = groundY - lift;
    if (t < _dropAt) {
      px = fx + forkOffset;
      py = onForksY;
    } else if (t < _fallEnd) {
      final k = Curves.easeIn.transform(_seg(t, _dropAt, _fallEnd));
      px = xDrop + forkOffset - 6 * k; // slides a little off the forks
      py = onForksY + lift * k;
      tilt = -math.sin(k * math.pi) * 0.25;
    } else if (t < _backEnd) {
      px = xDrop + forkOffset - 6;
      py = groundY;
    } else if (t < _liftEnd) {
      final k = Curves.easeOut.transform(_seg(t, _backEnd, _liftEnd));
      px = xDrop + forkOffset - 6 * (1 - k);
      py = groundY - lift * k;
    } else {
      px = fx + forkOffset;
      py = onForksY;
    }

    // A little bounce while driving.
    final bob = moving ? (math.sin(t * math.pi * 60).abs() * 1.5) : 0.0;
    final carrying = t < _dropAt || t >= _liftEnd;
    final puzzled = t >= _stopAt && t < _backAt;

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: groundY,
          child: Container(height: 2, color: ground),
        ),
        Positioned(
          left: px,
          top: py - _Pallet.height - (carrying ? bob : 0),
          child: Transform.rotate(
            angle: tilt,
            alignment: Alignment.bottomRight,
            child: _Pallet(color: color),
          ),
        ),
        Positioned(
          left: fx,
          top: groundY - size + 4 - bob,
          // Mirrored: forks to the left, trailing as it reverses to the right.
          child: Transform.flip(
            flipX: true,
            child: Icon(Icons.forklift, size: size, color: color),
          ),
        ),
        if (puzzled)
          Positioned(
            left: fx + size * 0.6,
            top: groundY - size - 22,
            child: Text(
              '?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
            ),
          ),
      ],
    );
  }

  static double _lerp(double a, double b, double k) => a + (b - a) * k;
}

/// A pallet board with a box on it.
class _Pallet extends StatelessWidget {
  const _Pallet({required this.color});

  static const width = 26.0;
  static const height = 22.0;

  final Color color;

  @override
  Widget build(BuildContext context) {
    final box = Color.lerp(color, Colors.brown, 0.45)!;
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 18,
            height: 15,
            decoration: BoxDecoration(
              color: box,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: color, width: 1.5),
            ),
          ),
          Container(width: width, height: 3, color: color),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (var i = 0; i < 3; i++) Container(width: 4, height: 4, color: color)],
          ),
        ],
      ),
    );
  }
}
