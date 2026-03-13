import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/place.dart';
import '../map/map_focus_provider.dart';
import '../collections/collection_folders_notifier.dart';
import '../collections/place_folder_notifier.dart';
import 'saved_places_notifier.dart';

final selectedTagProvider = StateProvider<String?>((ref) => null);
final selectedFolderProvider = StateProvider<String?>((ref) => null);
final savedSearchQueryProvider = StateProvider<String>((ref) => '');

final savedFavoritesOnlyProvider = StateProvider<bool>((ref) => false);

/// Saved 관리 v2: 다중 선택 모드
final savedSelectionModeProvider = StateProvider<bool>((ref) => false);
final savedSelectedIdsProvider = StateProvider<Set<String>>((ref) => <String>{});

  enum SavedSort {
  recent,
  oldest,
  nameAsc,
  favoritesFirst,
  recentVisited,
  }

extension SavedSortX on SavedSort {
  String get label {
    switch (this) {
      case SavedSort.recent:
        return '최근 저장순';
      case SavedSort.oldest:
        return '오래된 저장순';
      case SavedSort.nameAsc:
        return '이름 오름차순';
      case SavedSort.favoritesFirst:
        return '즐겨찾기 우선';
      case SavedSort.recentVisited:
        return '최근 방문순';
    }
  }
}

final savedSortProvider = StateProvider<SavedSort>((ref) => SavedSort.recent);

