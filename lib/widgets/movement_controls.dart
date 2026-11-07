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

  Widget _button(IconData icon, String tooltip, String command, double size) =>
      SizedBox(
        width: size,
        height: size,
        child: IconButton(
          tooltip: tooltip,
          onPressed: () => onCommand(command),
          icon: Icon(icon),
          iconSize: (size * 0.55).clamp(28, 36),
          padding: EdgeInsets.zero,
        ),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        final stacked = size.maxWidth < 288;
        final buttonSize =
            (stacked ? (size.maxWidth - 24) / 3 : (size.maxWidth - 96) / 4)
                .clamp(48.0, 64.0);
        final xy = Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _button(
                  Icons.keyboard_arrow_up,
                  'Y ${negativeYUp ? '−' : '+'}10 mm',
                  'G91\nG0 Y${negativeYUp ? '-' : ''}10 F3000\nG90',
                  buttonSize),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _button(Icons.keyboard_arrow_left, 'X −10 mm',
                    'G91\nG0 X-10 F3000\nG90', buttonSize),
                _button(Icons.home, 'Home'.tr(), 'G28', buttonSize),
                _button(Icons.keyboard_arrow_right, 'X +10 mm',
                    'G91\nG0 X10 F3000\nG90', buttonSize),
              ]),
              _button(
                  Icons.keyboard_arrow_down,
                  'Y ${negativeYUp ? '+' : '−'}10 mm',
                  'G91\nG0 Y${negativeYUp ? '' : '-'}10 F3000\nG90',
                  buttonSize),
            ]),
          ),
        );
        final z = Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _button(Icons.arrow_upward, 'Z +2 mm', 'G91\nG0 Z2 F300\nG90',
                  buttonSize),
              SizedBox(
                  height: buttonSize, child: const Center(child: Text('Z'))),
              _button(Icons.arrow_downward, 'Z −2 mm', 'G91\nG0 Z-2 F300\nG90',
                  buttonSize),
            ]),
          ),
        );
        if (stacked) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                xy,
                z,
              ]);
        }
        return Row(
            children: [Expanded(flex: 3, child: xy), Expanded(child: z)]);
      });
}
