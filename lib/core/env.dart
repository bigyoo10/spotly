import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  static String get kakaoKey => dotenv.env['KAKAO_REST_API_KEY'] ?? '';
  static String get googleMapsKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
}
