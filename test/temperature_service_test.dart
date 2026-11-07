import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:CacomixtlePad/services/temp_svc.dart';
import 'support/fake_printer.dart';

void main() {
  test('polling reuses one subscription and allows only one outstanding query',
      () {
    fakeAsync((clock) {
      final printer = FakePrinter();
      final temperatures = TemperatureService(printer);
      clock.flushMicrotasks();
      expect(printer.sent, ['M105']);
      clock.elapse(const Duration(seconds: 4));
      clock.flushMicrotasks();
      expect(printer.sent, ['M105']);
      printer.respond('ok T:200 /210 B:60 /65 FAN0@:128\n');
      clock.flushMicrotasks();
      expect(temperatures.hotendTemp, '200');
      expect(temperatures.targetBed, 65);
      expect(temperatures.fanSpeed, 128);
      clock.elapse(const Duration(seconds: 2));
      clock.flushMicrotasks();
      expect(printer.sent, ['M105', 'M105']);
      printer.respond();
      clock.flushMicrotasks();
      int updates = 0;
      temperatures.addListener(() => updates++);
      printer.respond('FAN0@:100\n');
      clock.flushMicrotasks();
      expect(updates, 1);
      expect(temperatures.fanSpeed, 100);
      printer.detach();
      clock.flushMicrotasks();
      expect(temperatures.hotendTemp, '--');
      clock.elapse(const Duration(seconds: 6));
      clock.flushMicrotasks();
      expect(printer.sent.length, 2);
      temperatures.dispose();
      printer.dispose();
      clock.flushMicrotasks();
    });
  });
}
