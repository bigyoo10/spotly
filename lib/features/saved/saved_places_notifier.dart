import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/collections_db_service.dart';
import '../../data/local_db_service.dart';
import '../../domain/place.dart';

final savedPlacesProvider =
    NotifierProvider<SavedPlacesNotifier, List<Place>>(SavedPlacesNotifier.new);

class SavedPlacesNotifier extends Notifier<List<Place>> {
  @override
  List<Place> build() => LocalDbService.getAllSaved();

  Place? findById(String placeId) {
    for (final p in state) {
      if (p.placeId == placeId) return p;
    }
    return null;
  }

  bool contains(String placeId) => state.any((p) => p.placeId == placeId);

  Future<void> refresh() async {
    state = LocalDbService.getAllSaved();
  }

  /// ✅ 저장/업데이트
  Future<void> upsert(Place place) async {
    final saved = contains(place.placeId);

    final toSave = saved
        ? place.copyWith(savedAt: place.savedAt ?? DateTime.now())
        : place.copyWith(savedAt: DateTime.now());

    await LocalDbService.save(toSave);
    state = LocalDbService.getAllSaved();
  }

  Future<void> remove(String placeId) async {
    await LocalDbService.remove(placeId);
    await CollectionsDbService.clearPlace(placeId);
    state = LocalDbService.getAllSaved();
  }

  /// ✅ 빠른 토글(저장/삭제)
  Future<void> toggleSimple(Place place) async {
    if (contains(place.placeId)) {
      await remove(place.placeId);
    } else {
      await upsert(place);
    }
  }

  /// ✅ 방문여부 토글
  Future<void> toggleVisited(String placeId) async {
    final existing = LocalDbService.getById(placeId);
    if (existing == null) return;
    await upsert(existing.copyWith(visited: !existing.visited));
  }

  /// ⭐ 즐겨찾기 토글
  Future<void> toggleFavorite(String placeId) async {
    final existing = LocalDbService.getById(placeId);
    if (existing == null) return;
    await upsert(existing.copyWith(isFavorite: !existing.isFavorite));
  }

  /// ✅ 방문 기록 추가(방문횟수 +1, 마지막 방문시각 갱신)
  Future<void> markVisited(String placeId) async {
    final existing = LocalDbService.getById(placeId);
    if (existing == null) return;

    final now = DateTime.now();
    final nextCount = existing.visitedCount + 1;

    await upsert(
      existing.copyWith(
        visited: true,
        visitedCount: nextCount,
        lastVisitedAt: now,
      ),
    );
  }

  // -------------------- Bulk --------------------

  Future<void> removeMany(Iterable<String> placeIds) async {
    await LocalDbService.removeMany(placeIds);
    await CollectionsDbService.clearPlaces(placeIds);
    state = LocalDbService.getAllSaved();
  }

  Future<void> toggleFavoriteMany(Iterable<String> placeIds) async {
    for (final id in placeIds) {
      final existing = LocalDbService.getById(id);
      if (existing == null) continue;
      await LocalDbService.save(
        existing.copyWith(isFavorite: !existing.isFavorite),
      );
    }
    state = LocalDbService.getAllSaved();
  }

  Future<void> markVisitedMany(Iterable<String> placeIds) async {
    final now = DateTime.now();
    for (final id in placeIds) {
      final existing = LocalDbService.getById(id);
      if (existing == null) continue;
      await LocalDbService.save(
        existing.copyWith(
          visited: true,
          visitedCount: existing.visitedCount + 1,
          lastVisitedAt: now,
        ),
      );
    }
    state = LocalDbService.getAllSaved();
  }

  // -------------------- Undo helpers --------------------

  /// Undo for visited badge action
  Future<void> restoreVisitedSnapshot({
    required String placeId,
    required bool visited,
    required int visitedCount,
    DateTime? lastVisitedAt,
  }) async {
    final existing = LocalDbService.getById(placeId);
    if (existing == null) return;

    await LocalDbService.save(
      existing.copyWith(
        visited: visited,
        visitedCount: visitedCount,
        lastVisitedAt: lastVisitedAt,
      ),
    );
    state = LocalDbService.getAllSaved();
  }

  /// Undo for removing a single place (optionally restore its folder)
  Future<void> restoreRemovedOne({
    required Place place,
    String? folderId,
  }) async {
    await LocalDbService.save(place);
    await CollectionsDbService.setPlaceFolder(
      placeId: place.placeId,
      folderId: folderId,
    );
    state = LocalDbService.getAllSaved();
  }

  /// Undo for removing multiple places
  Future<void> restoreRemoved({
    required List<Place> places,
    Map<String, String?>? folderIdsByPlaceId,
  }) async {
    await LocalDbService.saveMany(places);

    if (folderIdsByPlaceId != null) {
      for (final p in places) {
        await CollectionsDbService.setPlaceFolder(
          placeId: p.placeId,
          folderId: folderIdsByPlaceId[p.placeId],
        );
      }
    }
    state = LocalDbService.getAllSaved();
  }
}
