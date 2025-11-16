import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesService {
  static SharedPreferences? _instance;

  static SharedPreferences get instance {
    if (_instance == null) {
      throw Exception('SharedPreferences not initialized!');
    }
    return _instance!;
  }

  static Future<void> init() async {
    _instance = await SharedPreferences.getInstance();
  }
}
