/// Error raised by DOM operations. [name] follows DOMException names
/// (`HierarchyRequestError`, `NotFoundError`, `SyntaxError`,
/// `InvalidCharacterError`, `QuotaExceededError`, ...).
class DomException implements Exception {
  DomException(this.name, this.message);
  final String name;
  final String message;

  @override
  String toString() => '$name: $message';
}
