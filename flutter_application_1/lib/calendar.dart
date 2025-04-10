import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:device_calendar/device_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'gift_recommendation.dart';
import 'chat_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:fuzzy/fuzzy.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();
  DateTime _selectedDate = DateTime.now();
  final Map<DateTime, List<String>> _events = {};
  late SharedPreferences _prefs;
  bool _isDisposed = false;

  // Firebase Messaging and Notifications
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // List of special occasions
  final Map<String, List<String>> _occasionSynonyms = {
    "Birthday": ["bday", "b-day", "birthday", "birth day", "BD"],
    "Anniversary": ["anniversary", "anniv", "anniv.","Anniversary"],
    "Baby & Expecting": ["baby", "expecting", "baby shower"],
    "Father's Day": ["fathers day", "father day", "dad day", "Father's Day"],
    "Mother's Day": ["mothers day", "mother day", "mom day","Mother's Day"],
    "Christmas": ["christmas", "xmas"],
    "Friendship Day": ["friendship day", "friend day"],
    "New Year": ["new year", "newyear", "new years"],
    "Graduarion": ["graduation", "grad"],
    "Wedding": ["wedding", "marriage", "wed"],
    "Halloween": ["halloween", "hallowe'en", "halloween"],
    "Thanksgiving": ["thanksgiving", "thanks giving", "thanksgiving"],
    "Easter": ["easter", "easter sunday", "easter day"],
    "Black Friday": ["black friday", "blackfriday"],
    "Valentine's Day": ["valentine's day", "valentine day", "vday", "valentine"],
  };

  @override
  void dispose() {
    _isDisposed = true; // Set flag when widget is disposed
    super.dispose();
  }

  // Helper method to safely call setState
  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) {
      setState(fn);
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeSharedPreferences();
    _fetchCalendarEvents();
    _initializeFirebaseMessaging();
    _initializeNotifications();
  }

  // Initialize Firebase Messaging
  void _initializeFirebaseMessaging() async {
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Received a message while in the foreground!');
      print('Message data: ${message.data}');

      if (message.notification != null) {
        print('Message also contained a notification: ${message.notification}');
        _showNotification(
          message.notification!.title!,
          message.notification!.body!,
        );
      }
    });

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
  static Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    print('Handling a background message: ${message.messageId}');
    if (message.notification != null) {
      print('Notification received in background: ${message.notification}');
    }
  }

  void _initializeNotifications() {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    _flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _showNotification(String title, String body) {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'your_channel_id',
      'your_channel_name',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    _flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  String _getCurrentUserID() {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return '';
    }
    return user.uid;
  }

  Future<void> _initializeSharedPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    final userID = _getCurrentUserID(); 
    _loadSavedEvents(userID); 
  }

  void _loadSavedEvents(String userID) {
    final savedEvents = _prefs.getString('events_$userID'); // Use user-specific key
    if (savedEvents != null) {
      final Map<String, dynamic> decodedEvents = jsonDecode(savedEvents);
      decodedEvents.forEach((key, value) {
        final eventDate = DateTime.parse(key);
        _events[eventDate] = List<String>.from(value);
      });
      _safeSetState(() {}); 
    }
  }

  void _saveEvents(String userID) {
    final encodedEvents = _events.map((key, value) {
      return MapEntry(key.toIso8601String(), value);
    });
    _prefs.setString('events_$userID', jsonEncode(encodedEvents)); // Use user-specific key
  }

  // Fetch events from the device calendar
  Future<void> _fetchCalendarEvents() async {
    _events.clear();

    // Fetch events from the device calendar
    var permissionsGranted = await _deviceCalendarPlugin.hasPermissions();
    if (!permissionsGranted.isSuccess || !permissionsGranted.data!) {
      var permissions = await _deviceCalendarPlugin.requestPermissions();
      if (!permissions.isSuccess || !permissions.data!) {
        return;
      }
    }

    var calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
    if (!calendarsResult.isSuccess || calendarsResult.data == null) {
      return;
    }

    for (var calendar in calendarsResult.data!) {
      var eventsResult = await _deviceCalendarPlugin.retrieveEvents(
        calendar.id!,
        RetrieveEventsParams(
          startDate: DateTime.now().subtract(const Duration(days: 30)),
          endDate: DateTime.now().add(const Duration(days: 365)),
        ),
      );

      if (eventsResult.isSuccess && eventsResult.data != null) {
        for (var event in eventsResult.data!) {
          var eventDate = DateTime(event.start!.year, event.start!.month, event.start!.day);
          if (!_events.containsKey(eventDate)) {
            _events[eventDate] = [];
          }

          // Check if the event already exists in the list for this date
          if (!_events[eventDate]!.contains(event.title!)) {
            _events[eventDate]!.add(event.title!);
          }
        }
      }
    }

    // Save fetched events for the current user
    _saveEvents(_getCurrentUserID());
    _safeSetState(() {}); // Refresh UI
  }

  // Schedule a notification for a special event
  Future<void> _scheduleNotification(String eventTitle, DateTime eventDate) async {
    final token = await _firebaseMessaging.getToken();

    if (token != null) {
      await sendNotification(
        token,
        'Event Reminder',
        '$eventTitle is coming soon!',
      );
    } else {
      print('FCM token is null');
    }
  }

  Future<void> sendNotification(String token, String title, String body) async {
    // Use the ngrok URL here
    final String backendUrl = 'https://bb4b-37-203-155-164.ngrok-free.app/send-notification';
    final Map<String, dynamic> requestBody = {
      'token': token,
      'title': title,
      'body': body,
    };

    try {
      final response = await http.post(
        Uri.parse(backendUrl),
        headers: <String, String>{
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        print('Notification sent successfully');
        print('Response: ${response.body}');
      } else {
        print('Failed to send notification: ${response.statusCode}');
        print('Response: ${response.body}');
      }
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  void _addEvent(String eventTitle) {
    final eventDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    if (!_events.containsKey(eventDate)) {
      _events[eventDate] = [];
    }
    _events[eventDate]!.add(eventTitle);
    _saveEvents(_getCurrentUserID()); 

    // Schedule a notification if the event is a special occasion
    if (_isSpecialOccasion(eventTitle)) {
      _scheduleNotification(eventTitle, eventDate);
    }

    _safeSetState(() {}); 
  }

  bool _isSpecialOccasion(String event) {
    // Check for exact matches in synonyms
    for (var occasion in _occasionSynonyms.keys) {
      final synonyms = _occasionSynonyms[occasion]!;
      for (var synonym in synonyms) {
        if (event.toLowerCase().contains(synonym.toLowerCase())) {
          return true;
        }
      }
    }

    // Use fuzzy matching for variations
    final fuzzy = Fuzzy(_occasionSynonyms.keys.toList());
    final result = fuzzy.search(event);
    return result.isNotEmpty && result[0].score > 50; // threshold score for fuzzy match
  }

  bool _hasSpecialOccasion(DateTime day) {
    final events = _events[DateTime(day.year, day.month, day.day)] ?? [];
    for (var event in events) {
      if (_isSpecialOccasion(event)) {
        return true;
      }
    }
    return false;
  }

  String? _getOccasionKeyword(String event) {
    for (var occasion in _occasionSynonyms.keys) {
      final synonyms = _occasionSynonyms[occasion]!;
      for (var synonym in synonyms) {
        if (event.toLowerCase().contains(synonym.toLowerCase())) {
          return occasion;
        }
      }
    }
    return null;
  }

  void _editEvent(String oldEvent, DateTime eventDate) {
    final TextEditingController eventController = TextEditingController(text: oldEvent);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Event'),
          content: TextField(
            controller: eventController,
            decoration: const InputDecoration(
              hintText: 'Edit event title',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _events[eventDate]!.remove(oldEvent);

                if (_events[eventDate]!.isEmpty) {
                  _events.remove(eventDate);
                }
                _saveEvents(_getCurrentUserID());

                _safeSetState(() {});
                Navigator.pop(context);
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            // Save Button
            TextButton(
              onPressed: () {
                if (eventController.text.isNotEmpty) {
                  // Remove the old event and add the updated one
                  _events[eventDate]!.remove(oldEvent);
                  _events[eventDate]!.add(eventController.text);
                  _saveEvents(_getCurrentUserID()); 
                  _safeSetState(() {});
                  Navigator.pop(context);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void deleteEvent(String eventTitle, DateTime eventDate) {
    // if the event date exists in the map
    if (_events.containsKey(eventDate)) {
      _events[eventDate]!.remove(eventTitle);

      if (_events[eventDate]!.isEmpty) {
        _events.remove(eventDate);
      }
      _saveEvents(_getCurrentUserID());
      _safeSetState(() {});
    }
  }
  final GlobalKey<TooltipState> tooltipKey = GlobalKey<TooltipState>();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SingleChildScrollView(
        child: Column(
          children: [
            TableCalendar(
              focusedDay: _selectedDate,
              firstDay: DateTime.utc(2000, 1, 1),
              lastDay: DateTime.utc(2100, 12, 31),
              selectedDayPredicate: (day) => isSameDay(day, _selectedDate),
              onDaySelected: (selectedDay, focusedDay) {
                _safeSetState(() {
                  _selectedDate = selectedDay;
                });
              },
              eventLoader: (day) {
                return _events[DateTime(day.year, day.month, day.day)] ?? [];
              },
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, date, events) {
                  if (events.isNotEmpty) {
                    final hasSpecialOccasion = _hasSpecialOccasion(date);
                    return Positioned(
                      bottom: 1,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasSpecialOccasion ? Colors.red : Colors.blue,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            const SizedBox(height: 20),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                _showAddEventDialog();
              },
              child: const Text('Add Event'),
            ),
            const SizedBox(height: 10),
            ListView(
              shrinkWrap: true, 
              physics: const NeverScrollableScrollPhysics(), 
              children: (_events[DateTime(
                        _selectedDate.year,
                        _selectedDate.month,
                        _selectedDate.day,
                      )] ??
                      [])
                  .map((event) {
                final isSpecial = _isSpecialOccasion(event);
                final occasionKeyword = _getOccasionKeyword(event);
                return ListTile(
                  title: Text(
                    event,
                    style: TextStyle(
                      color: isSpecial ? Colors.red : Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  leading: Icon(
                    Icons.event,
                    color: isSpecial ? Colors.red : Colors.blue,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSpecial)
                        Tooltip(
                          message: 'Tap to shop for this event!', 
                          triggerMode: TooltipTriggerMode.tap,
                          preferBelow: false,
                          child: IconButton(
                            icon: const Icon(Icons.card_giftcard, 
                                  color: Colors.redAccent, 
                                  size: 28), 
                            onPressed: () {
                              if (occasionKeyword != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => GiftTab(
                                      showBackButton: true,
                                      initialOccasion: occasionKeyword,
                                      showFilterPanel: true,
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.grey),
                        onPressed: () {
                          _editEvent(event, DateTime(
                            _selectedDate.year,
                            _selectedDate.month,
                            _selectedDate.day,
                          ));
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _askToSendHybridGift(String eventName) async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Send Hybrid Gift?'),
          content: Text('Send the digital gift now and schedule the media for "$eventName"?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(),
                  ),
                );
              },
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
  }

  void _showAddEventDialog() {
    final TextEditingController eventController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Event'),
          content: TextField(
            controller: eventController,
            decoration: const InputDecoration(
              hintText: 'Enter event title',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (eventController.text.isNotEmpty) {
                  final eventName = eventController.text.trim();
                  _addEvent(eventName);
                  Navigator.pop(context);

                  // Check if the event is a special occasion
                  if (_isSpecialOccasion(eventName)) {
                    _askToSendHybridGift(eventName); 
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}