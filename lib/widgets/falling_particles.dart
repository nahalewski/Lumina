import 'dart:math';
import 'package:flutter/material.dart';

/// A premium particle system for falling sakura flowers
class FallingFlowersBackground extends StatefulWidget {
  final Widget child;
  const FallingFlowersBackground({super.key, required this.child});

  @override
  State<FallingFlowersBackground> createState() => _FallingFlowersBackgroundState();
}

class _FallingFlowersBackgroundState extends State<FallingFlowersBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Flower> _flowers = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    
    // Increase density for better visibility
    for (int i = 0; i < 60; i++) {
      _flowers.add(_Flower(_random, initial: true));
    }
    
    _controller.addListener(() {
      for (var flower in _flowers) {
        flower.update(_random, 0.016);
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0xFF131315),
            Color(0xFF2D1B3D),
            Color(0xFF131315),
          ],
        ),
      ),
      child: Stack(
        children: [
          CustomPaint(
            painter: _FlowerPainter(_flowers),
            size: Size.infinite,
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _Flower {
  late double x;
  late double y;
  late double size;
  late double rotation;
  late double speed;
  late double swing;
  late double opacity;

  _Flower(Random random, {bool initial = false}) {
    reset(random, initial: initial);
  }

  void reset(Random random, {bool initial = false}) {
    x = random.nextDouble();
    y = initial ? random.nextDouble() : -0.1;
    // Larger flowers
    size = random.nextDouble() * 20 + 15;
    rotation = random.nextDouble() * 2 * pi;
    speed = random.nextDouble() * 0.1 + 0.05;
    swing = random.nextDouble() * 1.5 + 0.5;
    // Higher opacity
    opacity = random.nextDouble() * 0.4 + 0.2;
  }

  void update(Random random, double dt) {
    y += speed * dt;
    x += sin(y * 8) * 0.002 * swing;
    rotation += 0.01;
    if (y > 1.1) reset(random);
  }
}

class _FlowerPainter extends CustomPainter {
  final List<_Flower> flowers;

  _FlowerPainter(this.flowers);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (var flower in flowers) {
      final pos = Offset(flower.x * size.width, flower.y * size.height);
      // Use the vibrant pink color the user likes
      paint.color = const Color(0xFFE9B3FF).withValues(alpha: flower.opacity);
      
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(flower.rotation);
      
      _drawSakura(canvas, flower.size, paint);
      
      canvas.restore();
    }
  }

  void _drawSakura(Canvas canvas, double size, Paint paint) {
    for (int i = 0; i < 5; i++) {
      canvas.save();
      canvas.rotate(i * 2 * pi / 5);
      
      final path = Path();
      path.moveTo(0, 0);
      path.quadraticBezierTo(size * 0.4, -size * 0.6, 0, -size);
      path.quadraticBezierTo(-size * 0.4, -size * 0.6, 0, 0);
      canvas.drawPath(path, paint);
      
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
