import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nativa_css/nativa_css.dart';
import 'package:nativa_render/nativa_render.dart';

void main() {
  // A flex/stretch parent can impose a minimum width above the box's own
  // max-width. Capping the incoming maximum below that minimum produced
  // invalid constraints and a clampDouble assertion (5 INVALID visual pages).
  for (final incoming in const [
    BoxConstraints(minWidth: 300, maxWidth: 800),
    BoxConstraints(minWidth: 300, maxWidth: 300),
  ]) {
    test('max-width below the parent minimum keeps valid constraints '
        '($incoming)', () {
      final box = RenderCssBox(
        const CssBoxSpec(maxWidth: ResolvedLength.px(200)),
        ImageConfiguration.empty,
      );
      final size = box.getDryLayout(incoming);
      expect(incoming.isSatisfiedBy(size), isTrue);
      expect(size.width, 300);
    });
  }
}
