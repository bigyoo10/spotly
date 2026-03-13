import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/debouncer.dart';
import '../../domain/place.dart';
import '../collections/collection_folders_notifier.dart';
import '../collections/place_folder_notifier.dart';
import '../saved/saved_places_notifier.dart';
import '../search/search_controller.dart';
import 'location_provider.dart';
import 'map_search_overlay_provider.dart';
import 'map_focus_provider.dart';

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  GoogleMapController? _controller;
  late final ProviderSubscription<MapSearchOverlay> _overlaySub;
  late final ProviderSubscription<MapFocusRequest?> _focusSub;

  Place? _pendingFocusPlace;
  double _pendingFocusZoom = 16.0;
  bool _pendingFocusClearOverlay = true;

  // ✅ google_maps_flutter 내장 클러스터링
  static const ClusterManagerId _clusterManagerId = ClusterManagerId('spotly_cluster');
  late final ClusterManager _clusterManager;


  // ✅ 하단 리스트 바텀시트 (지도 ↔ 리스트 동기화 v1)
  final DraggableScrollableController _listSheetController = DraggableScrollableController();
  ScrollController? _listScrollController;
  double _listSheetExtent = 0.18; // 화면 높이 대비 비율
  static const double _listItemExtent = 72.0;

  // ✅ 지도 인터랙션 (Search this area)
  CameraPosition? _cameraPosition;
  LatLng? _lastSearchCenter;
  double? _lastSearchZoom;
  bool _showSearchThisArea = false;
  bool _searchingThisArea = false;

  // ✅ 선택된 마커 하이라이트
  String? _selectedPlaceId;


  // ✅ 터치 매끄럽게: 바텀시트 터치 중에는 지도 제스처 비활성화
  bool _sheetPointerDown = false;

  // ✅ 마커 탭 UX: 같은 마커 빠른 2번째 탭이면 상세 시트 열기
  String? _lastMarkerTapId;
  DateTime? _lastMarkerTapAt;


  final Debouncer _areaSearchDebouncer = Debouncer(delay: const Duration(milliseconds: 250));

  /// 바텀시트 중복 방지
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();

    _clusterManager = ClusterManager(
      clusterManagerId: _clusterManagerId,
      onClusterTap: _onClusterTap,
    );

    // ✅ initState에서는 listenManual 사용
    _overlaySub = ref.listenManual<MapSearchOverlay>(
      mapSearchOverlayProvider,
      (prev, next) {
        if (next.places.isNotEmpty) {
          // 새 검색 결과가 들어오면 “재검색 버튼” 상태 초기화
          _lastSearchCenter = null;
          _lastSearchZoom = null;
          if (mounted) {
            setState(() => _showSearchThisArea = false);
          }
          _fitToPlaces(next.places);
        }
      },
    );

    _focusSub = ref.listenManual<MapFocusRequest?>(
      mapFocusProvider,
      (prev, next) {
        if (next == null) return;
        _handleMapFocus(next);
        // consume
        ref.read(mapFocusProvider.notifier).clear();
      },
    );
  }

  @override
  void dispose() {
    _overlaySub.close();
    _focusSub.close();
    _areaSearchDebouncer.dispose();
    _controller?.dispose();
    super.dispose();
  }


  void _handleMapFocus(MapFocusRequest req) {
    final place = req.place;

    // 옵션 저장
    _pendingFocusZoom = req.zoom ?? 16.0;
    _pendingFocusClearOverlay = req.clearOverlay;

    if (req.clearOverlay) {
      // 검색 오버레이를 지우고 Saved 중심 모드로 전환
      ref.read(mapSearchOverlayProvider.notifier).clear();
      _lastSearchCenter = null;
      _lastSearchZoom = null;
      if (mounted) {
        setState(() => _showSearchThisArea = false);
      } else {
        _showSearchThisArea = false;
      }
    }

    // 선택/리스트 동기화는 먼저 해두기
    _setSelectedPlace(place.placeId);
    _expandListSheet(targetExtent: 0.45);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollListToPlace(place.placeId);
    });

    // 지도 컨트롤러가 아직 없으면 pending으로 저장 (onMapCreated에서 처리)
    if (_controller == null) {
      _pendingFocusPlace = place;
      return;
    }

    _focusToPlace(place, zoom: _pendingFocusZoom);
  }

  Future<void> _focusToPlace(Place place, {double zoom = 16.0}) async {
    final c = _controller;
    if (c == null) return;

    final target = LatLng(place.lat, place.lng);
    try {
      await c.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: zoom),
        ),
      );
    } catch (_) {
      // 일부 기기에서 animateCamera 예외가 날 수 있어 보호
      await c.animateCamera(CameraUpdate.newLatLng(target));
    }

    // 포커스 후 UX 보정
    _setSelectedPlace(place.placeId);
    _expandListSheet(targetExtent: 0.45);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollListToPlace(place.placeId);
    });
  }

  void _setSelectedPlace(String? placeId) {
    if (_selectedPlaceId == placeId) return;
    setState(() => _selectedPlaceId = placeId);
  }

  void _setSheetPointerDown(bool v) {
    if (_sheetPointerDown == v) return;
    setState(() => _sheetPointerDown = v);
  }


  BitmapDescriptor _placeMarkerIcon({required bool isSaved, required bool isSelected}) {
    final hue = isSelected
        ? BitmapDescriptor.hueOrange
        : (isSaved ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueRed);
    return BitmapDescriptor.defaultMarkerWithHue(hue);
  }

  Set<Marker> _buildPlaceMarkers({
    required List<Place> savedPlaces,
    required MapSearchOverlay overlay,
  }) {
    final savedIdSet = savedPlaces.map((e) => e.placeId).toSet();

    final markers = <Marker>{};

    // Saved markers
    for (final p in savedPlaces) {
      markers.add(
        Marker(
          clusterManagerId: _clusterManagerId,
          markerId: MarkerId('saved_${p.placeId}'),
          position: LatLng(p.lat, p.lng),
          icon: _placeMarkerIcon(isSaved: true, isSelected: _selectedPlaceId == p.placeId),
          infoWindow: InfoWindow.noText,
          consumeTapEvents: true,
          onTap: () => _onMarkerSelected(p),
        ),
      );
    }

    // Search overlay markers (exclude already saved)
    for (final p in overlay.places.where((p) => !savedIdSet.contains(p.placeId))) {
      markers.add(
        Marker(
          clusterManagerId: _clusterManagerId,
          markerId: MarkerId('search_${p.placeId}'),
          position: LatLng(p.lat, p.lng),
          icon: _placeMarkerIcon(isSaved: false, isSelected: _selectedPlaceId == p.placeId),
          infoWindow: InfoWindow.noText,
          consumeTapEvents: true,
          onTap: () => _onMarkerSelected(p),
        ),
      );
    }

    return markers;
  }

  void _onClusterTap(Cluster cluster) async {
    final c = _controller;
    if (c == null) return;

    final currentZoom = _cameraPosition?.zoom ?? 14.0;
    final nextZoom = (currentZoom + 2).clamp(0, 20).toDouble();

    await c.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: cluster.position, zoom: nextZoom),
      ),
    );
  }

  Future<void> _openPlaceSheet(Place place) async {
    if (_sheetOpen) return;
    _sheetOpen = true;

    _setSelectedPlace(place.placeId);

    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) {
          return Consumer(
            builder: (ctx, ref, _) {
              final savedList = ref.watch(savedPlacesProvider);
              final saved = savedList.where((p) => p.placeId == place.placeId).toList();
              final savedPlace = saved.isEmpty ? null : saved.first;
              final isSaved = savedPlace != null;
              final base = savedPlace ?? place;

              final folders = ref.watch(collectionFoldersProvider);
              final folderMap = ref.watch(placeFolderMapProvider);
              final folderId = folderMap[base.placeId];
              final folderName = folderId == null
                  ? '미분류'
                  : (folders.where((f) => f.id == folderId).map((f) => f.name).cast<String?>().firstOrNull ??
                      '미분류');

              final categoryShort = base.category.trim().isEmpty
                  ? ''
                  : (base.category.contains('>') ? base.category.split('>').last.trim() : base.category.trim());

              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              base.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: '닫기',
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        base.address,
                        style: const TextStyle(color: Colors.grey),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (categoryShort.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            categoryShort,
                            style: const TextStyle(color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (isSaved)
                            const Chip(
                              label: Text('저장됨'),
                              avatar: Icon(Icons.bookmark, size: 18),
                            )
                          else
                            const Chip(
                              label: Text('검색 결과'),
                              avatar: Icon(Icons.place_outlined, size: 18),
                            ),
                          Chip(label: Text('📁 $folderName')),
                          if (isSaved && base.visited)
                            Chip(
                              label: Text('방문 ${base.visitedCount > 0 ? base.visitedCount : ''}'.trim()),
                              avatar: const Icon(Icons.check_circle_outline, size: 18),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              icon: Icon(isSaved ? Icons.bookmark_remove : Icons.bookmark_add),
                              label: Text(isSaved ? '저장 해제' : '저장하기'),
                              onPressed: () async {
                                if (isSaved) {
                                  await ref.read(savedPlacesProvider.notifier).remove(base.placeId);
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text('저장에서 제거했어요'),
                                      duration: Duration(milliseconds: 900),
                                    ),
                                  );
                                  return;
                                }

                                final picked = await _pickFolderId(ctx);
                                if (picked == null) return;
                                final folderIdToSet = picked == '__unfiled__' ? null : picked;

                                await ref.read(savedPlacesProvider.notifier).upsert(base);
                                await ref.read(placeFolderMapProvider.notifier).setFolder(base.placeId, folderIdToSet);

                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(folderIdToSet == null ? '미분류로 저장했어요' : '폴더에 저장했어요'),
                                    duration: const Duration(milliseconds: 900),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.folder_outlined),
                              label: const Text('폴더'),
                              onPressed: !isSaved
                                  ? null
                                  : () async {
                                      final picked = await _pickFolderId(ctx);
                                      if (picked == null) return;
                                      final folderIdToSet = picked == '__unfiled__' ? null : picked;
                                      await ref.read(placeFolderMapProvider.notifier).setFolder(base.placeId, folderIdToSet);
                                      if (!ctx.mounted) return;
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(
                                          content: Text('폴더를 변경했어요'),
                                          duration: Duration(milliseconds: 900),
                                        ),
                                      );
                                    },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('상세 보기'),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            context.push('/place', extra: base);
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      _sheetOpen = false;
    }
  }

  Future<void> _fitToPlaces(List<Place> places) async {
    final c = _controller;
    if (c == null || places.isEmpty) return;

    if (places.length == 1) {
      final p = places.first;
      await c.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: LatLng(p.lat, p.lng), zoom: 15),
        ),
      );
      return;
    }

    double minLat = places.first.lat, maxLat = places.first.lat;
    double minLng = places.first.lng, maxLng = places.first.lng;

    for (final p in places) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    await c.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  void _handleCameraIdleForAreaSearch() {
    final overlay = ref.read(mapSearchOverlayProvider);
    if (!overlay.hasData) {
      if (_showSearchThisArea && mounted) setState(() => _showSearchThisArea = false);
      return;
    }

    final pos = _cameraPosition;
    if (pos == null) return;

    if (_lastSearchCenter == null || _lastSearchZoom == null) {
      _lastSearchCenter = pos.target;
      _lastSearchZoom = pos.zoom;
      if (_showSearchThisArea && mounted) setState(() => _showSearchThisArea = false);
      return;
    }

    final movedMeters = _distanceMeters(_lastSearchCenter!, pos.target);
    final zoomDelta = (pos.zoom - _lastSearchZoom!).abs();

    final shouldShow = movedMeters >= 800 || zoomDelta >= 0.8;

    if (shouldShow != _showSearchThisArea && mounted) {
      setState(() => _showSearchThisArea = shouldShow);
    }
  }

  Future<void> _searchInThisArea() async {
    final overlay = ref.read(mapSearchOverlayProvider);
    if (!overlay.hasData) return;

    final query = overlay.query.trim();
    if (query.isEmpty) return;

    final pos = _cameraPosition;
    if (pos == null) return;

    if (mounted) {
      setState(() => _searchingThisArea = true);
    } else {
      _searchingThisArea = true;
    }

    try {
      final repo = ref.read(placesRepoProvider);
      final res = await repo.search(
        query: query,
        lat: pos.target.latitude,
        lng: pos.target.longitude,
        page: 1,
        size: 15,
      );

      ref.read(mapSearchOverlayProvider.notifier).setResults(
        query: query,
        places: res.places,
      );

      _lastSearchCenter = pos.target;
      _lastSearchZoom = pos.zoom;

      if (mounted) {
        setState(() => _showSearchThisArea = false);
      } else {
        _showSearchThisArea = false;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('재검색 실패: $e'),
            duration: const Duration(milliseconds: 1200),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _searchingThisArea = false);
      } else {
        _searchingThisArea = false;
      }
    }
  }

  static double _distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0; // meters
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLon = (b.longitude - a.longitude) * math.pi / 180.0;

    final sinDlat = math.sin(dLat / 2);
    final sinDlon = math.sin(dLon / 2);

    final h = sinDlat * sinDlat + math.cos(lat1) * math.cos(lat2) * sinDlon * sinDlon;
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return earthRadius * c;
  }


