import 'package:flutter_test/flutter_test.dart';
import 'package:nativax/nativax.dart';

void main() {
  test('URL and URLSearchParams are exposed to scripts', () async {
    final runtime = await NativaXRuntime.create(
      source: r'''
<body>
<script>
  const u = new URL('../x?y=1&y=2#h', 'https://example.org/a/b/c');
  window.urlResult = [
    u.href,
    u.origin,
    u.pathname,
    u.search,
    u.hash,
    u.searchParams.get('y'),
    u.searchParams.getAll('y').join(','),
  ];
</script>
</body>
''',
    );
    expect(
      runtime.engine.evaluate('urlResult'),
      [
        'https://example.org/a/x?y=1&y=2#h',
        'https://example.org',
        '/a/x',
        '?y=1&y=2',
        '#h',
        '1',
        '1,2',
      ],
    );
    runtime.dispose();
  });

  test('CharacterData, ChildNode and isEqualNode APIs work', () async {
    final runtime = await NativaXRuntime.create(
      source: r'''
<body>
<script>
  const text = document.createTextNode('ab');
  text.appendData('cd');
  text.replaceData(1, 2, 'X');
  const parent = document.createElement('div');
  parent.appendChild(text);
  text.after('z');
  const clone = parent.cloneNode(true);
  window.domResult = [
    text.data,
    parent.textContent,
    parent.isEqualNode(clone),
    parent.isSameNode(clone),
  ];
</script>
</body>
''',
    );
    expect(
      runtime.engine.evaluate('domResult'),
      ['aXd', 'aXdz', true, false],
    );
    runtime.dispose();
  });
}
