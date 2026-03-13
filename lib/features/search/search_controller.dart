import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/debouncer.dart';
import '../../data/search_history_service.dart';
import '../../data/places_repository.dart';
import '../../domain/place.dart';
import '../map/location_provider.dart';
import '../map/map_search_overlay_provider.dart';

final placesRepoProvider = Provider((ref) => PlacesRepository());

class SearchState {
  final String query;
  final bool loading;        // 첫 페이지 로딩
  final bool loadingMore;    // 다음 페이지 로딩
  final String? error;
  final List<Place> results;
  final int page;
  final bool isEnd;          // true면 더 이상 다음 페이지 없음
  final List<String> recent; // 최근 검색어

  const SearchState({
    this.query = '',
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.results = const [],
    this.page = 1,
    this.isEnd = true,
    this.recent = const [],
  });

  SearchState copyWith({
    String? query,
    bool? loading,
    bool? loadingMore,
    String? error,
    List<Place>? results,
    int? page,
    bool? isEnd,
    List<String>? recent,
  }) =>
      SearchState(
        query: query ?? this.query,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: error,
        results: results ?? this.results,
        page: page ?? this.page,
        isEnd: isEnd ?? this.isEnd,
        recent: recent ?? this.recent,
      );
}

final searchControllerProvider =
StateNotifierProvider<SearchController, SearchState>((ref) {
  return SearchController(ref);
});

class SearchController extends StateNotifier<SearchState> {
  SearchController(this.ref)
      : super(SearchState(recent: SearchHistoryService.getAll()));

  final Ref ref;
  final _debouncer = Debouncer();

  /// 최근 검색어에 넣을 최소 글자 수(오타/삭제 중 저장되는 문제 방지)
  static const int _minHistoryLength = 2;

  void onQueryChanged(String q) {
    final trimmed = q.trim();
    state = state.copyWith(query: q);

    if (trimmed.isEmpty) {
      state = SearchState(recent: SearchHistoryService.getAll());
      ref.read(mapSearchOverlayProvider.notifier).clear();
      return;
    }

    // 입력 멈춘 뒤에만 첫 페이지 검색 실행
    // ✅ 타이핑 중 자동검색은 “최근검색어 저장”하지 않음
    _debouncer.run(() => _searchFirstPage(trimmed, saveToHistory: false));
  }

  /// 명시적으로 검색을 확정했을 때(키보드 검색, 최근검색어 탭 등)
  Future<void> submit(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;

    // 동일 쿼리로 이미 결과가 있고 로딩 중이 아니라면 네트워크 재호출 없이 히스토리만 커밋
    final hasResultsForSameQuery =
        state.query.trim() == trimmed && !state.loading && state.results.isNotEmpty;

    state = state.copyWith(query: trimmed, error: null);

    if (hasResultsForSameQuery) {
      await _commitHistory(trimmed);
      return;
    }

    await _searchFirstPage(trimmed, saveToHistory: true);
  }

  /// 결과를 탭해 상세로 들어가는 등, 현재 query를 “최근검색어”로만 커밋
  Future<void> commitCurrentQuery() async {
    final trimmed = state.query.trim();
    if (trimmed.isEmpty) return;
    await _commitHistory(trimmed);
  }

  Future<void> retry() async {
    final trimmed = state.query.trim();
    if (trimmed.isEmpty) return;
    await _searchFirstPage(trimmed, saveToHistory: true);
  }

  Future<void> _commitHistory(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < _minHistoryLength) return;
    await SearchHistoryService.add(trimmed);
    state = state.copyWith(recent: SearchHistoryService.getAll());
  }

  Future<void> _searchFirstPage(String query, {required bool saveToHistory}) async {
    final expectedQuery = query.trim();
    if (expectedQuery.isEmpty) return;
    // debounce 사이에 사용자가 쿼리를 바꿨으면 무시
    if (state.query.trim() != expectedQuery) return;

    try {
      // 첫 페이지 검색 시작: 결과/페이지 상태 리셋
      state = state.copyWith(
        loading: true,
        loadingMore: false,
        error: null,
        results: const [],
        page: 1,
        isEnd: true,
      );

      final loc = await ref.read(locationProvider.future);
      final repo = ref.read(placesRepoProvider);

      final res = await repo.search(
        query: expectedQuery,
        lat: loc.lat,
        lng: loc.lng,
        page: 1,
        size: 15,
      );

      // 네트워크 대기 중 쿼리가 바뀌면 결과를 덮어쓰지 않음
      if (state.query.trim() != expectedQuery) return;

      state = state.copyWith(
        loading: false,
        results: res.places,
        page: 1,
        isEnd: res.isEnd,
        error: null,
      );

      // ✅ 명시적으로 확정된 검색만 “최근 검색어” 저장
      if (saveToHistory) {
        await _commitHistory(expectedQuery);
      }

      // ✅ 지도 오버레이 갱신(1페이지 결과)
      ref.read(mapSearchOverlayProvider.notifier).setResults(
        query: expectedQuery,
        places: res.places,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  /// 최근 검색어 탭
  Future<void> selectRecent(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;
    await submit(trimmed);
  }

  Future<void> removeRecent(String q) async {
    await SearchHistoryService.remove(q);
    state = state.copyWith(recent: SearchHistoryService.getAll());
  }

  Future<void> clearRecents() async {
    await SearchHistoryService.clear();
    state = state.copyWith(recent: SearchHistoryService.getAll());
  }

  /// 무한 스크롤에서 호출: 다음 페이지 로드
  Future<void> loadMore() async {
    final query = state.query.trim();
    if (query.isEmpty) return;

    // 이미 로딩 중이거나, 더 이상 페이지가 없으면 중단
    if (state.loading || state.loadingMore || state.isEnd) return;

    try {
      state = state.copyWith(loadingMore: true, error: null);

      final nextPage = state.page + 1;

      final loc = await ref.read(locationProvider.future);
      final repo = ref.read(placesRepoProvider);

      final res = await repo.search(
        query: query,
        lat: loc.lat,
        lng: loc.lng,
        page: nextPage,
        size: 15,
      );

      final merged = [...state.results, ...res.places];

      state = state.copyWith(
        loadingMore: false,
        results: merged,
        page: nextPage,
        isEnd: res.isEnd,
      );

      // ✅ 지도 오버레이도 “누적 결과”로 갱신
      ref.read(mapSearchOverlayProvider.notifier).setResults(
        query: query,
        places: merged,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e.toString());
    }
  }

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }
}