// ====== 지도 ↔ 리스트 동기화 v1 ======

void _onMarkerSelected(Place place) {
  final now = DateTime.now();

  final isSecondTapSame =
      _lastMarkerTapId == place.placeId &&
      _lastMarkerTapAt != null &&
      now.difference(_lastMarkerTapAt!).inMilliseconds <= 650;

  _lastMarkerTapId = place.placeId;
  _lastMarkerTapAt = now;

  // 같은 마커를 빠르게 두 번 탭하면 상세 시트를 바로 열기
  if (isSecondTapSame) {
    _openPlaceSheet(place);
    return;
  }

  _setSelectedPlace(place.placeId);
  _expandListSheet();

  // 시트가 확장된 다음에 스크롤이 안정적으로 동작하도록 다음 프레임에 실행
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _scrollListToPlace(place.placeId);
  });
}

Future<void> _moveCameraToPlace(Place place) async {
  final c = _controller;
  if (c == null) return;

  final target = LatLng(place.lat, place.lng);
  await c.animateCamera(CameraUpdate.newLatLng(target));
}

void _expandListSheet({double targetExtent = 0.45}) {
  if (!_listSheetController.isAttached) return;

  // min/max 범위 내로 보정
  final clamped = targetExtent.clamp(0.12, 0.75).toDouble();
  _listSheetController.animateTo(
    clamped,
    duration: const Duration(milliseconds: 240),
    curve: Curves.easeOut,
  );
}

