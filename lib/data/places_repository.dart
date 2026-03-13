import 'package:dio/dio.dart';
import '../domain/place.dart';
import 'kakao_places_api.dart';
import 'local_db_service.dart';

class PlacesRepository {
  PlacesRepository() : _api = KakaoPlacesApi(Dio());

  final KakaoPlacesApi _api;

  Future<KakaoKeywordSearchResult> search({
    required String query,
    required double lat,
    required double lng,
    int page = 1,
    int size = 15,
  }) {
    return _api.searchKeyword(
      query: query,
      lat: lat,
      lng: lng,
      page: page,
      size: size,
    );
  }

  // 저장 관련은 그대로 사용 가능 (Saved Provider에서 직접 LocalDbService 써도 됨)
  List<Place> getSaved() => LocalDbService.getAllSaved();
  bool isSaved(String placeId) => LocalDbService.isSaved(placeId);
}
