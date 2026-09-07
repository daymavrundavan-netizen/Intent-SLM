import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

class VoiceTranscript {
  final String text;
  final double transcriptionMs;
  final double peakDb;
  final int audioBytes;

  const VoiceTranscript({
    required this.text,
    required this.transcriptionMs,
    required this.peakDb,
    required this.audioBytes,
  });
}

class VoiceEngine {
  static const String _assetPath = 'assets/asr/whisper/ggml-base.en.bin';

  static const WhisperModel _model = WhisperModel.baseEn;

  //
  // Short vocabulary bias for command recognition.
  // Keep this concise to avoid over-biasing tiny Whisper.
  //
  static const String _commandPrompt =
      'music, song, album, artist, playlist, weather, forecast, '
      'restaurant, reservation, book, rate, stars, movie, '
      'screening, cinema, showtime, calculator, camera, '
      'browser, flashlight, torch';

  final WhisperController _whisper = WhisperController();

  final AudioRecorder _recorder = AudioRecorder();

  bool _initialized = false;
  bool _recording = false;

  String? _recordingPath;

  StreamSubscription<Amplitude>? _amplitudeSub;

  double _peakDb = -160.0;

  DateTime? _recordingStartedAt;

  bool get isRecording => _recording;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    final modelPath = await _whisper.getPath(_model);

    final modelFile = File(modelPath);

    await modelFile.parent.create(recursive: true);

    final asset = await rootBundle.load(_assetPath);