void _scrollListToPlace(String placeId) {
  final sc = _listScrollController;
  if (sc == null || !sc.hasClients) return;

  final savedPlaces = ref.read(savedPlacesProvider);
  final overlay = ref.read(mapSearchOverlayProvider);

  final rows = _buildVisibleRows(savedPlaces: savedPlaces, overlay: overlay);
  final idx = rows.indexWhere((r) => r.place.placeId == placeId);
  if (idx < 0) return;

  final offset = (idx * _listItemExtent).toDouble();
  sc.animateTo(
    offset,
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOut,
  );
}

List<_VisiblePlaceRow> _buildVisibleRows({
  required List<Place> savedPlaces,
  required MapSearchOverlay overlay,
}) {
  final rows = <_VisiblePlaceRow>[];

  // Saved 먼저
  final savedMap = <String, Place>{for (final p in savedPlaces) p.placeId: p};
  for (final p in savedPlaces) {
    rows.add(_VisiblePlaceRow(place: p, isSaved: true));
  }

  // 검색 결과(저장된 것은 중복 제거)
  if (overlay.hasData) {
    for (final p in overlay.places) {
      if (savedMap.containsKey(p.placeId)) continue;
      rows.add(_VisiblePlaceRow(place: p, isSaved: false));
    }
  }

  return rows;
}

