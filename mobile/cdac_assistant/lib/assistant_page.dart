import 'dart:convert';

import 'package:flutter/material.dart';

import 'action_dispatcher.dart';
import 'action_router.dart';
import 'device_action_page.dart';
import 'intent_acceptance_gate.dart';
import 'nlu_engine.dart';
import 'voice_engine.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final NluEngine _engine = NluEngine();
  final VoiceEngine _voice = VoiceEngine();
  final ActionRouter _router = ActionRouter();
  final DeviceActionDispatcher _dispatcher = DeviceActionDispatcher();

  final TextEditingController _controller = TextEditingController(
    text: 'play a song by adele',
  );

  bool _loading = true;
  bool _processing = false;
  bool _recording = false;
  bool _transcribing = false;

  int _progress = 0;

  String? _error;
  String? _transcript;

  double? _asrLatency;

  NluResult? _result;

  String? _unsupportedReason;
  String? _rejectedIntent;
  double? _rejectedConfidence;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _engine.initialize();

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint(error.toString());
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<bool> _handleCameraCaptureCommand(String input) async {
    final text = input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[.!?,;:]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ');

    final asksForCameraAction =
        RegExp(r'\b(take|click|capture|snap|open)\b').hasMatch(text) &&
        RegExp(r'\b(photo|picture|camera|selfie)\b').hasMatch(text);

    if (!asksForCameraAction) {
      return false;
    }

    final front = text.contains('front') || text.contains('selfie');

    final back = text.contains('back') || text.contains('rear');

    if (!front && !back) {
      return false;
    }

    try {
      final status = front
          ? await _dispatcher.captureFrontPhoto()
          : await _dispatcher.captureBackPhoto();

      debugPrint('CAMERA CAPTURE ACTION: $status');

      if (!mounted) {
        return true;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(status), duration: const Duration(seconds: 3)),
        );

      return true;
    } catch (error, stackTrace) {
      debugPrint('CAMERA CAPTURE ERROR: $error');

      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return true;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Camera capture failed: $error')),
        );

      return true;
    }
  }

  Future<bool> _handleWhatsAppCommand(String input) async {
    final text = input.trim().replaceAll(RegExp(r'\s+'), ' ');

    RegExpMatch? match;

    //
    // Example:
    // send hii to shubham on whatsapp
    //
    match = RegExp(
      r'^send\s+(.+?)\s+to\s+(.+?)\s+on\s+whatsapp$',
      caseSensitive: false,
    ).firstMatch(text);

    //
    // Also support:
    // open whatsapp and send hii to shubham
    //
    match ??= RegExp(
      r'^open\s+whatsapp\s+(?:and\s+)?send\s+(.+?)\s+to\s+(.+?)$',
      caseSensitive: false,
    ).firstMatch(text);

    if (match == null) {
      return false;
    }

    final message = match.group(1)?.trim() ?? '';

    final contact = match.group(2)?.trim() ?? '';

    if (message.isEmpty || contact.isEmpty) {
      return false;
    }

    try {
      final status = await _dispatcher.sendWhatsApp(
        contact: contact,
        message: message,
      );

      debugPrint('WHATSAPP ACTION: $status');

      if (!mounted) {
        return true;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(status), duration: const Duration(seconds: 3)),
        );

      return true;
    } catch (error, stackTrace) {
      debugPrint('WHATSAPP ACTION ERROR: $error');

      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return true;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('WhatsApp action failed: $error'),
            duration: const Duration(seconds: 3),
          ),
        );

      return true;
    }
  }

  Future<bool> _handleLocalMediaControl(String input) async {
    final text = input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[.!?,;:]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ');

    String? status;

    final pause = RegExp(
      r'^(?:please )?pause (?:the )?(?:music|song)(?: please)?$',
    ).hasMatch(text);

    final resume = RegExp(
      r'^(?:please )?(?:resume|continue) (?:the )?(?:music|song)(?: please)?$',
    ).hasMatch(text);

    final stop = RegExp(
      r'^(?:please )?stop (?:the )?(?:music|song)(?: please)?$',
    ).hasMatch(text);

    try {
      if (pause) {
        status = await _dispatcher.pauseMusic();
      } else if (resume) {
        status = await _dispatcher.resumeMusic();
      } else if (stop) {
        status = await _dispatcher.stopMusic();
      }
    } catch (error, stackTrace) {
      debugPrint('LOCAL MUSIC CONTROL ERROR: $error');

      debugPrintStack(stackTrace: stackTrace);

      status = 'Music control failed: $error';
    }

    if (status == null) {
      return false;
    }

    debugPrint('LOCAL MUSIC CONTROL: $status');

    if (!mounted) {
      return true;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(status), duration: const Duration(seconds: 2)),
    );

    return true;
  }

  Future<void> _process() async {
    final text = _controller.text.trim();

    if (text.isEmpty || _processing || _loading) {
      return;
    }

    //
    // Product-only local media controls.
    //
    // These are intentionally separate from
    // the seven official Champion V4 intents.
    //
    final handledCameraCapture = await _handleCameraCaptureCommand(text);

    if (!mounted) {
      return;
    }

    if (handledCameraCapture) {
      return;
    }

    final handledWhatsApp = await _handleWhatsAppCommand(text);

    if (!mounted) {
      return;
    }

    if (handledWhatsApp) {
      return;
    }

    final handledMediaControl = await _handleLocalMediaControl(text);

    if (!mounted) {
      return;
    }

    if (handledMediaControl) {
      return;
    }

    //
    // DEVICE ACTION ROUTER
    //
    final deviceCommand = _router.route(text);

    if (deviceCommand != null &&
        deviceCommand.action != DeviceActionType.playMusic) {
      setState(() {
        _result = null;
        _error = null;
        _unsupportedReason = null;
        _rejectedIntent = null;
        _rejectedConfidence = null;
      });

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DeviceActionPage(command: deviceCommand),
        ),
      );

      return;
    }

    //
    // OFFICIAL CHAMPION V4 SLM
    //
    setState(() {
      _processing = true;
      _error = null;
      _unsupportedReason = null;
      _rejectedIntent = null;
      _rejectedConfidence = null;
    });

    try {
      final result = await _engine.predict(text);

      if (!mounted) {
        return;
      }

      //
      // EXECUTION GUARDRAIL
      //
      // Champion V4 remains authoritative for the
      // seven official benchmark intents.
      //
      // The guardrail does NOT change the model output.
      // It only decides whether a product/device action
      // is allowed to execute.
      //
      final acceptance = IntentAcceptanceGate.evaluate(
        text: text,
        predictedIntent: result.intent,
        confidence: result.confidence,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _processing = false;

        //
        // Always preserve the actual Champion V4 result.
        //
        _result = result;

        if (acceptance.accepted) {
          _unsupportedReason = null;
          _rejectedIntent = null;
          _rejectedConfidence = null;
        } else {
          _unsupportedReason = acceptance.reason;

          _rejectedIntent = result.intent;

          _rejectedConfidence = result.confidence;
        }
      });

      debugPrint(
        'EXECUTION GUARDRAIL: '
        'accepted=${acceptance.accepted}, '
        'intent=${result.intent}, '
        'confidence=${result.confidence.toStringAsFixed(4)}, '
        'reason="${acceptance.reason}"',
      );

      //
      // CRITICAL:
      // Never execute a model-driven Android action
      // when the execution guardrail rejects it.
      //
      if (!acceptance.accepted) {
        debugPrint('EXECUTION BLOCKED BY GUARDRAIL');

        return;
      }

      //
      // Product action happens only AFTER:
      //
      // 1. Champion V4 inference
      // 2. Structured intent + slots
      // 3. Execution guardrail acceptance
      //
      await _executeMusicAfterSlm(result, text);
    } catch (error, stackTrace) {
      debugPrint(error.toString());
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      setState(() {
        _processing = false;
        _error = error.toString();
      });
    }
  }

  String _musicQueryFromResult(NluResult result) {
    final json = result.toJson();
    final rawSlots = json['slots'];

    final values = <String, String>{};

    //
    // Support:
    //
    // {
    //   "artist": "adele",
    //   "track": "hello"
    // }
    //
    if (rawSlots is Map) {
      for (final entry in rawSlots.entries) {
        final key = entry.key.toString();

        final value = entry.value?.toString().trim();

        if (value != null && value.isNotEmpty) {
          values[key] = value;
        }
      }
    }

    //
    // Also support:
    //
    // [
    //   {
    //     "slot": "artist",
    //     "value": "adele"
    //   }
    // ]
    //
    if (rawSlots is List) {
      for (final item in rawSlots) {
        if (item is! Map) {
          continue;
        }

        final slot = (item['slot'] ?? item['type'] ?? item['name'])?.toString();

        final value = (item['value'] ?? item['text'])?.toString().trim();

        if (slot != null &&
            slot.isNotEmpty &&
            value != null &&
            value.isNotEmpty) {
          values[slot] = value;
        }
      }
    }

    final parts = <String>[];

    //
    // Searchable entities from the official
    // PlayMusic frame.
    //
    const usefulSlots = <String>[
      'track',
      'artist',
      'album',
      'playlist',
      'genre',
    ];

    for (final key in usefulSlots) {
      final value = values[key];

      if (value == null || value.isEmpty) {
        continue;
      }

      final duplicate = parts.any(
        (existing) => existing.toLowerCase() == value.toLowerCase(),
      );

      if (!duplicate) {
        parts.add(value);
      }
    }

    //
    // music_item is frequently a generic value
    // such as "song", "track", or "music".
    //
    // Do not search for just "song".
    //
    if (parts.isEmpty) {
      final item = values['music_item'];

      if (item != null && item.isNotEmpty) {
        final normalized = item.toLowerCase();

        const genericItems = <String>{
          'song',
          'songs',
          'music',
          'track',
          'tracks',
          'album',
          'albums',
          'artist',
          'playlist',
        };

        if (!genericItems.contains(normalized)) {
          parts.add(item);
        }
      }
    }

    return parts.join(' ').trim();
  }

  Future<void> _executeMusicAfterSlm(
    NluResult result,
    String originalText,
  ) async {
    //
    // Champion V4 is the ONLY authority
    // for the official PlayMusic intent.
    //
    if (result.intent != 'PlayMusic') {
      return;
    }

    final query = _musicQueryFromResult(result);

    debugPrint(
      'CHAMPION V4 PLAY MUSIC: '
      'text="$originalText", '
      'query="$query"',
    );

    //
    // Give Flutter time to paint:
    //
    // intent
    // slots
    // confidence
    // JSON
    //
    // before switching to another app.
    //
    await Future<void>.delayed(const Duration(milliseconds: 800));

    try {
      final status = await _dispatcher.playMusic(query: query);

      debugPrint('POST-SLM MUSIC ACTION: $status');
    } catch (error, stackTrace) {
      //
      // Music-app failure must never
      // invalidate or erase the official
      // Champion V4 result.
      //
      debugPrint(
        'POST-SLM MUSIC ACTION ERROR: '
        '$error',
      );

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _toggleVoice() async {
    if (_loading || _processing || _transcribing) {
      return;
    }

    //
    // START RECORDING
    //
    if (!_recording) {
      try {
        final started = await _voice.startRecording();

        if (!mounted) {
          return;
        }

        if (!started) {
          setState(() {
            _error = 'Microphone permission was not granted.';
          });

          return;
        }

        setState(() {
          _recording = true;
          _error = null;
          _progress = 0;
          _transcript = null;
          _asrLatency = null;
        });
      } catch (error, stackTrace) {
        debugPrint(error.toString());
        debugPrintStack(stackTrace: stackTrace);

        if (!mounted) {
          return;
        }

        setState(() {
          _error = error.toString();
        });
      }

      return;
    }

    //
    // STOP + WHISPER TRANSCRIPTION
    //
    setState(() {
      _recording = false;
      _transcribing = true;
      _progress = 0;
      _error = null;
    });

    try {
      final result = await _voice.stopAndTranscribe(
        onProgress: (progress) {
          if (!mounted) {
            return;
          }

          setState(() {
            _progress = progress;
          });
        },
      );

      if (!mounted) {
        return;
      }

      final text = result.text.trim();

      if (text.isEmpty) {
        setState(() {
          _transcribing = false;
          _error = 'No speech was recognized.';
        });

        return;
      }

      _controller.text = text;

      _controller.selection = TextSelection.collapsed(offset: text.length);

      setState(() {
        _transcribing = false;
        _transcript = text;
        _asrLatency = result.transcriptionMs;
      });

      //
      // Send Whisper transcript through the
      // same router as typed commands.
      //
      await _process();
    } catch (error, stackTrace) {
      debugPrint(error.toString());
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      setState(() {
        _recording = false;
        _transcribing = false;
        _error = error.toString();
      });
    }
  }

  void _sample(String text) {
    _controller.text = text;

    _controller.selection = TextSelection.collapsed(offset: text.length);

    _process();
  }

  @override
  void dispose() {
    _controller.dispose();
    _engine.close();
    _voice.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 18),
              Text(
                'Loading on-device AI...',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        children: [
          //
          // HERO
          //
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primaryContainer, scheme.tertiaryContainer],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.psychology_rounded,
                        color: scheme.primary,
                        size: 32,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.offline_bolt_rounded, size: 17),
                          SizedBox(width: 5),
                          Text(
                            'OFFLINE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text(
                  'Command AI',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Private intelligence. Running entirely on your phone.',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    _HeroChip(icon: Icons.memory_rounded, text: 'INT8 SLM'),
                    _HeroChip(icon: Icons.mic_rounded, text: 'Whisper'),
                    _HeroChip(icon: Icons.cloud_off_rounded, text: 'No Cloud'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          //
          // COMMAND INPUT
          //
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Ask your assistant',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _controller,
                    minLines: 2,
                    maxLines: 4,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: 'Type a command...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _process(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _processing || _transcribing
                              ? null
                              : _process,
                          icon: _processing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.psychology_rounded),
                          label: Text(
                            _processing ? 'Understanding...' : 'Understand',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 54,
                        height: 48,
                        child: IconButton.filledTonal(
                          onPressed: _processing || _transcribing
                              ? null
                              : _toggleVoice,
                          icon: Icon(
                            _recording ? Icons.stop_rounded : Icons.mic_rounded,
                          ),
                          tooltip: 'Voice command',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          //
          // LISTENING
          //
          if (_recording) ...[
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              child: ListTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.mic_rounded, color: scheme.error),
                ),
                title: const Text(
                  'Listening...',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Speak clearly, then tap Stop.'),
                trailing: FilledButton.tonal(
                  onPressed: _toggleVoice,
                  child: const Text('Stop'),
                ),
              ),
            ),
          ],

          //
          // WHISPER PROGRESS
          //
          if (_transcribing) ...[
            const SizedBox(height: 14),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.graphic_eq_rounded),
                        SizedBox(width: 8),
                        Text(
                          'Transcribing locally',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _progress > 0 ? _progress / 100 : null,
                    ),
                    const SizedBox(height: 8),
                    Text('Whisper $_progress%'),
                  ],
                ),
              ),
            ),
          ],

          //
          // TRANSCRIPT
          //
          if (_transcript != null) ...[
            const SizedBox(height: 14),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'VOICE TRANSCRIPT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _transcript!,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_asrLatency != null) ...[
                      const SizedBox(height: 6),
                      Text('Whisper • ${_asrLatency!.toStringAsFixed(0)} ms'),
                    ],
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          //
          // SEPARATOR — OFFICIAL SLM AREA
          //
          Row(
            children: [
              Expanded(child: Divider(color: scheme.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'CHAMPION V4 SLM',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Expanded(child: Divider(color: scheme.outlineVariant)),
            ],
          ),

          const SizedBox(height: 18),

          Text(
            'Official command understanding',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),

          const SizedBox(height: 5),

          Text(
            'These examples are handled by the frozen 7-intent competition model.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),

          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.music_note_rounded),
                label: const Text('PlayMusic'),
                onPressed: () => _sample('play a song by adele'),
              ),
              ActionChip(
                avatar: const Icon(Icons.playlist_add_rounded),
                label: const Text('AddToPlaylist'),
                onPressed: () =>
                    _sample('add this track to my workout playlist'),
              ),
              ActionChip(
                avatar: const Icon(Icons.cloud_rounded),
                label: const Text('GetWeather'),
                onPressed: () =>
                    _sample('what is the weather in mumbai this weekend'),
              ),
              ActionChip(
                avatar: const Icon(Icons.restaurant_rounded),
                label: const Text('BookRestaurant'),
                onPressed: () => _sample(
                  'book a table for two at an italian restaurant tomorrow at 8 pm',
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.star_rounded),
                label: const Text('RateBook'),
                onPressed: () => _sample('rate the book sapiens five stars'),
              ),
              ActionChip(
                avatar: const Icon(Icons.search_rounded),
                label: const Text('SearchCreativeWork'),
                onPressed: () => _sample('find the movie inception'),
              ),
              ActionChip(
                avatar: const Icon(Icons.movie_filter_rounded),
                label: const Text('SearchScreeningEvent'),
                onPressed: () =>
                    _sample('are there any shows of dune near me tonight'),
              ),
            ],
          ),

          //
          // ERROR
          //
          if (_error != null) ...[
            const SizedBox(height: 18),
            Card(
              elevation: 0,
              child: ListTile(
                leading: Icon(Icons.error_outline_rounded, color: scheme.error),
                title: const Text(
                  'Something went wrong',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(_error!),
              ),
            ),
          ],

          //
          // UNSUPPORTED / OUT-OF-DOMAIN COMMAND
          //
          if (_unsupportedReason != null) ...[
            const SizedBox(height: 22),
            _UnsupportedCommandCard(
              reason: _unsupportedReason!,
              predictedIntent: _rejectedIntent,
              confidence: _rejectedConfidence,
            ),
          ],

          //
          // SLM RESULT
          //
          if (_result != null) ...[
            const SizedBox(height: 22),
            _SlmResultCard(result: _result!),
          ],
        ],
      ),
    );
  }
}

