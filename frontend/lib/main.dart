// frontend/lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Tambahkan import lokal dan intl
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

// Import screen tanpa prefix untuk yang tidak menimbulkan ambigu
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/user_profile_screen.dart';
import 'screens/conversation_list_screen.dart';
import 'screens/splash_screen.dart';

// Prefix untuk AdminScreen agar jelas asalnya
import 'screens/admin_screen.dart' as admin_scr;
// Prefix untuk ChatScreen agar jelas asalnya
import 'screens/chat_screen.dart' as chat_scr;

// Untuk mendapatkan userId saat routing ke /conversations
import 'services/auth_service.dart';
import 'models/user_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set default locale ke Indonesia (untuk DateFormat, dsb.)
  Intl.defaultLocale = 'id_ID';

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ambulan Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.red,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),

      // Tambahkan dukungan lokal untuk bahasa Indonesia
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''),
        Locale('id', ''), // Dukungan untuk Indonesia
      ],
      locale: const Locale('id', ''), // Pakai default Bahasa Indonesia

      // Initial route diarahkan ke SplashScreen
      initialRoute: '/splash',

      routes: {
        '/splash': (context) => const SplashScreen(),

        // Setelah splash, langsung ke home tanpa cek login
        '/home': (context) => const HomeScreen(),

        // Login hanya untuk fitur komentar/chat
        '/login': (context) => LoginScreen(
              onLoginSuccess: (bool isAdmin) {
                // Setelah login, kembali ke home
                Navigator.pushReplacementNamed(context, '/home');
              },
            ),
        '/register': (context) => const RegisterScreen(),

        '/admin': (context) => const admin_scr.AdminScreen(),

        '/profile': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          if (args is int && args >= 1) {
            return UserProfileScreen(userId: args);
          }
          return Scaffold(
            appBar: AppBar(title: const Text('Profil Pengguna')),
            body: const Center(child: Text('ID pengguna tidak valid')),
          );
        },

        '/conversations': (context) {
          return FutureBuilder<User?>(
            future: AuthService().getCurrentUser(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              final user = snapshot.data;
              if (user == null || !user.isAdmin) {
                return Scaffold(
                  appBar: AppBar(title: const Text('Inbox Chat')),
                  body: const Center(child: Text('Session admin tidak valid')),
                );
              }
              return ConversationListScreen(
                currentUserId: user.id,
              );
            },
          );
        },
      },

      onGenerateRoute: (settings) {
        if (settings.name == '/chat') {
          final args = settings.arguments;
          if (args is Map<String, dynamic>) {
            final int? targetUserId = args['targetUserId'] as int?;
            final String? targetUsername = args['targetUsername'] as String?;
            if (targetUserId != null && targetUsername != null) {
              return MaterialPageRoute(
                builder: (_) => chat_scr.ChatScreen(
                  targetUserId: targetUserId,
                  targetUsername: targetUsername,
                ),
              );
            }
          }
        }
        return null;
      },

      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Halaman Tidak Ditemukan')),
            body: const Center(child: Text('Halaman tidak ditemukan')),
          ),
        );
      },
    );
  }
}
