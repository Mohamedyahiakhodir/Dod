import 'package:flutter_test/flutter_test.dart';
import 'package:voice_studio/models/fx.dart';

void main() {
  test('fx settings survive a JSON round trip', () {
    final f = FxSettings()..eqOn = true..eq[3] = 4.5..revType = 'mosque'..normOn = true;
    final g = FxSettings.fromJson(f.toJson());
    expect(g.eq[3], 4.5);
    expect(g.revType, 'mosque');
    expect(g.normOn, isTrue);
  });
}
