import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'src/controllers/app_controller.dart';
import 'src/screens/app_shell.dart';
import 'src/theme/app_theme.dart';

/// מסתיר את מסגרת החלון של המערכת; שורת הכותרת היא [AppTitleBar] שבתוך האפליקציה.
/// כשל כאן הוא קוסמטי בלבד: נשארת מסגרת המערכת.
Future<bool> _prepareWindow() async {
  if (!(Platform.isWindows || Platform.isLinux)) return false;
  try {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(900, 620));
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    return true;
  } catch (e) {
    debugPrint('הכנת החלון נכשלה: $e');
    return false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final customFrame = await _prepareWindow();
  runApp(MyLibraryApp(customFrame: customFrame));
}

class MyLibraryApp extends StatefulWidget {
  const MyLibraryApp({super.key, this.customFrame = false});

  final bool customFrame;

  @override
  State<MyLibraryApp> createState() => _MyLibraryAppState();
}

class _MyLibraryAppState extends State<MyLibraryApp> {
  final AppController _controller = AppController();

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => MaterialApp(
        title: 'ספרייה אישית לאוצריא',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _controller.themeMode,
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child ?? const SizedBox.shrink()),
        home: AppShell(controller: _controller, customTitleBar: widget.customFrame),
      ),
    );
  }
}
