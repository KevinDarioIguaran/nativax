import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_render/nativa_render.dart';

void main() {
  test('rasterizes an SVG background', () async {
    final image = await rasterizeSvgBytes(
      Uint8List.fromList(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect width="10" height="5" fill="#ffe800"/>'
        '<rect y="5" width="10" height="5" fill="#00148e"/>'
        '</svg>'
            .codeUnits,
      ),
      width: 20,
      height: 20,
    );
    expect(image.width, 20);
    expect(image.height, 20);
    image.dispose();
  });
}
