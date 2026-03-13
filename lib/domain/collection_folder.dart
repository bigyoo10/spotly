class CollectionFolder {
  final String id;
  final String name;
  final DateTime createdAt;

  const CollectionFolder({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  CollectionFolder copyWith({
    String? name,
  }) {
    return CollectionFolder(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory CollectionFolder.fromJson(Map<String, dynamic> json) {
    final createdAtMs = json['createdAt'];
    final createdAt = (createdAtMs is int)
        ? DateTime.fromMillisecondsSinceEpoch(createdAtMs)
        : DateTime.now();

    return CollectionFolder(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      createdAt: createdAt,
    );
  }
}
