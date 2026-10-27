import 'package:test/test.dart';
import 'package:nativa_js/nativa_js.dart';

void main() {
  test('reentrant', () {
    final engine = JscEngine();
    engine.evaluate('globalThis.double = (x) => x * 2');
    engine.registerHostFunction('viaScript', (args) {
      return engine.callGlobal('double', args[0]);
    });
    print('result: ' + engine.evaluate('__nx.host("viaScript", 21)').toString());
    engine.dispose();
  });
}
