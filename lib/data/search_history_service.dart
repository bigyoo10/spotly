import 'package:hive_flutter/hive_flutter.dart';

/// 최근 검색어 저장소 (Hive)
/// - 최신이 위로
/// - 중복 제거
/// - 최대 10개 유지
class SearchHistoryService {
  static const String boxName = 'search_history';
  static const int limit = 10;

  static Box<String>? _box;

  /// main()에서 LocalDbService.init() 이후에 호출해줘.
  static Future<void> init() async {
    // Hive.initFlutter()는 LocalDbService.init()에서 이미 호출됨
    _box ??= await Hive.openBox<String>(boxName);
  }

  static List<String> getAll() {
    final box = _box;
    if (box == null) return const [];
    return box.values.toList().reversed.toList();
  }

  static Future<void> add(String q) async {
    final box = _box;
    if (box == null) return;

    final query = q.trim();
    if (query.isEmpty) return;

    // 중복 제거
    dynamic dupKey;
    for (final k in box.keys) {
      if (box.get(k) == query) {
        dupKey = k;
        break;
      }
    }
    if (dupKey != null) {
      await box.delete(dupKey);
    }

    await box.add(query);

    // limit 유지 (가장 오래된 것부터 삭제)
    while (box.length > limit) {
      await box.deleteAt(0);
    }
  }

  static Future<void> remove(String q) async {
    final box = _box;
    if (box == null) return;

    dynamic targetKey;
    for (final k in box.keys) {
      if (box.get(k) == q) {
        targetKey = k;
        break;
      }
    }
    if (targetKey != null) {
      await box.delete(targetKey);
    }
  }

  static Future<void> clear() async {
    final box = _box;
    if (box == null) return;
    await box.clear();
  }
}