class SavedPage extends ConsumerWidget {
  const SavedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedPlacesProvider);
    final folders = ref.watch(collectionFoldersProvider);
    final folderMap = ref.watch(placeFolderMapProvider);

    final selectedTag = ref.watch(selectedTagProvider);
    final selectedFolder = ref.watch(selectedFolderProvider);
    final q = ref.watch(savedSearchQueryProvider).trim().toLowerCase();
    final sort = ref.watch(savedSortProvider);
    final favoritesOnly = ref.watch(savedFavoritesOnlyProvider);

    final hasActiveFilters = selectedTag != null ||
        selectedFolder != null ||
        q.isNotEmpty ||
        favoritesOnly ||
        sort != SavedSort.recent;

    final selectionMode = ref.watch(savedSelectionModeProvider);
    final selectedIds = ref.watch(savedSelectedIdsProvider);

    final allTags = <String>{};
    for (final p in saved) {
      allTags.addAll(p.tags);
    }
    final tagList = allTags.toList()..sort();

    List<Place> filtered = [...saved];

    if (selectedFolder != null) {
      if (selectedFolder == '__unfiled__') {
        filtered =
            filtered.where((p) => !folderMap.containsKey(p.placeId)).toList();
      } else {
        filtered =
            filtered.where((p) => folderMap[p.placeId] == selectedFolder).toList();
      }
    }

    if (selectedTag != null) {
      filtered = filtered.where((p) => p.tags.contains(selectedTag)).toList();
    }

    if (q.isNotEmpty) {
      bool matches(Place p) {
        final hay = <String>[
          p.name,
          p.address,
          p.memo,
          p.category,
          p.tags.join(' '),
        ].join(' ').toLowerCase();
        return hay.contains(q);
      }

      filtered = filtered.where(matches).toList();
    }

    if (favoritesOnly) {
      filtered = filtered.where((p) => p.isFavorite).toList();
    }

    filtered.sort((a, b) {
      switch (sort) {
        case SavedSort.recent:
          final at = a.savedAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.savedAt?.millisecondsSinceEpoch ?? 0;
          return bt.compareTo(at);
        case SavedSort.oldest:
          final at = a.savedAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.savedAt?.millisecondsSinceEpoch ?? 0;
          return at.compareTo(bt);
        case SavedSort.nameAsc:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case SavedSort.favoritesFirst:
          final af = a.isFavorite ? 0 : 1;
          final bf = b.isFavorite ? 0 : 1;
          final c = af.compareTo(bf);
          if (c != 0) return c;
          final at = a.savedAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.savedAt?.millisecondsSinceEpoch ?? 0;
          return bt.compareTo(at);
        case SavedSort.recentVisited:
          final at = a.lastVisitedAt?.millisecondsSinceEpoch ?? 0;
          final bt = b.lastVisitedAt?.millisecondsSinceEpoch ?? 0;
          if (at == 0 && bt == 0) {
            final sa = a.savedAt?.millisecondsSinceEpoch ?? 0;
            final sb = b.savedAt?.millisecondsSinceEpoch ?? 0;
            return sb.compareTo(sa);
          }
          if (at == 0) return 1;
          if (bt == 0) return -1;
          return bt.compareTo(at);
      }
    });

    return Scaffold(
      bottomNavigationBar: selectionMode
          ? _SavedBulkBar(
              count: selectedIds.length,
              onMoveFolder: () async {
                if (selectedIds.isEmpty) return;
                final picked = await _pickFolderId(context, ref);
                if (picked == null) return;

                final folderIdToSet = picked == '__unfiled__' ? null : picked;

                final prevFolderById = <String, String?>{};
                for (final id in selectedIds) {
                  prevFolderById[id] = folderMap[id];
                }

                await ref
                    .read(placeFolderMapProvider.notifier)
                    .setFolderBulk(selectedIds, folderIdToSet);

                if (!context.mounted) return;
                final movedTo = folderIdToSet == null
                    ? '미분류'
                    : (folders
                                .where((f) => f.id == folderIdToSet)
                                .map((f) => f.name)
                                .firstOrNull ??
                            '폴더');

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${selectedIds.length}개를 "$movedTo"(으)로 이동했어요'),
                    action: SnackBarAction(
                      label: '되돌리기',
                      onPressed: () async {
                        for (final entry in prevFolderById.entries) {
                          await ref
                              .read(placeFolderMapProvider.notifier)
                              .setFolder(entry.key, entry.value);
                        }
                      },
                    ),
                  ),
                );
              },
              onToggleFavorite: () async {
                if (selectedIds.isEmpty) return;
                await ref
                    .read(savedPlacesProvider.notifier)
                    .toggleFavoriteMany(selectedIds);
              },
              onMarkVisited: () async {
                if (selectedIds.isEmpty) return;
                await ref
                    .read(savedPlacesProvider.notifier)
                    .markVisitedMany(selectedIds);
              },
              onDelete: () async {
                if (selectedIds.isEmpty) return;
                final ok = await _confirm(
                  context,
                  title: '삭제할까요?',
                  message: '${selectedIds.length}개 장소를 저장 목록에서 삭제합니다.',
                  okText: '삭제',
                );
                if (ok != true) return;

                final removedPlaces =
                    saved.where((p) => selectedIds.contains(p.placeId)).toList();
                final removedFolderById = <String, String?>{};
                for (final id in selectedIds) {
                  removedFolderById[id] = folderMap[id];
                }

                await ref.read(savedPlacesProvider.notifier).removeMany(selectedIds);

                ref.read(savedSelectionModeProvider.notifier).state = false;
                ref.read(savedSelectedIdsProvider.notifier).state = <String>{};

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${removedPlaces.length}개를 저장 목록에서 삭제했어요'),
                    action: SnackBarAction(
                      label: '되돌리기',
                      onPressed: () {
                        ref.read(savedPlacesProvider.notifier).restoreRemoved(
                              places: removedPlaces,
                              folderIdsByPlaceId: removedFolderById,
                            );
                      },
                    ),
                  ),
                );
              },
            )
          : null,
      appBar: AppBar(
        title: selectionMode
            ? Text('${selectedIds.length}개 선택됨')
            : const Text('Saved'),
        leading: selectionMode
            ? IconButton(
                tooltip: '선택 해제',
                icon: const Icon(Icons.close),
                onPressed: () {
                  ref.read(savedSelectionModeProvider.notifier).state = false;
                  ref.read(savedSelectedIdsProvider.notifier).state = <String>{};
                },
              )
            : null,
        actions: selectionMode
            ? [
                IconButton(
                  tooltip: '전체 선택',
                  icon: const Icon(Icons.select_all),
                  onPressed: () {
                    final all = filtered.map((e) => e.placeId).toSet();
                    ref.read(savedSelectedIdsProvider.notifier).state = all;
                    if (all.isNotEmpty) {
                      ref.read(savedSelectionModeProvider.notifier).state = true;
                    }
                  },
                ),
                IconButton(
                  tooltip: '삭제',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () async {
                          final ok = await _confirm(
                            context,
                            title: '삭제할까요?',
                            message: '${selectedIds.length}개 장소를 저장 목록에서 삭제합니다.',
                            okText: '삭제',
                          );
                          if (ok != true) return;

                          final removedPlaces = saved
                              .where((p) => selectedIds.contains(p.placeId))
                              .toList();
                          final removedFolderById = <String, String?>{};
                          for (final id in selectedIds) {
                            removedFolderById[id] = folderMap[id];
                          }

                          await ref
                              .read(savedPlacesProvider.notifier)
                              .removeMany(selectedIds);

                          ref.read(savedSelectionModeProvider.notifier).state =
                              false;
                          ref.read(savedSelectedIdsProvider.notifier).state =
                              <String>{};

                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text('${removedPlaces.length}개를 저장 목록에서 삭제했어요'),
                              action: SnackBarAction(
                                label: '되돌리기',
                                onPressed: () {
                                  ref
                                      .read(savedPlacesProvider.notifier)
                                      .restoreRemoved(
                                        places: removedPlaces,
                                        folderIdsByPlaceId: removedFolderById,
                                      );
                                },
                              ),
                            ),
                          );
                        },
                ),
              ]
            : [
                IconButton(
                  tooltip: '폴더 관리',
                  icon: const Icon(Icons.folder_open),
                  onPressed: () => _openFolderManager(context, ref),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () async {
                    await ref.read(savedPlacesProvider.notifier).refresh();
                    await ref.read(collectionFoldersProvider.notifier).refresh();
                    await ref.read(placeFolderMapProvider.notifier).refresh();
                  },
                ),
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '이름/주소/메모/태그 검색',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '지우기',
                        icon: const Icon(Icons.close),
                        onPressed: () => ref
                            .read(savedSearchQueryProvider.notifier)
                            .state = '',
                      ),
              ),
              onChanged: (v) =>
                  ref.read(savedSearchQueryProvider.notifier).state = v,
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                const Icon(Icons.sort, size: 18),
                DropdownButton<SavedSort>(
                  value: sort,
                  onChanged: (v) {
                    if (v == null) return;
                    ref.read(savedSortProvider.notifier).state = v;
                  },
                  items: SavedSort.values
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s.label),
                          ))
                      .toList(),
                ),
                if (hasActiveFilters)
                  TextButton.icon(
                    onPressed: () {
                      ref.read(selectedFolderProvider.notifier).state = null;
                      ref.read(selectedTagProvider.notifier).state = null;
                      ref.read(savedSearchQueryProvider.notifier).state = '';
                      ref.read(savedFavoritesOnlyProvider.notifier).state = false;
                      ref.read(savedSortProvider.notifier).state =
                          SavedSort.recent;
                    },
                    icon: const Icon(Icons.filter_alt_off, size: 18),
                    label: const Text('초기화'),
                  ),
                Text(
                  '${filtered.length}개',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),

          SizedBox(
            height: 54,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              scrollDirection: Axis.horizontal,
              children: [
                ChoiceChip(
                  label: const Text('전체'),
                  selected: selectedFolder == null,
                  onSelected: (_) =>
                      ref.read(selectedFolderProvider.notifier).state = null,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('미분류'),
                  selected: selectedFolder == '__unfiled__',
                  onSelected: (_) => ref
                      .read(selectedFolderProvider.notifier)
                      .state = '__unfiled__',
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('⭐ 즐겨찾기만'),
                  selected: favoritesOnly,
                  onSelected: (v) =>
                      ref.read(savedFavoritesOnlyProvider.notifier).state = v,
                ),
                const SizedBox(width: 8),
                ...folders.map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.name),
                      selected: selectedFolder == f.id,
                      onSelected: (_) =>
                          ref.read(selectedFolderProvider.notifier).state = f.id,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (tagList.isNotEmpty)
            SizedBox(
              height: 54,
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                scrollDirection: Axis.horizontal,
                children: [
                  ChoiceChip(
                    label: const Text('태그 전체'),
                    selected: selectedTag == null,
                    onSelected: (_) =>
                        ref.read(selectedTagProvider.notifier).state = null,
                  ),
                  const SizedBox(width: 8),
                  ...tagList.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(t),
                        selected: selectedTag == t,
                        onSelected: (_) =>
                            ref.read(selectedTagProvider.notifier).state = t,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: filtered.isEmpty
                ? _SavedEmptyState(
                    isTrulyEmpty: saved.isEmpty,
                    hasActiveFilters: hasActiveFilters,
                    onGoMap: () => context.go('/map'),
                    onReset: () {
                      ref.read(selectedFolderProvider.notifier).state = null;
                      ref.read(selectedTagProvider.notifier).state = null;
                      ref.read(savedSearchQueryProvider.notifier).state = '';
                      ref.read(savedFavoritesOnlyProvider.notifier).state = false;
                      ref.read(savedSortProvider.notifier).state =
                          SavedSort.recent;
                    },
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      final folderId = folderMap[p.placeId];
                      final folderName = folderId == null
                          ? null
                          : folders
                                  .where((f) => f.id == folderId)
                                  .map((f) => f.name)
                                  .firstOrNull;

                      final isSelected = selectedIds.contains(p.placeId);

                      return _SavedTile(
                        place: p,
                        folderName: folderName,
                        selectionMode: selectionMode,
                        selected: isSelected,
                        onToggleSelected: () {
                          final next = <String>{...selectedIds};
                          if (next.contains(p.placeId)) {
                            next.remove(p.placeId);
                          } else {
                            next.add(p.placeId);
                          }
                          ref.read(savedSelectedIdsProvider.notifier).state = next;
                          if (next.isEmpty) {
                            ref.read(savedSelectionModeProvider.notifier).state =
                                false;
                          } else {
                            ref.read(savedSelectionModeProvider.notifier).state =
                                true;
                          }
                        },
                        onEnterSelection: () {
                          if (selectionMode) return;
                          ref.read(savedSelectionModeProvider.notifier).state =
                              true;
                          ref.read(savedSelectedIdsProvider.notifier).state = {
                            p.placeId
                          };
                        },
                        onOpenDetail: () => context.push('/place', extra: p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _openFolderManager(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Consumer(builder: (ctx, ref, _) {
            final folders = ref.watch(collectionFoldersProvider);

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '폴더',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => _promptCreateFolder(ctx, ref),
                          icon: const Icon(Icons.add),
                          label: const Text('추가'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (folders.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('아직 폴더가 없어요. "추가"로 만들어보세요.'),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: folders.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final f = folders[i];
                            return ListTile(
                              leading: const Icon(Icons.folder),
                              title: Text(
                                f.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: '이름 변경',
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _promptRenameFolder(
                                      ctx,
                                      ref,
                                      f.id,
                                      f.name,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '삭제',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () =>
                                        _confirmDeleteFolder(ctx, ref, f.id, f.name),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Future<void> _promptCreateFolder(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('폴더 추가'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '예: 맛집, 카페, 데이트코스'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('추가'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;
    await ref.read(collectionFoldersProvider.notifier).create(name);
  }

  Future<void> _promptRenameFolder(
    BuildContext context,
    WidgetRef ref,
    String folderId,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('폴더 이름 변경'),
          content: TextField(
            controller: controller,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;
    await ref.read(collectionFoldersProvider.notifier).rename(folderId, name);
  }

  Future<void> _confirmDeleteFolder(
    BuildContext context,
    WidgetRef ref,
    String folderId,
    String name,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('폴더 삭제'),
          content: Text('"$name" 폴더를 삭제할까요?\n\n폴더만 삭제되고, Saved(저장된 장소)는 유지돼요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    await ref.read(collectionFoldersProvider.notifier).delete(folderId);

    final selected = ref.read(selectedFolderProvider);
    if (selected == folderId) {
      ref.read(selectedFolderProvider.notifier).state = null;
    }
    await ref.read(placeFolderMapProvider.notifier).refresh();
  }
}

class _SavedTile extends ConsumerWidget {
  const _SavedTile({
    required this.place,
    this.folderName,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelected,
    required this.onEnterSelection,
    required this.onOpenDetail,
  });

  final Place place;
  final String? folderName;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onToggleSelected;
  final VoidCallback onEnterSelection;
  final VoidCallback onOpenDetail;

  String _fmtSavedAt(DateTime dt) {
    final s = dt.toLocal().toString();
    if (s.length >= 16) return s.substring(0, 16);
    return s;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAtText = place.savedAt == null ? '' : ' · ${_fmtSavedAt(place.savedAt!)}';
    final tagsText = place.tags.isEmpty ? '' : place.tags.join(' • ');

    return ListTile(
      selected: selectionMode && selected,
      selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
      leading: selectionMode
          ? Checkbox(
              value: selected,
              onChanged: (_) => onToggleSelected(),
            )
          : Icon(
              place.visited ? Icons.check_circle : Icons.bookmark,
              color: place.visited ? Colors.green : null,
            ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            place.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (folderName != null) _Pill(text: folderName!),
              if (!selectionMode && place.isFavorite)
                const Icon(Icons.star, size: 18, color: Colors.amber),
            ],
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            place.address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (place.visited)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _VisitedBadge(
                visitedCount: place.visitedCount,
                lastVisitedAt: place.lastVisitedAt,
                onTap: selectionMode
                    ? null
                    : () async {
                        final prevVisited = place.visited;
                        final prevCount = place.visitedCount;
                        final prevLast = place.lastVisitedAt;

                        await ref
                            .read(savedPlacesProvider.notifier)
                            .markVisited(place.placeId);

                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('방문 기록이 추가됐어요'),
                            action: SnackBarAction(
                              label: '되돌리기',
                              onPressed: () {
                                ref
                                    .read(savedPlacesProvider.notifier)
                                    .restoreVisitedSnapshot(
                                      placeId: place.placeId,
                                      visited: prevVisited,
                                      visitedCount: prevCount,
                                      lastVisitedAt: prevLast,
                                    );
                              },
                            ),
                          ),
                        );
                      },
              ),
            ),
          if (tagsText.isNotEmpty)
            Text(
              tagsText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey),
            ),
          if (place.memo.trim().isNotEmpty)
            Text(
              '📝 ${place.memo}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (savedAtText.isNotEmpty)
            Text(
              savedAtText,
              style: const TextStyle(color: Colors.grey),
            ),
        ],
      ),
      trailing: selectionMode
          ? const Icon(Icons.chevron_right, color: Colors.transparent)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '지도에서 보기',
                  icon: const Icon(Icons.map_outlined),
                  onPressed: () {
                    ref.read(mapFocusProvider.notifier).focus(place);
                    context.go('/map');
                  },
                ),
                IconButton(
                  tooltip: '즐겨찾기',
                  icon: Icon(
                    place.isFavorite ? Icons.star : Icons.star_border,
                    color: place.isFavorite ? Colors.amber : null,
                  ),
                  onPressed: () => ref
                      .read(savedPlacesProvider.notifier)
                      .toggleFavorite(place.placeId),
                ),
                _FolderMenu(placeId: place.placeId),
              ],
            ),
      onTap: selectionMode ? onToggleSelected : onOpenDetail,
      onLongPress: onEnterSelection,
    );
  }
}

class _VisitedBadge extends StatelessWidget {
  const _VisitedBadge({
    required this.visitedCount,
    required this.lastVisitedAt,
    required this.onTap,
  });

  final int visitedCount;
  final DateTime? lastVisitedAt;
  final VoidCallback? onTap;

  String _fmtShort(DateTime dt) {
    final s = dt.toLocal().toString();
    if (s.length >= 16) return s.substring(5, 16);
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = cs.primaryContainer;
    final fg = cs.onPrimaryContainer;
    final bd = cs.primary.withOpacity(0.35);

    final last = lastVisitedAt;
    final subtitle = last == null ? '방문함' : '최근: ${_fmtShort(last)}';

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: bd),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              '방문${visitedCount > 0 ? ' · $visitedCount' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: fg),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderMenu extends ConsumerWidget {
  const _FolderMenu({required this.placeId});
  final String placeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(collectionFoldersProvider);
    final current = ref.watch(placeFolderMapProvider)[placeId];

    return PopupMenuButton<String?>(
      tooltip: '폴더로 이동',
      icon: const Icon(Icons.more_vert),
      onSelected: (folderId) async {
        final prev = current;
        await ref.read(placeFolderMapProvider.notifier).setFolder(placeId, folderId);

        if (!context.mounted) return;
        final movedTo = folderId == null
            ? '미분류'
            : (folders.where((f) => f.id == folderId).map((f) => f.name).firstOrNull ?? '폴더');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('폴더를 "$movedTo"(으)로 이동했어요'),
            action: SnackBarAction(
              label: '되돌리기',
              onPressed: () {
                ref.read(placeFolderMapProvider.notifier).setFolder(placeId, prev);
              },
            ),
          ),
        );
      },
      itemBuilder: (ctx) {
        return <PopupMenuEntry<String?>>[
          const PopupMenuItem<String?>(
            value: null,
            child: Text('미분류로'),
          ),
          const PopupMenuDivider(),
          ...folders.map(
            (f) => CheckedPopupMenuItem<String?>(
              value: f.id,
              checked: current == f.id,
              child: Text(
                f.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ];
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }
}

class _SavedBulkBar extends StatelessWidget {
  const _SavedBulkBar({
    required this.count,
    required this.onMoveFolder,
    required this.onToggleFavorite,
    required this.onMarkVisited,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onMoveFolder;
  final VoidCallback onToggleFavorite;
  final VoidCallback onMarkVisited;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final disabled = count <= 0;

    return SafeArea(
      top: false,
      child: Material(
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count개 선택됨',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 48 * 2 + 8,
                ),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open),
                        label: const Text('폴더'),
                        onPressed: disabled ? null : onMoveFolder,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.star),
                        label: const Text('즐겨찾기'),
                        onPressed: disabled ? null : onToggleFavorite,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.check_circle),
                        label: const Text('방문+1'),
                        onPressed: disabled ? null : onMarkVisited,
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('삭제'),
                        onPressed: disabled ? null : onDelete,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String okText,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(okText),
          ),
        ],
      );
    },
  );
}

Future<String?> _pickFolderId(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<String?>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return Consumer(builder: (ctx, ref, _) {
        final folders = ref.watch(collectionFoldersProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '어느 폴더로 이동할까요?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined),
                  title: const Text('미분류로'),
                  onTap: () => Navigator.of(ctx).pop('__unfiled__'),
                ),
                const Divider(height: 1),
                if (folders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('아직 폴더가 없어요. 먼저 폴더를 만들어주세요.'),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: folders.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final f = folders[i];
                        return ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(ctx).pop(f.id),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      });
    },
  );
}

class _SavedEmptyState extends StatelessWidget {
  const _SavedEmptyState({
    required this.isTrulyEmpty,
    required this.hasActiveFilters,
    required this.onGoMap,
    required this.onReset,
  });

  final bool isTrulyEmpty;
  final bool hasActiveFilters;
  final VoidCallback onGoMap;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    if (isTrulyEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bookmark_border, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text(
                '아직 저장한 장소가 없어요',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                '지도에서 검색 후 저장해보세요.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onGoMap,
                icon: const Icon(Icons.map_outlined),
                label: const Text('지도에서 장소 찾기'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              '조건에 맞는 장소가 없어요',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              hasActiveFilters ? '필터/검색 조건을 초기화해보세요.' : '다른 조건으로 찾아보세요.',
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('초기화'),
                ),
                FilledButton.icon(
                  onPressed: onGoMap,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('지도'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNullExt<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
