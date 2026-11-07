import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

Future<double?> showNumberInputDialog(
  BuildContext context, {
  required String title,
  required String hint,
  required double maximum,
  double minimum = 0,
  double? initialValue,
  bool integer = false,
}) =>
    showDialog<double>(
      context: context,
      builder: (_) => _NumberInputDialog(
        title: title,
        hint: hint,
        minimum: minimum,
        maximum: maximum,
        initialValue: initialValue,
        integer: integer,
      ),
    );

class _NumberInputDialog extends StatefulWidget {
  final String title, hint;
  final double minimum, maximum;
  final double? initialValue;
  final bool integer;
  const _NumberInputDialog({
    required this.title,
    required this.hint,
    required this.minimum,
    required this.maximum,
    required this.initialValue,
    required this.integer,
  });

  @override
  State<_NumberInputDialog> createState() => _NumberInputDialogState();
}

class _NumberInputDialogState extends State<_NumberInputDialog> {
  final _form = GlobalKey<FormState>();
  final _inputKey = GlobalKey<FormFieldState<String>>();
  late final _controller = TextEditingController(
      text: widget.initialValue?.toStringAsFixed(widget.integer ? 0 : 1) ?? '');

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.of(context).pop(double.parse(_controller.text));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height - media.viewInsets.bottom - media.padding.vertical;
    final compact = availableHeight < 260;
    final input = TextFormField(
      key: _inputKey,
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.numberWithOptions(
          decimal: !widget.integer, signed: widget.minimum < 0),
      textInputAction: TextInputAction.done,
      scrollPadding: const EdgeInsets.all(24),
      decoration: InputDecoration(
        label: compact
            ? Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        hintText: widget.hint,
        helperText: compact ? null : '${widget.minimum} – ${widget.maximum}',
        errorMaxLines: 2,
      ),
      validator: (text) {
        final value = double.tryParse(text ?? '');
        return value == null ||
                !value.isFinite ||
                value < widget.minimum ||
                value > widget.maximum ||
                (widget.integer && value != value.roundToDouble())
            ? 'Invalid_value'.tr()
            : null;
      },
      onFieldSubmitted: (_) => _submit(),
    );
    final confirm = FilledButton(onPressed: _submit, child: Text('OK'.tr()));
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!compact) ...[
                  Text(widget.title,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                ],
                if (compact)
                  Row(children: [
                    Expanded(child: input),
                    const SizedBox(width: 8),
                    IconButton(
                        tooltip: 'Cancel'.tr(),
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop()),
                    confirm,
                  ])
                else ...[
                  input,
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('Cancel'.tr())),
                      confirm,
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
