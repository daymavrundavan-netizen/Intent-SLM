import 'dart:convert';
import 'dart:math';

import 'package:dart_bert_tokenizer/dart_bert_tokenizer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

class NluResult {
  final String intent;
  final double confidence;
  final Map<String, String> slots;
  final double latencyMs;

  const NluResult({
    required this.intent,
    required this.confidence,
    required this.slots,
    required this.latencyMs,
  });

  Map<String, dynamic> toJson() {
    return {'intent': intent, 'slots': slots};
  }
}

class _WordSpan {
  final int start;
  final int end;

  const _WordSpan(this.start, this.end);
}

class _PreparedInput {
  final Int64List inputIds;
  final Int64List attentionMask;
  final Int64List tokenTypeIds;

  final List<int> firstPieceIndexes;
  final List<_WordSpan> wordSpans;

  const _PreparedInput({
    required this.inputIds,
    required this.attentionMask,
    required this.tokenTypeIds,
    required this.firstPieceIndexes,
    required this.wordSpans,
  });
}

class NluEngine {
  static const String _modelAsset = 'assets/models/command_slm_int8.onnx';

  late final OrtSession _session;
  late final WordPieceTokenizer _tokenizer;

  late final Map<String, String> _id2Intent;
  late final Map<String, String> _id2Slot;

  late final Map<String, Set<int>> _intentAllowedSlotIds;

  int _maxLength = 48;
  int _numSlots = 0;

  bool _initialized = false;

  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await _loadConfiguration();
    await _loadTokenizer();

    final runtime = OnnxRuntime();

    _session = await runtime.createSessionFromAsset(_modelAsset);

    _initialized = true;

