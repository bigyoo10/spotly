import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/collections_db_service.dart';
import '../../domain/collection_folder.dart';

final collectionFoldersProvider =
    NotifierProvider<CollectionFoldersNotifier, List<CollectionFolder>>(
        CollectionFoldersNotifier.new);

class CollectionFoldersNotifier extends Notifier<List<CollectionFolder>> {
  @override
  List<CollectionFolder> build() {
    return CollectionsDbService.getAllFolders();
  }

  Future<void> refresh() async {
    state = CollectionsDbService.getAllFolders();
  }

  /// Create a new folder and return its id.
  /// Returns null when [name] is empty after trimming.
  Future<String?> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    final folder = CollectionFolder(
      id: CollectionsDbService.newId(),
      name: trimmed,
      createdAt: DateTime.now(),
    );

    await CollectionsDbService.upsertFolder(folder);
    await refresh();
    return folder.id;
  }

  Future<void> rename(String folderId, String newName) async {
    final existing = state.where((f) => f.id == folderId).toList();
    if (existing.isEmpty) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;

    final updated = existing.first.copyWith(name: trimmed);
    await CollectionsDbService.upsertFolder(updated);
    await refresh();
  }

  Future<void> delete(String folderId) async {
    await CollectionsDbService.deleteFolder(folderId);
    await refresh();
  }
}
