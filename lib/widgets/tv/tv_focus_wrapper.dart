import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


/// A wrapper for TV-optimized focusable elements.
/// Provides scaling, glow effects, and border highlights when focused.
class TvFocusWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final double scaleFactor;
  final Color? focusColor;
  final BorderRadius? borderRadius;

  const TvFocusWrapper({
    super.key,
    required this.child,
    this.onTap,
    this.autofocus = false,
    this.focusNode,
    this.scaleFactor = 1.05,
    this.focusColor,
    this.borderRadius,
  });

  @override
  State<TvFocusWrapper> createState() => _TvFocusWrapperState();
}

class _TvFocusWrapperState extends State<TvFocusWrapper> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_handleFocusChange);
    }
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focusColor = widget.focusColor ?? theme.colorScheme.primary;
    final borderRadius = widget.borderRadius ?? BorderRadius.circular(12);

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && 
            (event.logicalKey == LogicalKeyboardKey.enter || 
             event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? widget.scaleFactor : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: focusColor.withValues(alpha: 0.4),
                        blurRadius: 25,
                        spreadRadius: 4,
                      ),
                      BoxShadow(
                        color: focusColor.withValues(alpha: 0.2),
                        blurRadius: 40,
                        spreadRadius: 8,
                      ),
                    ]
                  : [],
            ),
            child: Stack(
              children: [
                widget.child,
                // Focus Border
                AnimatedOpacity(
                  opacity: _isFocused ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: borderRadius,
                      border: Border.all(
                        color: focusColor,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