    debugPrint('======================================');
    debugPrint('CDAC OFFLINE COMMAND SLM READY');
    debugPrint('Model      : INT8 ONNX');
    debugPrint('Max length : $_maxLength');
    debugPrint('Intents    : ${_id2Intent.length}');
    debugPrint('Slot labels: $_numSlots');
    debugPrint('Inputs     : ${_session.inputNames}');
    debugPrint('Outputs    : ${_session.outputNames}');
    debugPrint('======================================');
  }

  Future<void> _loadConfiguration() async {
    final config =
        jsonDecode(
              await rootBundle.loadString('assets/config/model_config.json'),
            )
            as Map<String, dynamic>;

    _maxLength = (config['max_length'] as num).toInt();

    final intentJson =
        jsonDecode(await rootBundle.loadString('assets/config/id2intent.json'))
            as Map<String, dynamic>;

    _id2Intent = intentJson.map(
      (key, value) => MapEntry(key, value.toString()),
    );

    final slotJson =
        jsonDecode(await rootBundle.loadString('assets/config/id2slot.json'))
            as Map<String, dynamic>;

    _id2Slot = slotJson.map((key, value) => MapEntry(key, value.toString()));

    _numSlots = _id2Slot.length;

    final compatibilityJson =
        jsonDecode(
              await rootBundle.loadString(
                'assets/config/intent_slot_compat.json',
              ),
            )
            as Map<String, dynamic>;

    _intentAllowedSlotIds = {};

    for (final entry in compatibilityJson.entries) {
      final information = entry.value as Map<String, dynamic>;

      final allowed = information['allowed_ids'] as List<dynamic>;

      _intentAllowedSlotIds[entry.key] = allowed
          .map((value) => (value as num).toInt())
          .toSet();
    }
  }

  Future<void> _loadTokenizer() async {
    final rawVocab = await rootBundle.loadString('assets/tokenizer/vocab.txt');

    final tokens = rawVocab.split(RegExp(r'\r?\n')).toList();

    if (tokens.isNotEmpty && tokens.last.isEmpty) {
      tokens.removeLast();
    }

    final vocabulary = Vocabulary.fromTokens(tokens);

    _tokenizer = WordPieceTokenizer(
      vocab: vocabulary,
      config: const WordPieceConfig(
        lowercase: true,
        stripAccents: true,
        handleChineseChars: true,
        subwordPrefix: '##',
        maxWordLength: 200,
        addClsToken: true,
        addSepToken: true,
      ),
    );

    debugPrint(
      'Tokenizer vocab size: '
      '${_tokenizer.vocab.size}',
    );
  }

  _PreparedInput _prepareInput(String text) {
    final matches = RegExp(r'\S+').allMatches(text).toList();

    // Explicitly growable token-id list.
    final ids = <int>[_tokenizer.vocab.clsTokenId];

    final firstPieceIndexes = <int>[];
    final wordSpans = <_WordSpan>[];

    for (final match in matches) {
      final word = match.group(0)!;

      final encoding = _tokenizer.encode(word, addSpecialTokens: false);

      // Make an explicitly growable/copy-backed list.
      final pieces = List<int>.from(encoding.ids, growable: false);

      if (pieces.isEmpty) {
        continue;
      }

      // Reserve one position for [SEP].
      if (ids.length + pieces.length + 1 > _maxLength) {
        break;
      }

      firstPieceIndexes.add(ids.length);

      wordSpans.add(_WordSpan(match.start, match.end));

      ids.addAll(pieces);
    }

    ids.add(_tokenizer.vocab.sepTokenId);

    // Save the real sequence length BEFORE padding.
    final realLength = ids.length;

    // Only ids is extended here.
    while (ids.length < _maxLength) {
      ids.add(_tokenizer.vocab.padTokenId);
    }

    // Build final-size masks directly.
    // No .add() calls are used on these lists.
    final attentionMask = List<int>.generate(
      _maxLength,
      (index) => index < realLength ? 1 : 0,
      growable: false,
    );

    final tokenTypeIds = List<int>.filled(_maxLength, 0, growable: false);

    if (ids.length != _maxLength) {
      throw StateError('input_ids length ${ids.length} != $_maxLength');
    }

    if (attentionMask.length != _maxLength) {
      throw StateError(
        'attention_mask length ${attentionMask.length} != $_maxLength',
      );
    }

    if (tokenTypeIds.length != _maxLength) {
      throw StateError(
        'token_type_ids length ${tokenTypeIds.length} != $_maxLength',
      );
    }

    return _PreparedInput(
      inputIds: Int64List.fromList(ids),
      attentionMask: Int64List.fromList(attentionMask),
      tokenTypeIds: Int64List.fromList(tokenTypeIds),
      firstPieceIndexes: firstPieceIndexes,
      wordSpans: wordSpans,
    );
  }

  Future<NluResult> predict(String text) async {
    if (!_initialized) {
      throw StateError('NLU engine is not initialized.');
    }

    final cleanText = text.trim();

    if (cleanText.isEmpty) {
      throw ArgumentError('Command cannot be empty.');
    }

    final prepared = _prepareInput(cleanText);

    final inputIdsValue = await OrtValue.fromList(prepared.inputIds, [
      1,
      _maxLength,
    ]);

    final attentionMaskValue = await OrtValue.fromList(prepared.attentionMask, [
      1,
      _maxLength,
    ]);

    final tokenTypeIdsValue = await OrtValue.fromList(prepared.tokenTypeIds, [
      1,
      _maxLength,
    ]);

    final inputs = <String, OrtValue>{
      'input_ids': inputIdsValue,

      'attention_mask': attentionMaskValue,

      'token_type_ids': tokenTypeIdsValue,
    };

    Map<String, OrtValue>? outputs;

    final stopwatch = Stopwatch()..start();

    try {
      outputs = await _session.run(inputs);
    } finally {
      stopwatch.stop();

      for (final value in inputs.values) {
        await value.dispose();
      }
    }

    try {
      final rawIntent = await outputs['intent_logits']!.asFlattenedList();

      final intentLogits = rawIntent
          .map((value) => (value as num).toDouble())
          .toList();

      final rawSlots = await outputs['slot_logits']!.asFlattenedList();

      final flatSlotLogits = rawSlots
          .map((value) => (value as num).toDouble())
          .toList();

      final intentId = _argmax(intentLogits);

      final intent = _id2Intent[intentId.toString()] ?? 'UNKNOWN';

      final confidence = _softmaxProbability(intentLogits, intentId);

      //
      // ONNX slot output shape:
      //
      // [1, 48, 72]
      //
      // Extract only the first WordPiece
      // for each original word, exactly as
      // evaluation does.
      //
      final wordLogits = <List<double>>[];

      for (final tokenIndex in prepared.firstPieceIndexes) {
        final start = tokenIndex * _numSlots;

        final end = start + _numSlots;

        wordLogits.add(flatSlotLogits.sublist(start, end));
      }

      final allowedIds =
          _intentAllowedSlotIds[intent] ??
          {for (int i = 0; i < _numSlots; i++) i};

      final decodedSlotIds = _viterbiDecode(wordLogits, allowedIds);

      final labels = decodedSlotIds
          .map((id) => _id2Slot[id.toString()] ?? 'O')
          .toList();

      final slots = _decodeSlotValues(cleanText, prepared.wordSpans, labels);

      return NluResult(
        intent: intent,
        confidence: confidence,
        slots: slots,
        latencyMs: stopwatch.elapsedMicroseconds / 1000.0,
      );
    } finally {
      for (final value in outputs.values) {
        await value.dispose();
      }
    }
  }

  int _argmax(List<double> values) {
    int bestIndex = 0;

    double bestValue = double.negativeInfinity;

    for (int i = 0; i < values.length; i++) {
      if (values[i] > bestValue) {
        bestValue = values[i];
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  double _softmaxProbability(List<double> logits, int index) {
    final maximum = logits.reduce(max);

    double denominator = 0;

    for (final value in logits) {
      denominator += exp(value - maximum);
    }

    return exp(logits[index] - maximum) / denominator;
  }

  (String, String?) _parseBioLabel(String label) {
    if (label == 'O') {
      return ('O', null);
    }

    final dash = label.indexOf('-');

    if (dash < 0) {
      return (label, null);
    }

    return (label.substring(0, dash), label.substring(dash + 1));
  }

  bool _legalStart(String label) {
    final (prefix, _) = _parseBioLabel(label);

    return (prefix == 'O' || prefix == 'B');
  }

  bool _legalTransition(String previous, String current) {
    final (currentPrefix, currentType) = _parseBioLabel(current);

    if (currentPrefix == 'O' || currentPrefix == 'B') {
      return true;
    }

    if (currentPrefix != 'I') {
      return false;
    }

    final (previousPrefix, previousType) = _parseBioLabel(previous);

    return ((previousPrefix == 'B' || previousPrefix == 'I') &&
        previousType == currentType);
  }

  List<int> _viterbiDecode(List<List<double>> logits, Set<int> allowedIds) {
    if (logits.isEmpty) {
      return [];
    }

    const negativeInfinity = -1e30;

    final steps = logits.length;

    final scores = List.generate(
      steps,
      (_) => List<double>.filled(_numSlots, negativeInfinity),
    );

    final backPointers = List.generate(
      steps,
      (_) => List<int>.filled(_numSlots, 0),
    );

    //
    // First word.
    //
    for (int current = 0; current < _numSlots; current++) {
      if (!allowedIds.contains(current)) {
        continue;
      }

      final label = _id2Slot[current.toString()]!;

      if (_legalStart(label)) {
        scores[0][current] = logits[0][current];
      }
    }

    //
    // Dynamic programming.
    //
    for (int t = 1; t < steps; t++) {
      for (int current = 0; current < _numSlots; current++) {
        if (!allowedIds.contains(current)) {
          continue;
        }

        final currentLabel = _id2Slot[current.toString()]!;

        double bestScore = negativeInfinity;

        int bestPrevious = 0;

        for (int previous = 0; previous < _numSlots; previous++) {
          if (scores[t - 1][previous] <= negativeInfinity / 2) {
            continue;
          }

          final previousLabel = _id2Slot[previous.toString()]!;

          if (!_legalTransition(previousLabel, currentLabel)) {
            continue;
          }

          final candidate = scores[t - 1][previous] + logits[t][current];

          if (candidate > bestScore) {
            bestScore = candidate;
            bestPrevious = previous;
          }
        }

        scores[t][current] = bestScore;

        backPointers[t][current] = bestPrevious;
      }
    }

    int current = _argmax(scores.last);

    final result = List<int>.filled(steps, 0);

    result[steps - 1] = current;

    for (int t = steps - 1; t > 0; t--) {
      current = backPointers[t][current];

      result[t - 1] = current;
    }

    return result;
  }

  Map<String, String> _decodeSlotValues(
    String text,
    List<_WordSpan> spans,
    List<String> labels,
  ) {
    final result = <String, String>{};

    String? currentType;

    int? currentStart;
    int? currentEnd;

    void closeEntity() {
      if (currentType != null && currentStart != null && currentEnd != null) {
        final value = text.substring(currentStart!, currentEnd!).trim();

        if (value.isNotEmpty) {
          final existing = result[currentType!];

          if (existing == null) {
            result[currentType!] = value;
          } else {
            result[currentType!] = '$existing $value';
          }
        }
      }

      currentType = null;
      currentStart = null;
      currentEnd = null;
    }

    final count = min(spans.length, labels.length);

    for (int i = 0; i < count; i++) {
      final span = spans[i];

      final label = labels[i];

      if (label == 'O') {
        closeEntity();
        continue;
      }

      final (prefix, slotType) = _parseBioLabel(label);

      if (slotType == null) {
        closeEntity();
        continue;
      }

      if (prefix == 'B') {
        closeEntity();

        currentType = slotType;

        currentStart = span.start;

        currentEnd = span.end;
      } else if (prefix == 'I') {
        if (currentType == slotType) {
          currentEnd = span.end;
        } else {
          //
          // Defensive repair.
          //
          closeEntity();

          currentType = slotType;

          currentStart = span.start;

          currentEnd = span.end;
        }
      }
    }

    closeEntity();

    return result;
  }

  Future<void> close() async {
    if (_initialized) {
      await _session.close();
      _initialized = false;
    }
  }
}