class _UnsupportedCommandCard extends StatelessWidget {
  final String reason;
  final String? predictedIntent;
  final double? confidence;

  const _UnsupportedCommandCard({
    required this.reason,
    required this.predictedIntent,
    required this.confidence,
  });

  static const _supportedIntents = [
    'PlayMusic',
    'AddToPlaylist',
    'GetWeather',
    'BookRestaurant',
    'RateBook',
    'SearchCreativeWork',
    'SearchScreeningEvent',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.block_rounded,
                    color: scheme.onErrorContainer,
                    size: 30,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'UNSUPPORTED COMMAND',
                          style: TextStyle(
                            color: scheme.onErrorContainer,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Outside the supported command domain',
                          style: TextStyle(
                            color: scheme.onErrorContainer,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            Text(
              reason,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
            ),
            if (predictedIntent != null) ...[
              const SizedBox(height: 15),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.psychology_alt_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Raw model guess: $predictedIntent',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (confidence != null)
                      Text(
                        '${(confidence! * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 17),
            const Text(
              'SUPPORTED OFFICIAL INTENTS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: _supportedIntents.map((intent) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    intent,
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeroChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SlmResultCard extends StatelessWidget {
  final NluResult result;

  const _SlmResultCard({required this.result});

  static const List<String> _allIntents = [
    'PlayMusic',
    'AddToPlaylist',
    'GetWeather',
    'BookRestaurant',
    'RateBook',
    'SearchCreativeWork',
    'SearchScreeningEvent',
  ];

  IconData _iconForIntent(String intent) {
    switch (intent) {
      case 'PlayMusic':
        return Icons.music_note_rounded;
      case 'AddToPlaylist':
        return Icons.playlist_add_rounded;
      case 'GetWeather':
        return Icons.cloud_rounded;
      case 'BookRestaurant':
        return Icons.restaurant_rounded;
      case 'RateBook':
        return Icons.star_rounded;
      case 'SearchCreativeWork':
        return Icons.search_rounded;
      case 'SearchScreeningEvent':
        return Icons.movie_filter_rounded;
      default:
        return Icons.psychology_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final payload = result.toJson();

    final json = const JsonEncoder.withIndent('  ').convert(payload);

    final rawSlots = payload['slots'];

    final slots = <String, dynamic>{};

    if (rawSlots is Map) {
      for (final entry in rawSlots.entries) {
        slots[entry.key.toString()] = entry.value;
      }
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            //
            // PREDICTED INTENT HERO
            //
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      _iconForIntent(result.intent),
                      color: scheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DETECTED INTENT',
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          result.intent,
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.check_circle_rounded,
                    size: 30,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            //
            // ALL 7 INTENTS WITH LIVE HIGHLIGHT
            //
            const Text(
              'SUPPORTED INTENTS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),

            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allIntents.map((intent) {
                return _IntentPill(
                  label: intent,
                  selected: intent == result.intent,
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            //
            // METRICS
            //
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    icon: Icons.verified_rounded,
                    label: 'Confidence',
                    value: '${(result.confidence * 100).toStringAsFixed(2)}%',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    icon: Icons.speed_rounded,
                    label: 'SLM latency',
                    value: '${result.latencyMs.toStringAsFixed(1)} ms',
                  ),
                ),
              ],
            ),

            //
            // EXTRACTED SLOTS
            //
            if (slots.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'EXTRACTED SLOTS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: slots.entries.map((entry) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: scheme.onSecondaryContainer,
                          fontSize: 12,
                        ),
                        children: [
                          TextSpan(
                            text: '${entry.key}: ',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          TextSpan(
                            text: entry.value.toString(),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 20),

            //
            // STRUCTURED OUTPUT
            //
            const Text(
              'STRUCTURED JSON',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),

            const SizedBox(height: 10),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
              ),
              child: SelectableText(
                json,
                style: const TextStyle(fontFamily: 'monospace', height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntentPill extends StatelessWidget {
  final String label;
  final bool selected;

  const _IntentPill({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected) ...[
            Icon(Icons.check_rounded, size: 15, color: scheme.onPrimary),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: scheme.primary),
          const SizedBox(height: 9),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
