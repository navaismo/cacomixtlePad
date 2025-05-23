import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


class MaterialValuesPage extends StatefulWidget {
  @override
  _MaterialValuesPageState createState() => _MaterialValuesPageState();
}

class _MaterialValuesPageState extends State<MaterialValuesPage> {

  final List<String> materials = ['PLA', 'PETG', 'TPU', 'ABS'];
  final List<double> defaultHotendTemperatures = [200.0, 240.0, 220.0, 270.0];
  final List<double> defaultBedTemperatures = [60.0, 72.0, 65.0, 90.0];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   automaticallyImplyLeading: false,
      //   //title: Text('Material Values'),
      // ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          int crossAxisCount = constraints.maxWidth > 600 ? 2 : 1;
          return Column(
            children: [
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                    childAspectRatio: 3.2,
                  ),
                  itemCount: materials.length,
                  itemBuilder: (context, index) {
                    return Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(25.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              materials[index],
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: defaultHotendTemperatures[index].toString(),
                                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Hotend (°C)',
                                      isDense: true,
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        defaultHotendTemperatures[index] = double.tryParse(value) ?? defaultHotendTemperatures[index];
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 40),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: defaultBedTemperatures[index].toString(),
                                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Bed'.tr() + ' (°C)',
                                      isDense: true,
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        defaultBedTemperatures[index] = double.tryParse(value) ?? defaultBedTemperatures[index];
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                child: SizedBox(
                  width: 200,
                  child: ElevatedButton.icon(
                  icon: Icon(Icons.save),
                  label: Text('Save'.tr()),
                  onPressed: () async {
                    // Save values to SharedPreferences
                    final prefs = await SharedPreferences.getInstance();
                    for (int i = 0; i < materials.length; i++) {
                    await prefs.setDouble('hotend_${materials[i]}', defaultHotendTemperatures[i]);
                    await prefs.setDouble('bed_${materials[i]}', defaultBedTemperatures[i]);
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Material_values_saved'.tr())),
                    );
                  },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }




}
