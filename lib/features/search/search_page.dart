import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'search_controller.dart';
import '../saved/saved_places_notifier.dart';
import '../collections/collection_folders_notifier.dart';
import '../collections/place_folder_notifier.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _scrollController = ScrollController();
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // 스크롤이 끝에 가까워지면 다음 페이지 로드
    _scrollController.addListener(() {
      final pos = _scrollController.position;
      if (!pos.hasPixels || !pos.hasContentDimensions) return;

      // 끝에서 300px 남았을 때 loadMore
      if (pos.pixels >= pos.maxScrollExtent - 300) {
        ref.read(searchControllerProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);
    final savedIds = ref.watch(
      savedPlacesProvider.select((list) => list.map((e) => e.placeId).toSet()),
    );

    final folders = ref.watch(collectionFoldersProvider);
    final folderMap = ref.watch(placeFolderMapProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
          IconButton(
            icon: const Icon(Icons.map),
            tooltip: '지도에서 보기',
            onPressed: () => context.go('/map'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                hintText: '예) 잠실 카페, 강남 헬스장...',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: state.query.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: '지우기',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _textController.clear();
                          ref
                              .read(searchControllerProvider.notifier)
                              .onQueryChanged('');
                        },
                      ),
              ),
              onChanged: (v) =>
                  ref.read(searchControllerProvider.notifier).onQueryChanged(v),
              onSubmitted: (_) async {
                final q = _textController.text.trim();
                if (q.isEmpty) return;
                await ref.read(searchControllerProvider.notifier).submit(q);
              },
            ),
          ),

          if (state.loading) const LinearProgressIndicator(),

          // 에러 상태 + 재시도
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '에러: ${state.error}',
                      style: const TextStyle(color: Colors.red),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () =>
                        ref.read(searchControllerProvider.notifier).retry(),
                    child: const Text('재시도'),
                  ),
                ],
              ),
            ),

          Expanded(
            child: Builder(
              builder: (_) {
                final q = state.query.trim();

                // ✅ 최근 검색어
                if (q.isEmpty) {
                  final recents = state.recent;
                  if (recents.isEmpty) {
                    return const Center(child: Text('최근 검색어가 없어요. 위에서 검색해보세요 🙂'));
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '최근 검색어',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                await ref.read(searchControllerProvider.notifier).clearRecents();
                              },
                              child: const Text('전체 삭제'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final r in recents)
                              InputChip(
                                label: Text(r),
                                onPressed: () async {
                                  _textController.text = r;
                                  _textController.selection = TextSelection.fromPosition(
                                    TextPosition(offset: r.length),
                                  );
                                  await ref.read(searchControllerProvider.notifier).submit(r);
                                },
                                onDeleted: () async {
                                  await ref.read(searchControllerProvider.notifier).removeRecent(r);
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                }

                if (!state.loading && q.isNotEmpty && state.results.isEmpty) {
                  return const Center(child: Text('검색 결과가 없어요.'));
                }

                return ListView.separated(
                  controller: _scrollController,
                  itemCount: state.results.length + 1, // 마지막에 “로딩 더보기” 영역
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i == state.results.length) {
                      // 리스트 맨 아래(추가 로딩 영역)
                      if (state.loadingMore) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (!state.isEnd && state.results.isNotEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: Text('더 불러오는 중...')),
                        );
                      }
                      return const SizedBox(height: 24);
                    }

                    final p = state.results[i];
                    final isSaved = savedIds.contains(p.placeId);

                    final folderId = folderMap[p.placeId];
                    final folderName = folderId == null
                        ? null
                        : folders
                            .where((f) => f.id == folderId)
                            .map((f) => f.name)
                            .cast<String?>()
                            .firstOrNull;

                    final categoryShort = p.category.trim().isEmpty
                        ? ''
                        : (p.category.contains('>')
                        ? p.category.split('>').last.trim()
                        : p.category.trim());

                    return ListTile(
                      title: Text(p.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.address),
                          if (categoryShort.isNotEmpty)
                            Text(
                              categoryShort,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          if (isSaved && folderName != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('📁 $folderName', style: const TextStyle(color: Colors.grey)),
                            ),
                        ],
                      ),
                      trailing: IconButton(
                        tooltip: isSaved ? '저장 취소' : '저장',
                        icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
                        onPressed: () async {
                          // 저장된 상태면 바로 제거
                          if (isSaved) {
                            await ref.read(savedPlacesProvider.notifier).remove(p.placeId);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('저장에서 제거했어요'),
                                duration: Duration(milliseconds: 900),
                              ),
                            );
                            return;
                          }

                          // ✅ 저장 시 폴더 선택 (취소하면 저장하지 않음)
                          final picked = await _pickFolderId(context);
                          if (picked == null) return; // cancelled

                          final folderIdToSet = picked == '__unfiled__' ? null : picked;

                          await ref.read(savedPlacesProvider.notifier).upsert(p);
                          await ref.read(placeFolderMapProvider.notifier).setFolder(p.placeId, folderIdToSet);

                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(folderIdToSet == null ? '미분류로 저장했어요' : '폴더에 저장했어요'),
                              duration: const Duration(milliseconds: 900),
                            ),
                          );
                        },
                      ),
                      onTap: () {
                        // ✅ 검색어 확정(Enter 없이 결과를 탭해도 최근검색어에 저장)
                        ref.read(searchControllerProvider.notifier).commitCurrentQuery();
                        context.push('/place', extra: p);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickFolderId(BuildContext context) async {
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
                  const Text('어느 폴더에 저장할까요?',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.folder_off_outlined),
                    title: const Text('미분류로 저장'),
                    onTap: () => Navigator.of(ctx).pop('__unfiled__'),
                  ),
                  const Divider(height: 1),
                  if (folders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('아직 폴더가 없어요. 아래에서 새로 만들어보세요.'),
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
                            title: Text(f.name),
                            onTap: () => Navigator.of(ctx).pop(f.id),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('새 폴더 만들기'),
                      onPressed: () async {
                        final name = await _promptNewFolderName(ctx);
                        if (name == null) return;
                        final newId = await ref.read(collectionFoldersProvider.notifier).create(name);
                        if (newId == null) return;
                        if (ctx.mounted) Navigator.of(ctx).pop(newId);
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

  Future<String?> _promptNewFolderName(BuildContext context) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('새 폴더'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: '예: 카공, 맛집, 데이트'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('만들기')),
          ],
        );
      },
    );
    if (ok != true) return null;
    final name = controller.text.trim();
    if (name.isEmpty) return null;
    return name;
  }
}

extension _FirstOrNullExt<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
