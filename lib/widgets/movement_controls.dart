import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class MovementControls extends StatelessWidget {
  final void Function(String) onCommand;
  final bool negativeYUp;
  const MovementControls({
    super.key,
    required this.onCommand,
    this.negativeYUp = true,
  });

  Widget _button(IconData icon, String tooltip, String command) => IconButton(
        tooltip: tooltip,
        onPressed: () => onCommand(command),
        icon: Icon(icon),
        iconSize: 28,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      );

  @override
  Widget build(BuildContext context) {
    final xy = Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _button(Icons.keyboard_arrow_up, 'Y ${negativeYUp ? '−' : '+'}10 mm',
              'G91\nG0 Y${negativeYUp ? '-' : ''}10 F3000\nG90'),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _button(Icons.keyboard_arrow_left, 'X −10 mm',
                'G91\nG0 X-10 F3000\nG90'),
            _button(Icons.home, 'Home'.tr(), 'G28'),
            _button(Icons.keyboard_arrow_right, 'X +10 mm',
                'G91\nG0 X10 F3000\nG90'),
          ]),
          _button(
              Icons.keyboard_arrow_down,
              'Y ${negativeYUp ? '+' : '−'}10 mm',
              'G91\nG0 Y${negativeYUp ? '' : '-'}10 F3000\nG90'),
        ]),
      ),
    );
    final z = Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _button(Icons.arrow_upward, 'Z +2 mm', 'G91\nG0 Z2 F300\nG90'),
          const SizedBox(height: 48, child: Center(child: Text('Z'))),
          _button(Icons.arrow_downward, 'Z −2 mm', 'G91\nG0 Z-2 F300\nG90'),
        ]),
      ),
    );
    return LayoutBuilder(builder: (context, size) {
      if (size.maxWidth < 288) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              xy,
              z,
            ]);
      }
      return Row(children: [Expanded(flex: 3, child: xy), Expanded(child: z)]);
    });
  }
}
