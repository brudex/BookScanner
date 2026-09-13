class Folder {
  const Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.parentId,
  });

  final String id;
  final String name;
  final String? parentId;
  final DateTime createdAt;

  Folder copyWith({String? name, String? parentId, bool? clearParentId}) =>
      Folder(
        id: id,
        name: name ?? this.name,
        parentId: (clearParentId ?? false) ? null : (parentId ?? this.parentId),
        createdAt: createdAt,
      );
}

class Tag {
  const Tag({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) => other is Tag && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