Widget _buildBottomListSheet({
  required List<Place> savedPlaces,
  required MapSearchOverlay overlay,
}) {
  final rows = _buildVisibleRows(savedPlaces: savedPlaces, overlay: overlay);
  final savedCount = savedPlaces.length;
  final searchCount = overlay.hasData
      ? overlay.places.where((p) => !savedPlaces.any((s) => s.placeId == p.placeId)).length
      : 0;

  final title = overlay.hasData ? '표시 중: 저장 $savedCount · 검색 $searchCount' : '저장 $savedCount';

  return NotificationListener<DraggableScrollableNotification>(
    onNotification: (n) {
      final next = n.extent;
      if ((next - _listSheetExtent).abs() > 0.004) {
        if (mounted) {
          setState(() => _listSheetExtent = next);
        } else {
          _listSheetExtent = next;
        }
      }
      return false;
    },
    child: DraggableScrollableSheet(
      controller: _listSheetController,
      minChildSize: 0.12,
      initialChildSize: 0.18,
      maxChildSize: 0.75,
      builder: (context, scrollController) {
        _listScrollController = scrollController;
        final cs = Theme.of(context).colorScheme;

        // ✅ Listener는 "시트 실제 영역"에서만 동작해야 지도 터치를 가로채지 않음.
        return Listener(
          behavior: HitTestBehavior.deferToChild,
          onPointerDown: (_) => _setSheetPointerDown(true),
          onPointerUp: (_) => _setSheetPointerDown(false),
          onPointerCancel: (_) => _setSheetPointerDown(false),
          child: Material(
            elevation: 12,
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_selectedPlaceId != null)
                        IconButton(
                          tooltip: '선택 해제',
                          onPressed: () => _setSelectedPlace(null),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (rows.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        overlay.hasData ? '표시할 결과가 없어요' : '저장된 장소가 없어요',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      dragStartBehavior: DragStartBehavior.down,
                      itemExtent: _listItemExtent,
                      itemCount: rows.length,
                      itemBuilder: (ctx, i) {
                        final r = rows[i];
                        final p = r.place;
                        final selected = p.placeId == _selectedPlaceId;

                        final leadingIcon = r.isSaved ? Icons.bookmark : Icons.place_outlined;

                        return ListTile(
                          selected: selected,
                          leading: Icon(
                            leadingIcon,
                            color: selected ? cs.tertiary : (r.isSaved ? cs.primary : cs.error),
                          ),
                          title: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            p.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: '상세',
                            icon: const Icon(Icons.more_horiz),
                            onPressed: () => _openPlaceSheet(p),
                          ),
                          onTap: () async {
                            _setSelectedPlace(p.placeId);
                            _expandListSheet();
                            await _moveCameraToPlace(p);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(locationProvider);
    final savedPlaces = ref.watch(savedPlacesProvider);
    final overlay = ref.watch(mapSearchOverlayProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '검색으로',
            onPressed: () => context.go('/search'),
          ),
          if (overlay.hasData)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: '검색 마커 지우기',
              onPressed: () {
                ref.read(mapSearchOverlayProvider.notifier).clear();
                _lastSearchCenter = null;
                _lastSearchZoom = null;
                if (mounted) setState(() => _showSearchThisArea = false);
              },
            ),
        ],
      ),
      body: loc.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('위치 오류: $e')),
        data: (l) {
          final markers = _buildPlaceMarkers(savedPlaces: savedPlaces, overlay: overlay);

          final screenH = MediaQuery.sizeOf(context).height;
          final mapPaddingBottom = (screenH * _listSheetExtent).clamp(0.0, screenH);

          return Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(l.lat, l.lng),
                  zoom: 14,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                scrollGesturesEnabled: !_sheetPointerDown,
                zoomGesturesEnabled: !_sheetPointerDown,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                padding: EdgeInsets.only(bottom: mapPaddingBottom),
                markers: markers,
                clusterManagers: <ClusterManager>{_clusterManager},
                onTap: (_) => _setSelectedPlace(null),
                onCameraMove: (pos) {
                  _cameraPosition = pos;
                },
                onCameraIdle: () {
                  _areaSearchDebouncer.run(_handleCameraIdleForAreaSearch);
                },
                onMapCreated: (c) {
                  _controller = c;
                  _cameraPosition ??= CameraPosition(target: LatLng(l.lat, l.lng), zoom: 14);

                  // ✅ 이미 검색 결과가 있으면 처음부터 그 결과로 카메라 맞추기
                  final currentOverlay = ref.read(mapSearchOverlayProvider);
                  if (currentOverlay.places.isNotEmpty) {
                    _fitToPlaces(currentOverlay.places);
                  }

                  // ✅ Saved 등에서 "지도에서 보기" 요청이 들어온 경우
                  final pending = _pendingFocusPlace;
                  if (pending != null) {
                    _pendingFocusPlace = null;
                    _focusToPlace(pending, zoom: _pendingFocusZoom);
                  }
                },
              ),

              // ✅ 상단에 “현재 검색 오버레이 상태” 표시
              if (overlay.hasData)
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '“${overlay.query}” 결과 ${overlay.places.length}개 표시 중',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              ref.read(mapSearchOverlayProvider.notifier).clear();
                              _lastSearchCenter = null;
                              _lastSearchZoom = null;
                              if (mounted) setState(() => _showSearchThisArea = false);
                            },
                            child: const Text('지우기'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ✅ “이 지역에서 재검색” 버튼
              if (overlay.hasData && _showSearchThisArea)
                Positioned(
                  top: 72,
                  left: 12,
                  right: 12,
                  child: Center(
                    child: FilledButton.icon(
                      onPressed: _searchingThisArea ? null : _searchInThisArea,
                      icon: _searchingThisArea
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('이 지역에서 재검색'),
                    ),
                  ),
                ),
            
              // ✅ 하단 리스트 바텀시트
              RepaintBoundary(

                child: _buildBottomListSheet(savedPlaces: savedPlaces, overlay: overlay),

              ),
            ],
          );
        },
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


class _VisiblePlaceRow {
  final Place place;
  final bool isSaved;

  const _VisiblePlaceRow({
    required this.place,
    required this.isSaved,
  });
}


extension _FirstOrNullExt<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}