    final bytes = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );

    if (!await modelFile.exists() || await modelFile.length() != bytes.length) {
      await modelFile.writeAsBytes(bytes, flush: true);
    }

    debugPrint('Whisper model ready: $modelPath');

    _initialized = true;
  }

  Future<bool> startRecording({bool permissionAlreadyGranted = false}) async {
    await initialize();

    if (_recording) {
      return true;
    }

    if (!permissionAlreadyGranted) {
      final granted = await _recorder.hasPermission();

      if (!granted) {
        return false;
      }
    } else {
      debugPrint("VoiceEngine: using pre-granted microphone permission");
    }

    final wavSupported = await _recorder.isEncoderSupported(AudioEncoder.wav);

    if (!wavSupported) {
      throw StateError('WAV recording is not supported on this device.');
    }

    final tempDir = await getTemporaryDirectory();

    _recordingPath = '${tempDir.path}/cdac_command.wav';

    final file = File(_recordingPath!);

    if (await file.exists()) {
      await file.delete();
    }

    const config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,

      // Help speech capture on phones.
      autoGain: true,
      noiseSuppress: true,

      // Echo cancellation can reduce voice level
      // on some phones, so leave it OFF initially.
      echoCancel: false,
    );

    _recorder.setOnConfigChanged((effectiveConfig) {
      debugPrint(
        'Effective record config: '
        '$effectiveConfig',
      );
    });

    await _recorder.start(config, path: _recordingPath!);

    _peakDb = -160.0;

    await _amplitudeSub?.cancel();

    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amplitude) {
          if (amplitude.current > _peakDb) {
            _peakDb = amplitude.current;
          }

          debugPrint(
            'Mic dBFS: '
            '${amplitude.current.toStringAsFixed(1)}',
          );
        });

    _recordingStartedAt = DateTime.now();

    _recording = true;

    debugPrint(
      'Recording started: '
      '$_recordingPath',
    );

    return true;
  }

  Future<VoiceTranscript> stopAndTranscribe({
    void Function(int percent)? onProgress,
  }) async {
    if (!_recording) {
      throw StateError('No voice recording is active.');
    }

    //
    // Keep a very small speech tail before stopping.
    // This helps avoid clipping the final word of short commands.
    //
    await Future<void>.delayed(const Duration(milliseconds: 180));

    final path = await _recorder.stop();

    final elapsed = DateTime.now().difference(
      _recordingStartedAt ?? DateTime.now(),
    );

    _recording = false;

    await _amplitudeSub?.cancel();
    _amplitudeSub = null;

    final audioPath = path ?? _recordingPath;

    if (audioPath == null) {
      throw StateError('Recorder returned no audio.');
    }

    final audioFile = File(audioPath);

    if (!await audioFile.exists()) {
      throw StateError('Recorded WAV file does not exist.');
    }

    final audioBytes = await audioFile.length();

    debugPrint(
      'Recording duration: '
      '${elapsed.inMilliseconds} ms',
    );

    debugPrint('Recording bytes: $audioBytes');

    debugPrint(
      'Peak microphone level: '
      '${_peakDb.toStringAsFixed(1)} dBFS',
    );

    //
    // Reject obviously bad capture instead of
    // asking Whisper to hallucinate from silence.
    //
    if (elapsed.inMilliseconds < 700) {
      throw StateError(
        'Recording was too short. '
        'Hold Speak for at least 1 second.',
      );
    }

    if (audioBytes < 5000) {
      throw StateError(
        'Audio capture is too small. '
        'The microphone may not be recording.',
      );
    }

    //
    // Typical speech will normally peak well
    // above -50 dBFS. Keep this threshold loose.
    //
    if (_peakDb < -55.0) {
      throw StateError(
        'Microphone level is too low '
        '(${_peakDb.toStringAsFixed(1)} dBFS). '
        'Speak closer to the phone.',
      );
    }

    final stopwatch = Stopwatch()..start();

    final result = await _whisper.transcribe(
      model: _model,
      audioPath: audioPath,
      lang: 'en',

      //
      // Short vocabulary-only bias for command words.
      //
      initialPrompt: _commandPrompt,

      //
      // Each push-to-talk recording is independent.
      //
      noContext: true,

      //
      // Allow Whisper to expose non-speech annotations.
      // They are removed before sending text to the SLM.
      //
      suppressNonSpeechTokens: false,

      onProgress: onProgress,
    );

    stopwatch.stop();

    final rawText = result?.transcription.text.trim() ?? '';

    final text = _cleanTranscript(rawText);

    debugPrint('Whisper raw transcript: "$rawText"');

    debugPrint('Whisper clean transcript: "$text"');

    if (text.isEmpty) {
      throw StateError('No speech was recognized.');
    }

    return VoiceTranscript(
      text: text,
      transcriptionMs: stopwatch.elapsedMicroseconds / 1000.0,
      peakDb: _peakDb,
      audioBytes: audioBytes,
    );
  }

  String _cleanTranscript(String input) {
    var text = input;

    //
    // Remove Whisper non-speech annotations such as:
    //
    // [music]
    // [noise]
    // (background noise)
    //
    // This intentionally avoids complicated regular expressions.
    //
    text = _removeDelimitedAnnotation(text, '[', ']');

    text = _removeDelimitedAnnotation(text, '(', ')');

    //
    // Normalize whitespace without changing recognized words.
    //
    text = text
        .replaceAll('\\n', ' ')
        .replaceAll('\\r', ' ')
        .replaceAll('\\t', ' ');

    while (text.contains('  ')) {
      text = text.replaceAll('  ', ' ');
    }

    return text.trim();
  }

  String _removeDelimitedAnnotation(
    String input,
    String opening,
    String closing,
  ) {
    var text = input;

    while (true) {
      final start = text.indexOf(opening);

      if (start < 0) {
        break;
      }

      final end = text.indexOf(closing, start + opening.length);

      if (end < 0) {
        break;
      }

      text =
          '\${text.substring(0, start)} '
          '\${text.substring(end + closing.length)}';
    }

    return text;
  }

  Future<void> cancelRecording() async {
    if (_recording) {
      await _recorder.cancel();

      _recording = false;
    }

    await _amplitudeSub?.cancel();

    _amplitudeSub = null;
  }

  Future<void> dispose() async {
    if (_recording) {
      await _recorder.stop();
    }

    await _amplitudeSub?.cancel();

    await _recorder.dispose();
  }
}
