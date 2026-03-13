import '../../domain/place.dart';

/// (Legacy) google_maps_cluster_manager 기반 구현에서 사용하던 모델.
/// 내장 클러스터링으로 전환하면서 더 이상 필수는 아니지만,
/// 다른 파일에서 참조할 수 있어 호환용으로 남겨둡니다.
class PlaceClusterItem {
  final Place place;
  final bool isSaved;

  const PlaceClusterItem({required this.place, required this.isSaved});
}
