import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/debouncer.dart';
import '../../domain/place.dart';
import '../collections/collection_folders_notifier.dart';
import '../collections/place_folder_notifier.dart';
import '../map/map_focus_provider.dart';
import '../saved/saved_places_notifier.dart';

/// Place Detail v2
/// - 메모/태그: 자동 저장
/// - 폴더 이동: 저장 안 되어 있어도 시도하면 자동 저장 후 진행
/// - 즐겨찾기/방문 +1: 저장 안 되어 있어도 자동 저장 후 적용
/// - 공유: 가게명/카테고리/주소 + 카카오 장소 링크(가능하면)로 바로 공유
class PlaceDetailPage extends ConsumerStatefulWidget {
  const PlaceDetailPage({super.key, required this.place});
  final Place place;

  @override
  ConsumerState<PlaceDetailPage> createState() => _PlaceDetailPageState();
}

class _PlaceDetailPageState extends ConsumerState<PlaceDetailPage> {
  late final TextEditingController _memoCtrl;
  late final TextEditingController _tagInputCtrl;
  final Debouncer _autoSaveDebouncer = Debouncer(delay: const Duration(milliseconds: 650));

  List<String> _tags = <String>[];
  bool _didAutoSaveCreate = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final base = _readSavedOrWidgetPlace();
    _memoCtrl = TextEditingController(text: base.memo);
    _tagInputCtrl = TextEditingController();
    _tags = List<String>.from(base.tags);

