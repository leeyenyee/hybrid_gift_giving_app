import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Add this import
import 'register_page.dart';
import 'login_page.dart';
import 'chat_page.dart';
import 'account_info.dart';
import 'calendar.dart';
import 'gift_recommendation.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'dart:ui';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';

bool isLoggedIn = false;
String loggedInEmail = '';
final GlobalKey<State<ChatScreen>> chatKey = GlobalKey<State<ChatScreen>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Firebase
  await Firebase.initializeApp();
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.playIntegrity,
  );

  FlutterError.onError = (FlutterErrorDetails details) {
    FirebaseCrashlytics.instance.recordFlutterError(details);
    showErrorDialog("An unexpected error occurred. Please try again.");
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack);
    showErrorDialog("An unexpected error occurred. Please try again.");
    return true;
  };

  tz.initializeTimeZones();

  final prefs = await SharedPreferences.getInstance();
  final userUid = prefs.getString('userUid');

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: MyApp(
        initialRoute: userUid != null ? '/home' : '/login',
      ),
    ),
  );
}

void showErrorDialog(String message) {
  // Use a global navigator key to show the error dialog
  final navigatorKey = GlobalKey<NavigatorState>();
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gifting App',
      theme: ThemeData.light(), 
      darkTheme: ThemeData.dark(),
      themeMode: Provider.of<ThemeProvider>(context).themeMode, 
      initialRoute: initialRoute,
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/chat': (context) => ChatScreen(key: chatKey),
        '/home': (context) => const MyHomePage(),
        '/account': (context) => const AccountInfoPage(),
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;
  String? currentUserId;
  AudioPlayer _audioPlayer = AudioPlayer(); // Initialize AudioPlayer for tab clicking sound

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  void _initializeUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        currentUserId = user.uid;
      });
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _onTabTapped(int index) async {
    await _audioPlayer.play(AssetSource('audio/press-button-sound-effects.mp3'));

    // Update the selected index
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose(); // Dispose the AudioPlayer
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<Widget> pages = [
      const CalendarTab(),
      GiftTab(),
      ChatScreen(),
      const AccountInfoPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 176, 146, 227),
        title: const Text('Gifting App'),
        leading: const Icon(Icons.card_giftcard),
        actions: [
          // Settings icon with dropdown menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings), // Settings icon
            onSelected: (value) {
              final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
              if (value == 'light') {
                themeProvider.setThemeMode(ThemeMode.light);
              } else if (value == 'dark') {
                themeProvider.setThemeMode(ThemeMode.dark); 
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'light',
                child: Text('Light Mode'),
              ),
              const PopupMenuItem(
                value: 'dark',
                child: Text('Dark Mode'),
              ),
            ],
          ),

          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              showDialog(
                context: context, 
                builder: (context) => AlertDialog(
                  title: Text("Logout"),
                  content: Text("Are you sure you want to logout?"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text("Cancel"),
                    ),
                    TextButton( 
                      onPressed: () async {
                        (chatKey.currentWidget as ChatScreen?)?.resetState();

                        await FirebaseAuth.instance.signOut(); 
                        Navigator.pushReplacementNamed(context, '/login');
                        
                      },
                      child: Text("Logout"), 
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        backgroundColor: Colors.white, 
        selectedItemColor: Colors.blue, 
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Calendar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Gifts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_2_outlined),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const RegisterPage()),
            );
          },
          child: const Text('Register'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const LoginPage()),
            );
          },
          child: const Text('Login'),
        ),
      ],
    );
  }
}

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }
}