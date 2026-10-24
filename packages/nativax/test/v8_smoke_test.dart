import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';

void main() {
  test(
    'V8 backend runs a document',
    () async {
      final runtime = await NativaXRuntime.create(
        config: const NativaXRuntimeConfig(engineFactory: V8Engine.new),
        source: r'''
<body>
<div id="x">hello</div>
<script>
  const el = document.getElementById('x');
  el.textContent = 'world';
  window.result = [1 + 1, el.textContent, document.body.children.length];
</script>
</body>
''',
      );
      expect(runtime.engine.evaluate('result'), [2, 'world', 2]);
      runtime.dispose();
    },
    skip: Platform.environment['NATIVAX_V8_LIB'] == null,
  );
}
