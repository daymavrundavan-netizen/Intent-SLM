import 'package:flutter/material.dart';
import 'package:flutter_screen_overlay/flutter_screen_overlay.dart';
import 'package:record/record.dart';

class EdgeAgentPage extends StatefulWidget {
  const EdgeAgentPage({super.key});

  @override
  State<EdgeAgentPage> createState() => _EdgeAgentPageState();
}

class _EdgeAgentPageState extends State<EdgeAgentPage> {
  bool _checking = true;
  bool _active = false;

  @override
  void initState() {
    super.initState();

    _refresh();
  }

  Future<void> _refresh() async {
    final active = await FlutterScreenOverlay.isActive();

    if (!mounted) {
      return;
    }

    setState(() {
      _active = active;
      _checking = false;
    });
  }

  Future<void> _enable() async {
    //
    // flutter_screen_overlay dimensions reach
    // Android WindowManager as physical pixels.
    // Scale our desired logical bubble size by DPR.
    //

    setState(() {
      _checking = true;
    });

    try {
      debugPrint('======================================');
      debugPrint('EDGE AGENT: ENABLE REQUESTED');

      var permission = await FlutterScreenOverlay.isPermissionGranted();

      debugPrint('EDGE AGENT: permission = $permission');

      if (!permission) {
        debugPrint('EDGE AGENT: requesting overlay permission');

        await FlutterScreenOverlay.requestPermission();

        if (!mounted) {
          return;
        }

        setState(() {
          _checking = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Allow "Display over other apps", return here, then tap Enable Edge Agent again.',
            ),
          ),
        );

        return;
      }

      debugPrint('EDGE AGENT: warming overlay Flutter engine');

      await FlutterScreenOverlay.warmUp();

      debugPrint('EDGE AGENT: warmUp complete');

      var active = await FlutterScreenOverlay.isActive();

      debugPrint('EDGE AGENT: active before show = $active');

      if (active) {
        debugPrint('EDGE AGENT: closing previous overlay');

        await FlutterScreenOverlay.closeOverlay();

        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      debugPrint('EDGE AGENT: calling showOverlay');

      //
      // Microphone permission must be requested from the
      // normal Flutter Activity before the floating overlay
      // begins using the microphone.
      //
      debugPrint('EDGE AGENT: checking microphone permission');

      final permissionRecorder = AudioRecorder();

      final microphoneGranted = await permissionRecorder.hasPermission();

      await permissionRecorder.dispose();

      debugPrint('EDGE AGENT: microphone permission = $microphoneGranted');

      if (!microphoneGranted) {
        if (!mounted) {
          return;
        }

        setState(() {
          _checking = false;
          _active = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 6),
            content: Text(
              'Please allow microphone access to use Edge Agent voice commands.',
            ),
          ),
        );

        return;
      }

      debugPrint('EDGE AGENT: microphone permission granted');

      await FlutterScreenOverlay.showOverlay(
        height: 100,
        width: 100,
        alignment: OverlayAlignment.centerRight,
        flag: OverlayFlag.defaultFlag,
        enableDrag: true,
        positionGravity: PositionGravity.auto,
        overlayTitle: 'C-DAC Edge Agent',
        overlayContent: 'Offline Edge Agent active',
      );

      debugPrint('EDGE AGENT: showOverlay returned');

      await Future<void>.delayed(const Duration(seconds: 2));

      active = await FlutterScreenOverlay.isActive();

      debugPrint('EDGE AGENT: active after show = $active');

      debugPrint('======================================');

      if (!mounted) {
        return;
      }

      setState(() {
        _active = active;
        _checking = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active
                ? 'Edge Agent overlay service started.'
                : 'Edge Agent overlay did not become active.',
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('EDGE AGENT START ERROR: $error');

      debugPrint('EDGE AGENT STACK TRACE: $stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _active = false;
        _checking = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text('Edge Agent failed: $error'),
        ),
      );
    }
  }

  Future<void> _disable() async {
    await FlutterScreenOverlay.closeOverlay();

    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primaryContainer, scheme.tertiaryContainer],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 42,
                  color: scheme.primary,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Edge Agent',
                  style: TextStyle(fontSize: 31, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A persistent, context-aware voice assistant that stays available over other Android apps.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        _active
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        color: _active
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _active ? 'Agent active' : 'Agent inactive',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              _active
                                  ? 'Floating voice bubble is running.'
                                  : 'Enable the floating voice agent.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _checking
                          ? null
                          : _active
                          ? _disable
                          : _enable,
                      icon: Icon(
                        _active
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_rounded,
                      ),
                      label: Text(
                        _checking
                            ? 'Checking...'
                            : _active
                            ? 'Disable Edge Agent'
                            : 'Enable Edge Agent',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'Context-aware examples',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          const _Example(number: '1', text: '"Open calculator"'),
          const _Example(number: '2', text: '"Calculate 2 plus 3"'),
          const _Example(number: '3', text: '"Multiply that by 10"'),
          const _Example(number: '4', text: '"Open camera"'),
          const SizedBox(height: 20),
          const Card(
            elevation: 0,
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.privacy_tip_outlined),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Push-to-talk only. The microphone is not continuously listening.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Example extends StatelessWidget {
  final String number;
  final String text;

  const _Example({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(radius: 16, child: Text(number)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
