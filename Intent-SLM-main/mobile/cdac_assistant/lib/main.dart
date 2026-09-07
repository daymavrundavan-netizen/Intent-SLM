import 'dart:async';

import 'package:flutter/material.dart';

import 'assistant_page.dart';
import 'device_hub_page.dart';
import 'edge_agent_bridge.dart';
import 'edge_agent_overlay.dart';
import 'edge_agent_page.dart';
import 'project_lab_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const CdacAssistantApp());
}

///
/// IMPORTANT:
/// This is a second Flutter entry point.
///
/// Android's floating overlay service starts this
/// Flutter entry point separately from the normal app.
///
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const EdgeAgentOverlayApp());
}

class CdacAssistantApp extends StatelessWidget {
  const CdacAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'C-DAC Edge Agent',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        cardTheme: CardThemeData(
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 76,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
            );
          }),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: scheme.primary, width: 1.5),
          ),
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  late final EdgeAgentBridge _edgeAgentBridge;

  @override
  void initState() {
    super.initState();

    //
    // This bridge stays alive while the main
    // application process is running.
    //
    // It receives commands from the floating
    // overlay and performs Agent Skills.
    //
    _edgeAgentBridge = EdgeAgentBridge();

    _edgeAgentBridge.start();

    debugPrint('======================================');

    debugPrint('C-DAC EDGE AGENT CORE READY');

    debugPrint('Tabs: Assistant | Device Hub | Edge Agent | Project');

    debugPrint('======================================');
  }

  @override
  void dispose() {
    unawaited(_edgeAgentBridge.dispose());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          //
          // TAB 1
          //
          const AssistantPage(),

          //
          // TAB 2
          //
          DeviceHubPage(),

          //
          // TAB 3
          //
          const EdgeAgentPage(),

          //
          // TAB 4
          //
          const ProjectLabPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          setState(() {
            _index = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology_rounded),
            label: 'Assistant',
          ),
          NavigationDestination(
            icon: Icon(Icons.devices_outlined),
            selectedIcon: Icon(Icons.devices_rounded),
            label: 'Device Hub',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'Edge Agent',
          ),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science_rounded),
            label: 'Project',
          ),
        ],
      ),
    );
  }
}
