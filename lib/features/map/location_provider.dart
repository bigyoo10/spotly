import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class AppLocation {
  final double lat;
  final double lng;
  const AppLocation(this.lat, this.lng);
}

final locationProvider = FutureProvider<AppLocation>((ref) async {
  // 1) 위치 서비스 켜져있는지
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception('위치 서비스가 꺼져 있어요. 설정에서 켜주세요.');
  }

  // 2) 권한 체크/요청
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied) {
    throw Exception('위치 권한이 거부됐어요.');
  }

  if (permission == LocationPermission.deniedForever) {
    throw Exception('위치 권한이 영구 거부됐어요. 설정에서 권한을 허용해주세요.');
  }

  // 3) 현재 위치 가져오기
  final pos = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );

  return AppLocation(pos.latitude, pos.longitude);
});
