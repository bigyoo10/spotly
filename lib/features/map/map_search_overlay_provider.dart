import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/place.dart';

/// 지도 위에 “임시로” 표시할 검색 결과(오버레이)
class MapSearchOverlay {
  final String query;
  final List<Place> places;

  const MapSearchOverlay({
    this.query = '',
    this.places = const [],
  });

  bool get hasData => places.isNotEmpty;
}

final mapSearchOverlayProvider =
NotifierProvider<MapSearchOverlayNotifier, MapSearchOverlay>(
  MapSearchOverlayNotifier.new,
);

class MapSearchOverlayNotifier extends Notifier<MapSearchOverlay> {
  @override
  MapSearchOverlay build() => const MapSearchOverlay();

  /// 검색 결과를 지도에 표시할 데이터로 저장
  void setResults({required String query, required List<Place> places}) {
    state = MapSearchOverlay(query: query, places: places);
  }

  /// 지도 오버레이(검색 마커) 제거
  void clear() {
    state = const MapSearchOverlay();
  }
}