    // 자동 저장: 메모 변경
    _memoCtrl.addListener(_scheduleAutoSave);
  }

  @override
  void dispose() {
    _memoCtrl.removeListener(_scheduleAutoSave);
    _memoCtrl.dispose();
    _tagInputCtrl.dispose();
    _autoSaveDebouncer.dispose();
    super.dispose();
  }

  Place _readSavedOrWidgetPlace() {
    final savedList = ref.read(savedPlacesProvider);
    final saved = savedList.firstWhereOrNull((p) => p.placeId == widget.place.placeId);
    return saved ?? widget.place;
  }

  bool _sameTags(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String _kakaoPlaceUrl(Place p) {
    // 카카오 로컬 API 결과의 id(placeId)가 숫자인 경우가 대부분
    if (RegExp(r'^\d+$').hasMatch(p.placeId)) {
      return 'https://place.map.kakao.com/${p.placeId}';
    }
    // placeId가 숫자가 아니면 구글 검색 링크로 폴백
    final q = Uri.encodeComponent('${p.name} ${p.address}'.trim());
    return 'https://www.google.com/maps/search/?api=1&query=$q';
  }

  String _buildShareText(Place p) {
    final url = _kakaoPlaceUrl(p);
    final category = p.category.trim().isEmpty ? '' : '🏷️ ${p.category}\n';
    final address = p.address.trim().isEmpty ? '' : '📌 ${p.address}\n';
    return '📍 ${p.name}\n'
        '$category'
        '$address'
        '\n🗺️ 지도: $url';
  }

  Future<void> _sharePlace(Place base) async {
    final text = _buildShareText(base);
    await Share.share(text, subject: base.name);
  }

  Place _draftOn(Place base) {
    final memo = _memoCtrl.text.trim();
    final tags = List<String>.from(_tags);
    return base.copyWith(memo: memo, tags: tags);
  }

  Future<Place> _ensureSaved({bool showSnack = true}) async {
    final notifier = ref.read(savedPlacesProvider.notifier);
    var base = notifier.findById(widget.place.placeId);
    if (base != null) return base;

    await notifier.upsert(_draftOn(widget.place));
    base = notifier.findById(widget.place.placeId);
    if (!mounted) return base ?? widget.place;

    if (showSnack && !_didAutoSaveCreate) {
      _didAutoSaveCreate = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장 목록에 추가했어요')),
      );
    }
    return base ?? widget.place;
  }

  void _scheduleAutoSave() {
    _autoSaveDebouncer.run(() async {
      if (!mounted) return;
      await _autoSaveMemoAndTags();
    });
  }

  Future<void> _autoSaveMemoAndTags() async {
    if (_saving) return;

    final notifier = ref.read(savedPlacesProvider.notifier);
    final currentSaved = notifier.findById(widget.place.placeId);
    final base = currentSaved ?? widget.place;
    final draft = _draftOn(base);

    // 변경 없으면 스킵
    if (draft.memo == base.memo && _sameTags(draft.tags, base.tags)) return;

    _saving = true;
    try {
      final savedBase = await _ensureSaved(showSnack: true);
      await notifier.upsert(_draftOn(savedBase));
    } finally {
      _saving = false;
    }
  }

  List<String> _parseTagsFromInput(String raw) {
    final parts = raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts;
  }

  void _addTagsFrom(String raw) {
    final incoming = _parseTagsFromInput(raw);
    if (incoming.isEmpty) return;
    final next = <String>{..._tags};
    next.addAll(incoming);
    final list = next.toList()..sort();
    setState(() {
      _tags = list;
      _tagInputCtrl.clear();
    });
    _scheduleAutoSave();
  }

  void _removeTag(String tag) {
    setState(() {
      _tags = _tags.where((t) => t != tag).toList();
    });
    _scheduleAutoSave();
  }

  Future<void> _toggleFavorite() async {
    final saved = await _ensureSaved(showSnack: true);
    await ref.read(savedPlacesProvider.notifier).upsert(
      saved.copyWith(isFavorite: !saved.isFavorite),
    );
  }

  Future<void> _markVisitedPlusOne() async {
    final saved = await _ensureSaved(showSnack: true);
    final now = DateTime.now();
    await ref.read(savedPlacesProvider.notifier).upsert(
      saved.copyWith(
        visited: true,
        visitedCount: saved.visitedCount + 1,
        lastVisitedAt: now,
      ),
    );
  }

  Future<void> _resetVisited() async {
    final notifier = ref.read(savedPlacesProvider.notifier);
    final base = notifier.findById(widget.place.placeId);
    if (base == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('방문 기록 초기화'),
        content: const Text('방문 횟수와 마지막 방문 시각을 초기화할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('초기화')),
        ],
      ),
    );
    if (ok != true) return;

    await notifier.upsert(
      base.copyWith(
        visited: false,
        visitedCount: 0,
        lastVisitedAt: null,
      ),
    );
  }

  Future<void> _removeSaved() async {
    final isSaved = ref.read(savedPlacesProvider.notifier).contains(widget.place.placeId);
    if (!isSaved) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('저장 해제'),
        content: const Text('저장 목록에서 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;

    final notifier = ref.read(savedPlacesProvider.notifier);
    final folderMap = ref.read(placeFolderMapProvider);
    final placeId = widget.place.placeId;

    final snap = ref.read(savedPlacesProvider).firstWhereOrNull((p) => p.placeId == placeId) ?? widget.place;
    final prevFolderId = folderMap[placeId];

    await notifier.remove(placeId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('저장 목록에서 삭제했어요'),
        action: SnackBarAction(
          label: '되돌리기',
          onPressed: () {
            notifier.restoreRemovedOne(place: snap, folderId: prevFolderId);
          },
        ),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // 저장본을 우선으로 사용 (외부에서 값이 변경되면 UI도 같이 반영)
    final saved = ref.watch(savedPlacesProvider).firstWhereOrNull(
          (p) => p.placeId == widget.place.placeId,
    );
    final base = saved ?? widget.place;
    final isSaved = saved != null;

    final folders = ref.watch(collectionFoldersProvider);
    final folderMap = ref.watch(placeFolderMapProvider);
    final currentFolderId = folderMap[widget.place.placeId];
    final currentFolderName = currentFolderId == null
        ? '미분류'
        : (folders
        .where((f) => f.id == currentFolderId)
        .map((f) => f.name)
        .cast<String?>()
        .firstOrNull ??
        '미분류');

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(base.name),
        actions: [
          IconButton(
            tooltip: base.isFavorite ? '즐겨찾기 해제' : '즐겨찾기',
            icon: Icon(base.isFavorite ? Icons.star : Icons.star_border),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            tooltip: '지도에서 보기',
            icon: const Icon(Icons.map_outlined),
            onPressed: () {
              ref.read(mapFocusProvider.notifier).focus(base);
              context.go('/map');
            },
          ),
          IconButton(
            tooltip: '공유',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _sharePlace(base),
          ),
          if (isSaved)
            IconButton(
              tooltip: '저장 해제',
              icon: const Icon(Icons.delete_outline),
              onPressed: _removeSaved,
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: Icon(isSaved ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined),
            label: Text(isSaved ? '저장 해제' : '저장하기'),
            onPressed: isSaved
                ? _removeSaved
                : () async {
              await _ensureSaved(showSnack: true);
            },
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        children: [
          Text(base.address),
          const SizedBox(height: 6),
          Text(base.category, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 18),

          // ✅ 폴더
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: const Text('폴더'),
            subtitle: Text(currentFolderName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await _ensureSaved(showSnack: true);
              final picked = await _pickFolderId(context);
              if (picked == null) return; // cancelled
              final folderIdToSet = picked == '__unfiled__' ? null : picked;
              final placeId = widget.place.placeId;
              final prev = ref.read(placeFolderMapProvider)[placeId];

              await ref.read(placeFolderMapProvider.notifier).setFolder(placeId, folderIdToSet);

              if (!context.mounted) return;
              final movedTo = folderIdToSet == null
                  ? '미분류'
                  : (folders.where((f) => f.id == folderIdToSet).map((f) => f.name).firstOrNull ?? '폴더');

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
              );            },
          ),

          const SizedBox(height: 12),

          // ✅ 방문
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('방문 ${base.visitedCount}회', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          base.lastVisitedAt == null
                              ? '아직 방문 기록이 없어요'
                              : '마지막 방문: ${base.lastVisitedAt!.toLocal().toString().substring(0, 16)}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        onPressed: _markVisitedPlusOne,
                        child: const Text('+1'),
                      ),
                      if (base.visitedCount > 0) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _resetVisited,
                          child: const Text('초기화'),
                        ),
                      ]
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ✅ 태그(칩)
          const Text('태그', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _tags)
                InputChip(
                  label: Text(t),
                  onDeleted: () => _removeTag(t),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
                child: TextField(
                  controller: _tagInputCtrl,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: '태그 추가',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: '추가',
                      icon: const Icon(Icons.add),
                      onPressed: () => _addTagsFrom(_tagInputCtrl.text),
                    ),
                  ),
                  onChanged: (v) {
                    // 콤마 입력 순간 자동 분리
                    if (v.contains(',')) {
                      _addTagsFrom(v);
                    }
                  },
                  onSubmitted: _addTagsFrom,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ✅ 메모
          TextField(
            controller: _memoCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '메모',
              hintText: '예) 콘센트 많음 / 조용함 / 주차 가능',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSaved ? '입력 내용은 자동 저장돼요.' : '입력하면 자동으로 저장 목록에 추가돼요.',
            style: const TextStyle(color: Colors.grey),
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
                        final newId =
                        await ref.read(collectionFoldersProvider.notifier).create(name);
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
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('만들기'),
            ),
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

extension _IterableFirstOrNullExt<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E e) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }

  E? get firstOrNull => isEmpty ? null : first;
}
