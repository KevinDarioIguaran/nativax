import 'package:nativa_css/nativa_css.dart';
import 'package:test/test.dart';

void main() {
  const cases = <String>[
    'p { color: red; margin: 0 auto; width: calc(100% - 4px); }',
    'div { display: flex; flex-wrap: wrap; gap: 4px; }',
    'div { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }',
    'p { font: 16px/1.5 "Helvetica Neue", sans-serif; }',
    'div { background: linear-gradient(to right, red, blue); }',
    'div { border: 1px solid #333; border-radius: 8px; }',
    'div { box-shadow: 0 4px 8px rgba(0,0,0,0.2); }',
    'div { transform: translateX(10px) rotate(45deg); }',
    'div { opacity: 0.5; filter: blur(2px); }',
    'div { position: absolute; top: 10px; left: 20px; z-index: 1; }',
    'div { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }',
    'div { padding: 10px 20px 30px 40px; }',
    'div { margin: 0 auto; }',
    'div { width: 100%; height: 50vh; }',
    'div { min-width: 100px; max-width: 500px; }',
    'div { min-height: 100px; max-height: 500px; }',
    'div { font-size: 16px; line-height: 1.5; }',
    'div { color: rgb(255, 0, 0); background: rgba(0, 0, 255, 0.5); }',
    'div { border-color: #ff0000 #00ff00 #0000ff; }',
    'div { grid-column: 1 / 3; grid-row: 1 / 2; }',
    'div { flex: 1 1 auto; align-self: center; }',
    'div { justify-content: space-between; align-items: center; }',
    'div { transition: all 0.3s ease; animation: fade 1s infinite; }',
    '@media (min-width: 768px) { div { color: blue; } }',
    '@media (prefers-color-scheme: dark) { div { color: white; } }',
    '@media (orientation: landscape) { div { color: green; } }',
    'div { --x: 10px; width: var(--x); }',
    'div { width: calc(100% - 20px); }',
    'div { font-family: "Helvetica Neue", sans-serif; }',
    'div { content: "hello"; }',
  ];

  for (var i = 0; i < cases.length; i++) {
    test('css fuzz case ${i + 1}', () {
      final sheet = StyleSheet.parse(cases[i]);
      expect(sheet, isNotNull);
    });
  }
}
