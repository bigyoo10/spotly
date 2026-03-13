import 'package:hive_flutter/hive_flutter.dart';

import '../domain/collection_folder.dart';

/// Collections v1
/// - Folders (collection_folders)
/// - Place -> folder mapping (collection_membership)
class CollectionsDbService {
  static const _foldersBoxName = 'collection_folders';
  static const _membershipBoxName = 'collection_membership';

  static Box? _foldersBox;
  static Box? _membershipBox;

  static Future<void> init() async {
    // Hive.initFlutter() is called by LocalDbService.init()
    _foldersBox ??= await Hive.openBox(_foldersBoxName);
    _membershipBox ??= await Hive.openBox(_membershipBoxName);
  }

  // -------------------- Folders --------------------

  static List<CollectionFolder> getAllFolders() {
    final box = _foldersBox!;
    final list = box.values
        .whereType<Map>()
        .map((e) => CollectionFolder.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  static Future<void> upsertFolder(CollectionFolder folder) async {
    await _foldersBox!.put(folder.id, folder.toJson());
  }

  static Future<void> deleteFolder(String folderId) async {
    await _foldersBox!.delete(folderId);

    // Also clear memberships pointing to this folder.
    final membership = _membershipBox!;
    final keysToClear = <dynamic>[];
    for (final key in membership.keys) {
      final v = membership.get(key);
      if (v == folderId) keysToClear.add(key);
    }
    for (final k in keysToClear) {
      await membership.delete(k);
    }
  }

  // -------------------- Membership --------------------

  static String? getFolderIdForPlace(String placeId) {
    final v = _membershipBox!.get(placeId);
    return v is String && v.trim().isNotEmpty ? v : null;
  }

  static Map<String, String> getAllMembership() {
    final box = _membershipBox!;
    final map = <String, String>{};
    for (final k in box.keys) {
      final key = k?.toString() ?? '';
      final v = box.get(k);
      if (key.isEmpty) continue;
      if (v is String && v.trim().isNotEmpty) {
        map[key] = v;
      }
    }
    return map;
  }

  static Future<void> setPlaceFolder({
    required String placeId,
    String? folderId,
  }) async {
    if (folderId == null || folderId.trim().isEmpty) {
      await _membershipBox!.delete(placeId);
      return;
    }
    await _membershipBox!.put(placeId, folderId);
  }

  static Future<void> clearPlace(String placeId) async {
    await _membershipBox!.delete(placeId);
  }


/// ✅ 여러 placeId를 한 번에 폴더로 이동 (bulk)
static Future<void> setPlacesFolder({
  required Iterable<String> placeIds,
  String? folderId,
}) async {
  if (folderId == null || folderId.trim().isEmpty) {
    for (final id in placeIds) {
      await _membershipBox!.delete(id);
    }
    return;
  }
  for (final id in placeIds) {
    await _membershipBox!.put(id, folderId);
  }
}

/// ✅ 여러 placeId의 폴더 매핑 삭제 (bulk)
static Future<void> clearPlaces(Iterable<String> placeIds) async {
  for (final id in placeIds) {
    await _membershipBox!.delete(id);
  }
}


  // -------------------- Utils --------------------

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
