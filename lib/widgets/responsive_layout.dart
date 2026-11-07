import 'package:flutter/material.dart';

/// Keep content readable and reachable even in short landscape viewports.
class PageScrollView extends StatelessWidget {
  final Widget child;
  const PageScrollView({super.key, required this.child});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: child,
            ),
          ),
        ),
      );
}

class AdaptiveColumns extends StatelessWidget {
  final Widget leading;
  final Widget trailing;
  final double breakpoint;
  final int leadingFlex;
  final int trailingFlex;
  final bool trailingFirstWhenStacked;
  const AdaptiveColumns({
    super.key,
    required this.leading,
    required this.trailing,
    this.breakpoint = 720,
    this.leadingFlex = 1,
    this.trailingFlex = 1,
    this.trailingFirstWhenStacked = false,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (size.maxWidth < breakpoint * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              trailingFirstWhenStacked ? trailing : leading,
              const SizedBox(height: 12),
              trailingFirstWhenStacked ? leading : trailing,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: leadingFlex, child: leading),
            const SizedBox(width: 12),
            Expanded(flex: trailingFlex, child: trailing),
          ],
        );
      });
}

/// Size columns from their available width, while letting labels grow in height.
class ControlWrap extends StatelessWidget {
  final List<Widget> children;
  final double minWidth;
  final int maxColumns;
  const ControlWrap({
    super.key,
    required this.children,
    this.minWidth = 150,
    this.maxColumns = 3,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        const gap = 8.0;
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = ((size.maxWidth + gap) / (minWidth * scale + gap))
            .floor()
            .clamp(1, maxColumns);
        final width = (size.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child)
          ],
        );
      });
}

class ControlCard extends StatelessWidget {
  final Widget icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  const ControlCard({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 104),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    icon,
                    const SizedBox(height: 8),
                    Text(label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
