import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'app/router.dart';
import 'data/collections_db_service.dart';
import 'data/local_db_service.dart';
import 'data/search_history_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 항상 세로 고정
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // ✅ Android에서 지도 위 오버레이(바텀시트/버튼) 터치가 씹히는 경우가 있어
  //    Hybrid Composition 모드로 강제 (필요 시만 사용 권장)
  final GoogleMapsFlutterPlatform mapsImplementation =
      GoogleMapsFlutterPlatform.instance;
  if (mapsImplementation is GoogleMapsFlutterAndroid) {
    mapsImplementation.useAndroidViewSurface = true;
  }

  await dotenv.load(fileName: '.env');
  await LocalDbService.init();
  await CollectionsDbService.init();
  await SearchHistoryService.init();

  // ✅ 키 로드 확인(디버그용)
  debugPrint("kakao key loaded: ${dotenv.env['KAKAO_REST_API_KEY']?.isNotEmpty}");

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(useMaterial3: true),
    );
  }
}
