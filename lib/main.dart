//main
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:premier_league/provider/player_provider.dart';
import 'package:premier_league/screens/home_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:premier_league/match_service.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 Firebase mit konfigurierten Optionen initialisieren
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp());
}


class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (ctx) => PlayerProvider()),
      ],
      child: MaterialApp(
        title: 'Premier League Fantasy App',
        theme: ThemeData(primarySwatch: Colors.blue),
        home: HomeScreen(),
      ),
    );
  }
}
