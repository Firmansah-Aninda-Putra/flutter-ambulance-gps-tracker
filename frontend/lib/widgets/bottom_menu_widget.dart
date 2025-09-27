// ambulance-tracker/frontend/lib/widgets/bottom_menu_widget.dart

import 'package:flutter/material.dart';

class BottomMenuWidget extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomMenuWidget({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.map),
          label: 'Map',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.comment),
          label: 'Komentar',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Dashboard',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profil',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.call),
          label: 'Panggil',
        ),
      ],
      onTap: onTap,
    );
  }
}
