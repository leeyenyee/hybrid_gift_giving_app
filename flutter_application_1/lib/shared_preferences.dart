import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferenceHelper {
  static const String _eventsKey = 'calendar_events';

  // Save events to shared preferences
  static Future<void> saveEvents(Map<DateTime, List<String>> events) async {
    final prefs = await SharedPreferences.getInstance();
  
    final Map<String, List<String>> stringEvents = events.map(
      (key, value) => MapEntry(key.toIso8601String(), value),
    );
    final String jsonString = json.encode(stringEvents);
    await prefs.setString(_eventsKey, jsonString);
  }

  // Retrieve events from shared preferences
  static Future<Map<DateTime, List<String>>> loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString(_eventsKey);

    if (jsonString == null) {
      return {}; 
    }

    final Map<String, dynamic> decodedEvents = json.decode(jsonString);
    final Map<DateTime, List<String>> events = decodedEvents.map(
      (key, value) => MapEntry(DateTime.parse(key), List<String>.from(value)),
    );

    return events;
  }
}
