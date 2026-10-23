import 'package:nativa_js/nativa_js.dart';
import 'package:test/test.dart';

void main() {
  test('JIT scaffold is safe to initialize', () {
    nativaJsJitInit();
    expect(nativaJsJitAvailable, isA<bool>());
    expect(nativaJsJitCodeBytes, greaterThanOrEqualTo(0));
  });
}
