import 'package:google_maps_flutter/google_maps_flutter.dart';

/// (Legacy) Spotly에서 클러스터 아이콘을 커스텀하던 헬퍼.
/// 현재는 google_maps_flutter 내장 클러스터링을 사용하므로,
/// 단일 마커 아이콘 선택 용도로만 남겨둡니다.
class MarkerClusterHelper {
  static BitmapDescriptor iconForPlace({
    required bool isSaved,
    required bool isSelected,
  }) {
    final hue = isSelected
        ? BitmapDescriptor.hueOrange
        : (isSaved ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueRed);
    return BitmapDescriptor.defaultMarkerWithHue(hue);
  }
}
