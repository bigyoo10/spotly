import 'package:dio/dio.dart';
import '../core/env.dart';
import '../domain/place.dart';

/// 카카오 키워드 검색 결과(페이징용)
class KakaoKeywordSearchResult {
  final List<Place> places;
  final bool isEnd; // true면 더 이상 다음 페이지 없음

  const KakaoKeywordSearchResult({
    required this.places,
    required this.isEnd,
  });
}

class KakaoPlacesApi {
  KakaoPlacesApi(this._dio);

  final Dio _dio;

  Future<KakaoKeywordSearchResult> searchKeyword({
    required String query,
    required double lat,
    required double lng,
    int page = 1,
    int size = 15,
  }) async {
    final res = await _dio.get(
      'https://dapi.kakao.com/v2/local/search/keyword.json',
      queryParameters: {
        'query': query,
        'x': lng, // Kakao는 x=경도, y=위도
        'y': lat,
        'page': page,
        'size': size,
      },
      options: Options(
        headers: {'Authorization': 'KakaoAK ${Env.kakaoKey}'},
      ),
    );

    final meta = (res.data['meta'] as Map).cast<String, dynamic>();
    final isEnd = (meta['is_end'] as bool?) ?? true;

    final docs = (res.data['documents'] as List).cast<Map<String, dynamic>>();

    final places = docs.map((d) {
      final id = (d['id'] ?? '') as String;
      final name = (d['place_name'] ?? '') as String;

      final road = (d['road_address_name'] as String?)?.trim() ?? '';
      final addr = road.isNotEmpty ? road : ((d['address_name'] ?? '') as String);

      final lat = double.tryParse((d['y'] ?? '0').toString()) ?? 0;
      final lng = double.tryParse((d['x'] ?? '0').toString()) ?? 0;

      return Place(
        placeId: id,
        name: name,
        address: addr,
        lat: lat,
        lng: lng,
        category: (d['category_name'] ?? '') as String,
      );
    }).toList();

    return KakaoKeywordSearchResult(places: places, isEnd: isEnd);
  }
}
