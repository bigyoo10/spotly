import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/collections_db_service.dart';

/// placeId -> folderId mapping
final placeFolderMapProvider =
    NotifierProvider<PlaceFolderMapNotifier, Map<String, String>>(
        PlaceFolderMapNotifier.new);

class PlaceFolderMapNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() {
    return CollectionsDbService.getAllMembership();
  }

  Future<void> refresh() async {
    state = CollectionsDbService.getAllMembership();
  }

  String? folderIdOf(String placeId) => state[placeId];

  Future<void> setFolder(String placeId, String? folderId) async {
    await CollectionsDbService.setPlaceFolder(placeId: placeId, folderId: folderId);
    await refresh();
  }



Future<void> setFolderBulk(Iterable<String> placeIds, String? folderId) async {
  await CollectionsDbService.setPlacesFolder(placeIds: placeIds, folderId: folderId);
  await refresh();
}

Future<void> clearPlaces(Iterable<String> placeIds) async {
  await CollectionsDbService.clearPlaces(placeIds);
  await refresh();
}


  Future<void> clearPlace(String placeId) async {
    await CollectionsDbService.clearPlace(placeId);
    await refresh();
  }
}
