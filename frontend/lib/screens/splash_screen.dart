// frontend/lib/screens/splash_screen.dart

import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToHome();
  }

  Future<void> _navigateToHome() async {
    // Tampilkan splash selama 2 detik
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    // Setelah itu, langsung ke HomeScreen tanpa cek login
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Transform.translate(
          offset: const Offset(0, -4), // geser 4px ke atas
          child: Image.asset(
            'assets/images/madiun.png',
            width: 30,
            height: 30,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
