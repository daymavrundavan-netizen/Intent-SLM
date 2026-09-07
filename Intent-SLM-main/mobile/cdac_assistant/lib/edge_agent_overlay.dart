import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screen_overlay/flutter_screen_overlay.dart';

import 'action_router.dart';
import 'agent_context.dart';
import 'calculator_skill.dart';
import 'overlay_action_executor.dart';
import 'voice_engine.dart';

class EdgeAgentOverlayApp extends StatelessWidget {
  const EdgeAgentOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      //
      // Critical for a real floating bubble.
      // Do not paint a rectangular MaterialApp background.
      //
      color: Colors.transparent,

      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
      ),

      home: const EdgeAgentOverlay(),
    );
  }
}

class EdgeAgentOverlay extends StatefulWidget {
  const EdgeAgentOverlay({super.key});

  @override
  State<EdgeAgentOverlay> createState() => _EdgeAgentOverlayState();
}

class _EdgeAgentOverlayState extends State<EdgeAgentOverlay> {
  final VoiceEngine _voice = VoiceEngine();

  final ActionRouter _router = ActionRouter();

  final AgentContext _context = AgentContext();

  final CalculatorSkill _calculator = CalculatorSkill();

  final OverlayActionExecutor _actions = OverlayActionExecutor();

  bool _recording = false;
  bool _working = false;
  bool _expanded = false;

  String _headline = 'Edge Agent';
  String _message = 'Tap to speak';

  Timer? _collapseTimer;

  String _repairTranscript(String input) {
    var text = input.trim();

    //
    // tiny.en occasionally hears:
    // "turn on the touch"
    // instead of:
    // "turn on the torch"
    //
    final lower = text.toLowerCase();

    final looksLikeTorchCommand =
        lower.contains('turn on') ||
        lower.contains('turn off') ||
        lower.contains('switch on') ||
        lower.contains('switch off');

    if (looksLikeTorchCommand &&
        RegExp(r'\btouch\b', caseSensitive: false).hasMatch(text)) {
      text = text.replaceAll(
        RegExp(r'\btouch\b', caseSensitive: false),
        'torch',
      );
    }

    return text;
  }

  Future<void> _toggleVoice() async {
    debugPrint(
      'EDGE OVERLAY TAP: recording=$_recording working=$_working expanded=$_expanded',
    );

    if (_working) {
      return;
    }

    _collapseTimer?.cancel();

    //
    // START RECORDING
    //
    if (!_recording) {
      try {
        await _expand();

        debugPrint('EDGE OVERLAY: calling VoiceEngine.startRecording');

        final started = await _voice.startRecording(
          permissionAlreadyGranted: true,
        );

        debugPrint('EDGE OVERLAY: startRecording returned $started');

        if (!mounted) {
          return;
        }

        if (!started) {
          _showError('Microphone could not be started.');
          return;
        }

        setState(() {
          _recording = true;
          _working = false;
          _headline = 'Listening';
          _message = 'Speak your command, then tap Stop.';
        });

        debugPrint('EDGE OVERLAY: recording started');
      } catch (error, stackTrace) {
        debugPrint('EDGE OVERLAY RECORD ERROR: $error');
        debugPrintStack(stackTrace: stackTrace);

        _showError(error.toString());
      }

      return;
    }

    //
    // STOP + WHISPER
    //
    setState(() {
      _recording = false;
      _working = true;
      _headline = 'Understanding';
      _message = 'Whisper is running locally...';
    });

    try {
      final result = await _voice.stopAndTranscribe();

      if (!mounted) {
        return;
      }

      final transcript = _repairTranscript(result.text.trim());

      if (transcript.isEmpty) {
        setState(() {
          _working = false;
          _headline = 'No speech detected';
          _message = 'Tap the microphone and try again.';
        });

        _scheduleCollapse(const Duration(seconds: 3));

        return;
      }

      debugPrint('======================================');
      debugPrint('EDGE OVERLAY COMMAND: $transcript');
      debugPrint(
        'EDGE OVERLAY ASR: '
        '${result.transcriptionMs.toStringAsFixed(0)} ms',
      );
      debugPrint('======================================');

      setState(() {
        _headline = 'Heard';
        _message = transcript;
      });

      await _processCommand(transcript);
    } catch (error, stackTrace) {
      debugPrint('EDGE OVERLAY WHISPER ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      _showError(error.toString());
    }
  }

  Future<void> _processCommand(String text) async {
    _context.observe(text);

    //
    // ------------------------------------------
    // LOCAL CONTEXT-AWARE CALCULATOR
    // ------------------------------------------
    //
    if (_calculator.canHandle(text, _context)) {
      final result = _calculator.evaluate(text, _context);

      if (result == null) {
        _showError('I could not understand that calculation.');
        return;
      }

      _context.setSkill(AgentSkill.calculator);

      debugPrint(
        'EDGE OVERLAY CALCULATOR RESULT: '
        '${result.display}',
      );

      _showResult(
        title: 'Calculator',
        message: result.display,
        collapseAfter: const Duration(seconds: 5),
      );

      return;
    }

    //
    // ------------------------------------------
    // DEVICE COMMAND ROUTER
    // ------------------------------------------
    //
    final command = _router.route(text);

    if (command != null) {
      try {
        late String status;

        switch (command.action) {
          case DeviceActionType.openCamera:
            _context.setSkill(AgentSkill.camera);

            status = await _actions.openCamera();
            break;

          case DeviceActionType.openCalculator:
            _context.setSkill(AgentSkill.calculator);

            status = await _actions.openCalculator();
            break;

          case DeviceActionType.openBrowser:
            _context.setSkill(AgentSkill.browser);

            status = await _actions.openBrowser();
            break;

          case DeviceActionType.flashlight:
            final normalized = text.toLowerCase();

            final enable =
                !normalized.contains('off') && !normalized.contains('disable');

            status = await _actions.setTorch(enable);
            break;

          case DeviceActionType.playMusic:
            status = await _actions.playMusic();
            break;
        }

        debugPrint('EDGE OVERLAY ACTION RESULT: $status');

        _showResult(
          title: _titleFor(command.action),
          message: status,
          collapseAfter: const Duration(seconds: 2),
        );
      } catch (error, stackTrace) {
        debugPrint('EDGE OVERLAY ACTION ERROR: $error');
        debugPrintStack(stackTrace: stackTrace);

        _showError(error.toString());
      }

      return;
    }

    //
    // ------------------------------------------
    // CAMERA CONTEXT FOLLOW-UP
    // ------------------------------------------
    //
    // We deliberately do NOT fake camera capture.
    // Voice shutter control can be added separately.
    //
    final normalized = text.toLowerCase();

    if (_context.activeSkill == AgentSkill.camera &&
        (normalized.contains('take a photo') ||
            normalized.contains('take photo') ||
            normalized.contains('click photo') ||
            normalized.contains('capture'))) {
      _showResult(
        title: 'Camera',
        message:
            'Camera context understood. Voice shutter capture is not enabled yet.',
        collapseAfter: const Duration(seconds: 4),
      );

      return;
    }

    _showResult(
      title: 'Edge Agent',
      message: 'Command is not handled by a device skill yet.',
      collapseAfter: const Duration(seconds: 4),
    );
  }

  String _titleFor(DeviceActionType action) {
    switch (action) {
      case DeviceActionType.openCamera:
        return 'Camera';

      case DeviceActionType.openCalculator:
        return 'Calculator';

      case DeviceActionType.openBrowser:
        return 'Browser';

      case DeviceActionType.flashlight:
        return 'Flashlight';

      case DeviceActionType.playMusic:
        return 'Music';
    }
  }

  void _showResult({
    required String title,
    required String message,
    Duration? collapseAfter,
  }) {
    if (!mounted) {
      return;
    }

    setState(() {
      _recording = false;
      _working = false;
      _headline = title;
      _message = message;
    });

    if (collapseAfter != null) {
      _scheduleCollapse(collapseAfter);
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _recording = false;
      _working = false;
      _headline = 'Agent error';
      _message = message;
    });
  }

