import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MediaStore.ensureInitialized();
  MediaStore.appFolder = 'Footnote Walk';
  runApp(const FootnoteWalkApp());
}

class FootnoteWalkApp extends StatelessWidget {
  const FootnoteWalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '풋노트 산책',
      theme: AppTheme.light(),
      home: const HomeScreen(),
    );
  }
}
