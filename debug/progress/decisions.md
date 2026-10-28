# Decisions

- Native C11 + Sokol implementation is the product under test.
- No Dart or Flutter code exists in this tree.
- Existing C tests are preserved and executed through CTest.
- Generated artifacts are stored under debug/artifacts/.