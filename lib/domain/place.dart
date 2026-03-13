class Place {
  final String placeId;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final String category;

  // ✅ 추가: 저장 데이터
  final String memo;              // 사용자 메모
  final List<String> tags;        // 태그들
  final bool visited;             // 방문 여부(레거시/호환)
  final int visitedCount;         // 방문 횟수
  final DateTime? lastVisitedAt;  // 마지막 방문 시각
  final bool isFavorite;          // 즐겨찾기(핀)
  final DateTime? savedAt;        // 저장 시각(저장된 항목이면 존재)

  const Place({
    required this.placeId,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.category,
    this.memo = '',
    this.tags = const [],
    this.visited = false,
    this.visitedCount = 0,
    this.lastVisitedAt,
    this.isFavorite = false,
    this.savedAt,
  });

  Place copyWith({
    String? memo,
    List<String>? tags,
    bool? visited,
    int? visitedCount,
    DateTime? lastVisitedAt,
    bool? isFavorite,
    DateTime? savedAt,
    String? name,
    String? address,
    double? lat,
    double? lng,
    String? category,
  }) {
    return Place(
      placeId: placeId,
      name: name ?? this.name,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      category: category ?? this.category,
      memo: memo ?? this.memo,
      tags: tags ?? this.tags,
      visited: visited ?? this.visited,
      visitedCount: visitedCount ?? this.visitedCount,
      lastVisitedAt: lastVisitedAt ?? this.lastVisitedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'placeId': placeId,
    'name': name,
    'address': address,
    'lat': lat,
    'lng': lng,
    'category': category,
    'memo': memo,
    'tags': tags,
    'visited': visited,
    'visitedCount': visitedCount,
    'lastVisitedAt': lastVisitedAt?.millisecondsSinceEpoch,
    'isFavorite': isFavorite,
    'savedAt': savedAt?.millisecondsSinceEpoch, // ✅ epoch로 저장
  };

  factory Place.fromJson(Map<String, dynamic> json) {
    // ✅ 과거 데이터(필드 없던 시절) 호환
    final tagsRaw = json['tags'];
    final tags = (tagsRaw is List)
        ? tagsRaw.map((e) => e.toString()).where((t) => t.trim().isNotEmpty).toList()
        : <String>[];

    final savedAtMs = json['savedAt'];
    DateTime? savedAt;
    if (savedAtMs is int) savedAt = DateTime.fromMillisecondsSinceEpoch(savedAtMs);

    final lastVisitedAtMs = json['lastVisitedAt'];
    DateTime? lastVisitedAt;
    if (lastVisitedAtMs is int) {
      lastVisitedAt = DateTime.fromMillisecondsSinceEpoch(lastVisitedAtMs);
    }

    final visitedCount = (json['visitedCount'] as num?)?.toInt() ?? 0;

    return Place(
      placeId: (json['placeId'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      address: (json['address'] ?? '') as String,
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      category: (json['category'] ?? '') as String,
      memo: (json['memo'] ?? '') as String,
      tags: tags,
      visited: (json['visited'] as bool?) ?? (visitedCount > 0),
      visitedCount: visitedCount,
      lastVisitedAt: lastVisitedAt,
      isFavorite: (json['isFavorite'] as bool?) ?? false,
      savedAt: savedAt,
    );
  }
}