  void _scheduleCollapse(Duration duration) {
    _collapseTimer?.cancel();

    _collapseTimer = Timer(duration, () {
      if (mounted && !_recording && !_working) {
        _collapse();
      }
    });
  }

  Future<void> _expand() async {
    if (_expanded) {
      return;
    }

    //
    // flutter_screen_overlay ultimately uses
    // Android WindowManager dimensions.
    //
    // Give it physical pixels so the Flutter
    // content has roughly 330 x 220 logical dp.
    //
    const width = 330;
    const height = 220;

    await FlutterScreenOverlay.resizeOverlay(width, height, true);

    if (!mounted) {
      return;
    }

    setState(() {
      _expanded = true;
    });
  }

  Future<void> _collapse() async {
    if (!_expanded) {
      return;
    }

    if (_recording || _working) {
      return;
    }

    const size = 96;

    await FlutterScreenOverlay.resizeOverlay(size, size, true);

    if (!mounted) {
      return;
    }

    setState(() {
      _expanded = false;
      _headline = 'Edge Agent';
      _message = 'Tap to speak';
    });
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _voice.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    //
    // No Scaffold here.
    // The overlay background must stay transparent.
    //
    return Material(
      type: MaterialType.transparency,
      child: _expanded ? _buildExpanded() : _buildBubble(),
    );
  }

  Widget _buildBubble() {
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleVoice,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _recording
                  ? const [Color(0xFFFF416C), Color(0xFFFF4B2B)]
                  : const [Color(0xFF7357FF), Color(0xFF22C1FF)],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.88),
              width: 2.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_working)
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                )
              else
                Icon(
                  _recording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 37,
                ),

              Positioned(
                right: 10,
                top: 9,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _recording
                        ? const Color(0xFFFFE082)
                        : const Color(0xFF69F0AE),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpanded() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xF21B1B24),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.34),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF7357FF), Color(0xFF22C1FF)],
                    ),
                  ),
                  child: Icon(
                    _recording
                        ? Icons.graphic_eq_rounded
                        : Icons.auto_awesome_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _recording
                            ? 'ON-DEVICE MICROPHONE'
                            : 'OFFLINE EDGE AGENT',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.56),
                          fontWeight: FontWeight.w700,
                          fontSize: 9,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Minimize',
                  onPressed: (_recording || _working) ? null : _collapse,
                  icon: const Icon(Icons.remove_rounded),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _working ? null : _toggleVoice,
                icon: _working
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                label: Text(
                  _working
                      ? 'Understanding...'
                      : _recording
                      ? 'Stop'
                      : 'Speak',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
