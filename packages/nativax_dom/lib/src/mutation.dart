import 'node.dart';

enum MutationType {
  /// Children were added or removed.
  childList,

  /// An attribute changed (including `class`, `id` and `style`).
  attributes,

  /// A text node's data changed.
  characterData,

  /// A form-control property changed (`value`, `checked`, `selectedIndex`)
  /// without an attribute change.
  property,
}

/// One change to the tree. Delivered synchronously to [Document] mutation
/// listeners, in order.
class MutationRecord {
  MutationRecord._(
    this.type,
    this.target, {
    this.addedNodes = const [],
    this.removedNodes = const [],
    this.previousSibling,
    this.nextSibling,
    this.name,
    this.oldValue,
  });

  factory MutationRecord.childList(
    Node target, {
    List<Node> added = const [],
    List<Node> removed = const [],
    Node? previousSibling,
    Node? nextSibling,
  }) =>
      MutationRecord._(
        MutationType.childList,
        target,
        addedNodes: added,
        removedNodes: removed,
        previousSibling: previousSibling,
        nextSibling: nextSibling,
      );

  factory MutationRecord.attribute(Node target, String name, String? old) =>
      MutationRecord._(MutationType.attributes, target,
          name: name, oldValue: old);

  factory MutationRecord.characterData(Node target, String old) =>
      MutationRecord._(MutationType.characterData, target, oldValue: old);

  factory MutationRecord.property(Node target, String name) =>
      MutationRecord._(MutationType.property, target, name: name);

  final MutationType type;
  final Node target;
  final List<Node> addedNodes;
  final List<Node> removedNodes;
  final Node? previousSibling;
  final Node? nextSibling;

  /// Attribute or property name for [MutationType.attributes] and
  /// [MutationType.property].
  final String? name;
  final String? oldValue;

  @override
  String toString() => 'MutationRecord(${type.name}, ${target.nodeName}'
      '${name == null ? '' : ', $name'})';
}

typedef MutationListener = void Function(MutationRecord record);
