import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/place.dart';

/// Saved/Search/Detail 등 다른 화면에서 "지도에서 보기"를 눌렀을 때,
/// MapPage가 카메라를 해당 장소로 이동하고(줌인) 마커/리스트 선택을 맞추기 위한 요청.
class MapFocusRequest {
  final Place place;
  final bool clearOverlay; // true면 Search overlay를 지우고 Saved 리스트 모드로 전환
  final double? zoom;

  const MapFocusRequest({
    required this.place,
    this.clearOverlay = true,
    this.zoom,
  });
}

class MapFocusController extends StateNotifier<MapFocusRequest?> {
  MapFocusController() : super(null);

  void focus(Place place, {bool clearOverlay = true, double? zoom}) {
    state = MapFocusRequest(place: place, clearOverlay: clearOverlay, zoom: zoom);
  }

  void clear() => state = null;
}

final mapFocusProvider =
    StateNotifierProvider<MapFocusController, MapFocusRequest?>((ref) {
  return MapFocusController();
});
