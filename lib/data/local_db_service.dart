import 'package:hive_flutter/hive_flutter.dart';
import '../domain/place.dart';

class LocalDbService {
  static const _boxName = 'saved_places';
  static Box? _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
  }

  static List<Place> getAllSaved() {
    final box = _box!;
    final list = box.values
        .map((e) => Place.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    // ✅ 최근 저장순(저장 시간이 없는 옛 데이터는 맨 뒤로)
    list.sort((a, b) {
      final at = a.savedAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.savedAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });

    return list;
  }

  static Place? getById(String placeId) {
    final box = _box!;
    if (!box.containsKey(placeId)) return null;
    final raw = box.get(placeId);
    if (raw is Map) return Place.fromJson(Map<String, dynamic>.from(raw));
    return null;
  }

  static bool isSaved(String placeId) => _box!.containsKey(placeId);

  static Future<void> save(Place place) async {
    await _box!.put(place.placeId, place.toJson());
  }

  static Future<void> remove(String placeId) async {
    await _box!.delete(placeId);
  }


/// ✅ 여러 개 한 번에 삭제 (bulk)
static Future<void> removeMany(Iterable<String> placeIds) async {
  final box = _box!;
  for (final id in placeIds) {
    await box.delete(id);
  }
}

/// ✅ 여러 개 한 번에 저장 (bulk)
static Future<void> saveMany(Iterable<Place> places) async {
  final box = _box!;
  for (final p in places) {
    await box.put(p.placeId, p.toJson());
  }
}

}
