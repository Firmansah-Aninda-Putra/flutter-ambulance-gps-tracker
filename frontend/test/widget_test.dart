import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ambulance_tracker/main.dart';
import 'package:ambulance_tracker/screens/splash_screen.dart';

void main() {
  testWidgets('App should launch, show splash, then login',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Cek splash screen tampil
    expect(find.byType(SplashScreen), findsOneWidget);

    // Tunggu splash selesai
    await tester.pumpAndSettle();

    // Cek login screen muncul
    expect(find.text('Login Ambulan Tracker'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
  });
}
