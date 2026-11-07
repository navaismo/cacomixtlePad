import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/material_presets.dart';

class MaterialValuesPage extends StatefulWidget {
  const MaterialValuesPage({super.key});
  @override
  State<MaterialValuesPage> createState() => _MaterialValuesPageState();
}

class _MaterialValuesPageState extends State<MaterialValuesPage> {
  final _hotend = <String, TextEditingController>{};
  final _bed = <String, TextEditingController>{};
  final _form = GlobalKey<FormState>();
  bool _loading = true, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      for (final material in MaterialPresets.materials) {
        _hotend[material] = TextEditingController(
            text:
                MaterialPresets.read(prefs, material, isBed: false).toString());
        _bed[material] = TextEditingController(
            text:
                MaterialPresets.read(prefs, material, isBed: true).toString());
      }
    } catch (error) {
      _error = error.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final material in MaterialPresets.materials) {
        final hotendSaved = await prefs.setDouble(
            'hotend_$material', double.parse(_hotend[material]!.text));
        final bedSaved = await prefs.setDouble(
            'bed_$material', double.parse(_bed[material]!.text));
        if (!hotendSaved || !bedSaved) {
          throw StateError('Unable to save preferences');
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Material_values_saved'.tr())));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _input(TextEditingController controller, String label, double max) =>
      TextFormField(
        controller: controller,
        enabled: !_saving,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        scrollPadding: const EdgeInsets.all(32),
        decoration: InputDecoration(
            labelText: '$label (°C)',
            helperText: '0 – ${max.toInt()} °C',
            errorMaxLines: 2),
        validator: (text) {
          final value = double.tryParse(text ?? '');
          return value == null || !value.isFinite || value < 0 || value > max
              ? 'Invalid_value'.tr()
              : null;
        },
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Edit_Material_Values'.tr())),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : Form(
                      key: _form,
                      child: Column(children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.all(12),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            children: [
                              for (final material in MaterialPresets.materials)
                                Card(
                                    child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(material,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      const SizedBox(height: 8),
                                      LayoutBuilder(builder: (context, size) {
                                        final fields = [
                                          _input(_hotend[material]!,
                                              'Hotend'.tr(), 300),
                                          _input(
                                              _bed[material]!, 'Bed'.tr(), 150),
                                        ];
                                        final scale =
                                            MediaQuery.textScalerOf(context)
                                                    .scale(14) /
                                                14;
                                        if (size.maxWidth < 440 * scale) {
                                          return Column(children: [
                                            fields[0],
                                            const SizedBox(height: 12),
                                            fields[1]
                                          ]);
                                        }
                                        return Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(child: fields[0]),
                                              const SizedBox(width: 24),
                                              Expanded(child: fields[1])
                                            ]);
                                      }),
                                    ],
                                  ),
                                )),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _saving ? null : _save,
                              icon: const Icon(Icons.save),
                              label: Text('Save'.tr()),
                            ),
                          ),
                        ),
                      ]),
                    ),
        ),
      );

  @override
  void dispose() {
    for (final controller in [..._hotend.values, ..._bed.values]) {
      controller.dispose();
    }
    super.dispose();
  }
}
