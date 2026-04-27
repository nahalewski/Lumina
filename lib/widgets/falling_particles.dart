import 'dart:math';
import 'package:flutter/material.dart';
import '../models/media_model.dart';

/// A premium particle system for falling sakura flowers
class FallingFlowersBackground extends StatefulWidget {
  final Widget child;
  final ParticleTheme theme;
  const FallingFlowersBackground({
    super.key,
    required this.child,
    this.theme = ParticleTheme.sakura,
  });

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
    
    // Optimized: Update flower logic on each tick without calling setState() on the whole widget
    _controller.addListener(() {
      for (var flower in _flowers) {
        flower.update(_random, 0.016);
      }
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
          // Use RepaintBoundary and AnimatedBuilder to isolate background rendering
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _FlowerPainter(_flowers, widget.theme),
                  size: Size.infinite,
                );
              },
            ),
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
  final ParticleTheme theme;
  static Path? _cachedSakuraPath;
  static Path? _cachedSkullPath;

  _FlowerPainter(this.flowers, this.theme);

  Path _getSakuraPath(double size) {
    if (_cachedSakuraPath != null) return _cachedSakuraPath!;
    
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final double angle = i * 2 * pi / 5;
      final double cosA = cos(angle);
      final double sinA = sin(angle);
      
      // Rotate manually for the path
      final p = Path();
      p.moveTo(0, 0);
      p.quadraticBezierTo(size * 0.4, -size * 0.6, 0, -size);
      p.quadraticBezierTo(-size * 0.4, -size * 0.6, 0, 0);
      
      final Matrix4 matrix = Matrix4.rotationZ(angle);
      path.addPath(p, Offset.zero, matrix4: matrix.storage);
    }
    _cachedSakuraPath = path;
    return path;
  }

  Path _getSkullPath(double size) {
    if (_cachedSkullPath != null) return _cachedSkullPath!;

    final path = Path();
    path.fillType = PathFillType.evenOdd;

    // Head
    path.addOval(Rect.fromLTWH(-size * 0.5, -size * 0.8, size, size * 0.8));

    // Jaw
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(-size * 0.3, -size * 0.2, size * 0.6, size * 0.3),
      Radius.circular(size * 0.1),
    ));

    // Eye sockets (holes)
    path.addOval(
        Rect.fromLTWH(-size * 0.35, -size * 0.6, size * 0.25, size * 0.25));
    path.addOval(
        Rect.fromLTWH(size * 0.1, -size * 0.6, size * 0.25, size * 0.25));

    // Nose socket (hole)
    path.moveTo(0, -size * 0.35);
    path.lineTo(-size * 0.08, -size * 0.25);
    path.lineTo(size * 0.08, -size * 0.25);
    path.close();

    // Teeth marks
    path.moveTo(-size * 0.15, -size * 0.05);
    path.lineTo(-size * 0.15, size * 0.05);
    path.moveTo(0, -size * 0.05);
    path.lineTo(0, size * 0.05);
    path.moveTo(size * 0.15, -size * 0.05);
    path.lineTo(size * 0.15, size * 0.05);

    _cachedSkullPath = path;
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    // Base size for the cached path
    const double baseSize = 20.0;
    final Path path = theme == ParticleTheme.sakura
        ? _getSakuraPath(baseSize)
        : _getSkullPath(baseSize);

    for (var flower in flowers) {
      final pos = Offset(flower.x * size.width, flower.y * size.height);
      paint.color = (theme == ParticleTheme.sakura
              ? const Color(0xFFE9B3FF)
              : Colors.white70)
          .withValues(alpha: flower.opacity);
      
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(flower.rotation);
      
      // Scale based on the flower's individual size
      final double scale = flower.size / baseSize;
      canvas.scale(scale, scale);
      
      canvas.drawPath(path, paint);
      
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
