import 'package:flutter/material.dart';

class ProjectLabPage extends StatelessWidget {
  const ProjectLabPage({super.key});

  static const _intentNames = <String>[
    'PlayMusic',
    'AddToPlaylist',
    'GetWeather',
    'BookRestaurant',
    'RateBook',
    'SearchCreativeWork',
    'SearchScreeningEvent',
  ];

  static const _intentExamples = <String>[
    'Play a song by Adele',
    'Add this track to my workout playlist',
    'What is the weather in Mumbai tomorrow?',
    'Book an Italian restaurant for four tonight',
    'Rate the book Sapiens five stars',
    'Find the movie Interstellar',
    'Find a screening of Dune tonight',
  ];

  static const _intentIcons = <IconData>[
    Icons.music_note_rounded,
    Icons.playlist_add_rounded,
    Icons.cloud_rounded,
    Icons.restaurant_rounded,
    Icons.star_rounded,
    Icons.search_rounded,
    Icons.movie_filter_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            //
            // HERO
            //
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primaryContainer, scheme.secondaryContainer],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(
                          Icons.science_rounded,
                          color: scheme.onPrimary,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'C-DAC PROJECT LAB',
                              style: TextStyle(
                                color: scheme.onPrimaryContainer,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Offline Command SLM',
                              style: TextStyle(
                                color: scheme.onPrimaryContainer,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'C-DAC AI Model Engineering Hackathon 2026 — '
                    'Track B: Small Language Model for Command Understanding.',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusChip(
                        icon: Icons.offline_bolt_rounded,
                        text: 'Fully On-Device',
                      ),
                      _StatusChip(
                        icon: Icons.lock_rounded,
                        text: 'Privacy First',
                      ),
                      _StatusChip(
                        icon: Icons.cloud_off_rounded,
                        text: 'Zero Cloud',
                      ),
                      _StatusChip(
                        icon: Icons.phone_android_rounded,
                        text: 'Android',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            //
            // HEADLINE METRICS
            //
            Text(
              'Final Champion Metrics',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),

            const SizedBox(height: 5),

            Text(
              'Frozen Champion V4 — deployable mask + BIO decoding.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),

            const SizedBox(height: 14),

            const _MetricGrid(
              metrics: [
                _MetricData('89.86%', 'Exact Frame', Icons.task_alt_rounded),
                _MetricData(
                  '98.43%',
                  'Intent Accuracy',
                  Icons.center_focus_strong_rounded,
                ),
                _MetricData('95.62%', 'Slot F1', Icons.label_rounded),
                _MetricData('32.55 MB', 'INT8 NLU', Icons.memory_rounded),
                _MetricData('~58 ms', 'SLM Latency', Icons.speed_rounded),
                _MetricData(
                  '7',
                  'Official Intents',
                  Icons.account_tree_rounded,
                ),
              ],
            ),

            const SizedBox(height: 18),

            _HighlightCard(
              icon: Icons.phone_android_rounded,
              title: 'Latency measured on target hardware',
              text:
                  '~58 ms is physical Android SLM inference latency. '
                  'It is not a laptop benchmark and it is not Whisper ASR latency. '
                  '58 ms = approximately 0.058 seconds.',
            ),

            const SizedBox(height: 18),

            //
            // PROJECT OVERVIEW
            //
            _ProjectSection(
              icon: Icons.info_rounded,
              title: '1. Project Overview',
              children: [
                const _BodyText(
                  'A fully on-device Android assistant that converts '
                  'natural-language commands into structured intent-and-slot '
                  'representations using a compact Small Language Model.',
                ),
                const SizedBox(height: 12),
                const _PipelineBox(
                  lines: [
                    'Text / Voice',
                    '↓',
                    'Local Processing',
                    '↓',
                    'Command Router',
                    '↙                     ↘',
                    'Official SLM          Device Skills',
                    '↓                     ↓',
                    'Intent + Slots         Android Actions',
                    '↓',
                    'Structured JSON',
                  ],
                ),
                const SizedBox(height: 12),
                const _Bullet(
                  'Benchmark command understanding is isolated from product-specific device actions.',
                ),
                const _Bullet('Core NLU inference requires no cloud service.'),
                const _Bullet(
                  'Designed for mobile deployment rather than desktop-only demonstration.',
                ),
              ],
            ),

            //
            // TASK
            //
            _ProjectSection(
              icon: Icons.assignment_rounded,
              title: '2. Competition Task',
              children: const [
                _BodyText(
                  'Input: a natural-language command. '
                  'Output: a structured representation containing the '
                  'predicted intent and extracted slot values.',
                ),
                SizedBox(height: 12),
                _PipelineBox(
                  lines: [
                    'Natural-Language Command',
                    '↓',
                    'Intent Classification',
                    '+',
                    'Slot Extraction',
                    '↓',
                    'Structured JSON',
                  ],
                ),
              ],
            ),

            //
            // INTENTS
            //
            _ProjectSection(
              icon: Icons.category_rounded,
              title: '3. Seven Official Benchmark Intents',
              children: [
                for (var i = 0; i < _intentNames.length; i++) ...[
                  _IntentInfoCard(
                    icon: _intentIcons[i],
                    intent: _intentNames[i],
                    example: _intentExamples[i],
                  ),
                  if (i != _intentNames.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),

            //
            // MODEL PROVENANCE
            //
            _ProjectSection(
              icon: Icons.psychology_rounded,
              title: '4. Model Provenance — What We Built',
              children: const [
                _BodyText(
                  'The language backbone was not trained from scratch. '
                  'The system uses a pretrained 12-layer MiniLM encoder '
                  'and performs task-specific fine-tuning for the C-DAC '
                  'command-understanding problem.',
                ),
                SizedBox(height: 14),
                _Subheading('Our model engineering'),
                _Bullet('Task-specific MiniLM fine-tuning'),
                _Bullet('Intent classification head'),
                _Bullet('Slot classification head'),
                _Bullet('Learned intent context injected into token features'),
                _Bullet('Intent-slot compatibility constraints'),
                _Bullet('BIO-constrained Viterbi decoding'),
                _Bullet('Targeted augmentation'),
                _Bullet('ONNX export and INT8 quantization'),
                _Bullet('Android tokenizer alignment'),
                _Bullet('Character-span slot reconstruction'),
                _Bullet('Fully on-device deployment pipeline'),
                SizedBox(height: 10),
                _Callout(
                  'Accurate description: custom fine-tuned Small Language '
                  'Model based on a pretrained MiniLM backbone.',
                ),
              ],
            ),

            //
            // ARCHITECTURE
            //
            _ProjectSection(
              icon: Icons.schema_rounded,
              title: '5. SLM Architecture',
              children: const [
                _PipelineBox(
                  lines: [
                    'Input Utterance',
                    '↓',
                    'WordPiece Tokenizer',
                    '↓',
                    'Fixed Sequence Length: 48',
                    '↓',
                    '12-Layer MiniLM Encoder',
                    '↓',
                    'Intent Classification Head',
                    '↓',
                    'Learned Intent Context',
                    '↓',
                    'Token Representations',
                    '↓',
                    'Slot Classification Head',
                    '↓',
                    'Intent-Slot Compatibility Mask',
                    '↓',
                    'BIO-Constrained Viterbi Decoder',
                    '↓',
                    'Intent + Slots',
                    '↓',
                    'Structured JSON',
                  ],
                ),
              ],
            ),

            //
            // DATASET + TRAINING
            //
            _ProjectSection(
              icon: Icons.storage_rounded,
              title: '6. Dataset & Training',
              children: const [
                _InfoRow(label: 'Dataset', value: 'SNIPS'),
                _InfoRow(label: 'Approx. utterances', value: '~14,000'),
                _InfoRow(label: 'Task', value: 'Joint intent + slot learning'),
                _InfoRow(label: 'Official intents', value: '7'),
                _InfoRow(label: 'Sequence length', value: '48 tokens'),
                SizedBox(height: 12),
                _Subheading('Training strategy'),
                _Bullet(
                  'Fine-tuned pretrained MiniLM representations on command-understanding examples.',
                ),
                _Bullet(
                  'Optimized intent classification and token-level slot prediction.',
                ),
                _Bullet(
                  'Added targeted augmentation for difficult intent/slot patterns.',
                ),
                _Bullet(
                  'Used validation data for model selection before final test evaluation.',
                ),
              ],
            ),

            //
            // DECODING
            //
            _ProjectSection(
              icon: Icons.route_rounded,
              title: '7. Structured Decoding',
              children: const [
                _BodyText(
                  'The final deployed system does not simply take independent '
                  'argmax predictions. It adds structural constraints to improve '
                  'command-frame consistency.',
                ),
                SizedBox(height: 12),
                _Subheading('Intent-slot compatibility mask'),
                _BodyText(
                  'Slot labels that are incompatible with the predicted intent '
                  'are masked before final decoding.',
                ),
                SizedBox(height: 10),
                _Subheading('BIO-constrained Viterbi'),
                _BodyText(
                  'A constrained Viterbi decoder enforces valid BIO transitions '
                  'and avoids structurally invalid slot sequences.',
                ),
                SizedBox(height: 12),
                _Callout(
                  'Raw exact-frame accuracy: 89.00% → '
                  'deployable constrained exact-frame accuracy: 89.86%.',
                ),
              ],
            ),

            //
            // EVALUATION
            //
            _ProjectSection(
              icon: Icons.analytics_rounded,
              title: '8. Evaluation & Model Freeze',
              children: const [
                _InfoRow(label: 'Intent accuracy', value: '98.43%'),
                _InfoRow(label: 'Slot F1', value: '95.62%'),
                _InfoRow(label: 'Raw exact frame', value: '89.00%'),
                _InfoRow(label: 'Deployable exact frame', value: '89.86%'),
                _InfoRow(label: 'Validation exact frame', value: '90.29%'),
                SizedBox(height: 12),
                _Subheading('Exact frame accuracy'),
                _BodyText(
                  'An example is counted as fully correct only when the intent '
                  'and the complete slot structure are correct.',
                ),
                SizedBox(height: 12),
                _Subheading('Test-set discipline'),
                _Bullet(
                  'Final champion evaluated on the untouched test set once.',
                ),
                _Bullet('No post-test model tuning.'),
                _Bullet(
                  'Champion V4 is frozen for the competition submission.',
                ),
              ],
            ),

            //
            // OPTIMIZATION
            //
            _ProjectSection(
              icon: Icons.memory_rounded,
              title: '9. Mobile Optimization & Deployment',
              children: const [
                _InfoRow(label: 'Export format', value: 'ONNX'),
                _InfoRow(label: 'Quantization', value: 'INT8'),
                _InfoRow(label: 'NLU model size', value: '32.55 MB'),
                _InfoRow(label: 'Runtime', value: 'ONNX Runtime'),
                _InfoRow(label: 'Target', value: 'Android / ARM64'),
                _InfoRow(label: 'Max sequence', value: '48'),
                SizedBox(height: 12),
                _Subheading('Model inputs'),
                _Bullet('input_ids'),
                _Bullet('attention_mask'),
                _Bullet('token_type_ids'),
                SizedBox(height: 8),
                _Subheading('Model outputs'),
                _Bullet('intent_logits'),
                _Bullet('slot_logits'),
              ],
            ),

            //
            // PERFORMANCE
            //
            _ProjectSection(
              icon: Icons.speed_rounded,
              title: '10. Performance & Latency',
              children: const [
                _InfoRow(
                  label: 'Physical Android SLM latency',
                  value: '~58 ms',
                ),
                _InfoRow(label: 'Equivalent time', value: '~0.058 s'),
                _InfoRow(label: 'Cloud round-trip', value: 'None'),
                SizedBox(height: 12),
                _Callout(
                  'SLM inference latency and speech-recognition latency are '
                  'different measurements and must not be compared as if they '
                  'were the same stage.',
                ),
                SizedBox(height: 12),
                _PipelineBox(
                  lines: [
                    'Voice End-to-End',
                    'Speech Duration',
                    '+',
                    'Whisper ASR',
                    '+',
                    'SLM (~58 ms)',
                    '+',
                    'Local Action',
                  ],
                ),
              ],
            ),

            //
            // VOICE
            //
            _ProjectSection(
              icon: Icons.mic_rounded,
              title: '11. Offline Voice Pipeline',
              children: const [
                _PipelineBox(
                  lines: [
                    'Microphone',
                    '↓',
                    '16 kHz Mono WAV',
                    '↓',
                    'Whisper Tiny.en',
                    '↓',
                    'Transcript',
                    '↓',
                    'Local Command Router',
                    '↓',
                    'SLM / Device Skill',
                  ],
                ),
                SizedBox(height: 12),
                _BodyText(
                  'Whisper is a pretrained speech-recognition component. '
                  'It is separate from the benchmark MiniLM-based command SLM.',
                ),
              ],
            ),

            //
            // PRODUCT ARCHITECTURE
            //
            _ProjectSection(
              icon: Icons.account_tree_rounded,
              title: '12. Benchmark SLM vs Product Skills',
              children: const [
                _PipelineBox(
                  lines: [
                    'User Command',
                    '↓',
                    'Local Command Router',
                    '↙                         ↘',
                    'Benchmark SLM             Device Skills',
                    '↓                         ↓',
                    '7 Official Intents         Calculator',
                    'Intent + Slots             Camera',
                    '↓                          Browser',
                    'Structured JSON            Flashlight',
                  ],
                ),
                SizedBox(height: 14),
                _Callout(
                  'The benchmark NLU model is immutable and handles the seven '
                  'official command-understanding intents. Product-specific '
                  'capabilities are isolated in a separate action-routing layer, '
                  'so adding phone functionality does not require modifying or '
                  'risking the benchmark model.',
                ),
              ],
            ),

            //
            // DEVICE SKILLS
            //
            _ProjectSection(
              icon: Icons.devices_rounded,
              title: '13. Device Skills',
              children: const [
                _FeatureTile(
                  icon: Icons.calculate_rounded,
                  title: 'Calculator',
                  subtitle:
                      'Launch and deterministic calculator skill routing.',
                ),
                _FeatureTile(
                  icon: Icons.camera_alt_rounded,
                  title: 'Camera',
                  subtitle: 'Launches the native camera experience.',
                ),
                _FeatureTile(
                  icon: Icons.language_rounded,
                  title: 'Browser',
                  subtitle: 'Local Android browser action.',
                ),
                _FeatureTile(
                  icon: Icons.flashlight_on_rounded,
                  title: 'Flashlight',
                  subtitle: 'Local torch control.',
                ),
              ],
            ),

            //
            // EDGE AGENT
            //
            _ProjectSection(
              icon: Icons.auto_awesome_rounded,
              title: '14. C-DAC Edge Agent',
              children: const [
                _BodyText(
                  'A persistent, context-aware, fully on-device Android agent '
                  'interface designed to remain available above other applications.',
                ),
                SizedBox(height: 12),
                _Bullet('Floating Android overlay'),
                _Bullet('Push-to-talk interaction design'),
                _Bullet('Persistent lightweight context'),
                _Bullet('Local calculator context'),
                _Bullet('Local deterministic actions'),
                _Bullet('Foreground-service integration'),
                SizedBox(height: 12),
                _PipelineBox(
                  lines: [
                    'Calculate 2 plus 3',
                    '→ 5',
                    '',
                    'Multiply that by 10',
                    '→ 50',
                  ],
                ),
              ],
            ),

            //
            // PRIVACY
            //
            _ProjectSection(
              icon: Icons.shield_rounded,
              title: '15. Offline Operation & Privacy',
              children: const [
                _InfoRow(label: 'Cloud API', value: 'None'),
                _InfoRow(label: 'NLU inference', value: 'On device'),
                _InfoRow(label: 'Voice ASR', value: 'On device'),
                _InfoRow(label: 'Command upload required', value: 'No'),
                _InfoRow(label: 'Device actions', value: 'Local'),
                SizedBox(height: 12),
                _Callout(
                  'Core command understanding can be demonstrated in airplane mode.',
                ),
              ],
            ),

            //
            // ANDROID ENGINEERING
            //
            _ProjectSection(
              icon: Icons.android_rounded,
              title: '16. Android Engineering',
              children: const [
                _InfoRow(label: 'Framework', value: 'Flutter'),
                _InfoRow(label: 'Language', value: 'Dart / Kotlin'),
                _InfoRow(label: 'Target device OS', value: 'Android 16'),
                _InfoRow(label: 'Target API', value: 'API 36'),
                _InfoRow(label: 'Device architecture', value: 'ARM64'),
                SizedBox(height: 12),
                _Bullet('ONNX Runtime mobile inference'),
                _Bullet('Offline Whisper integration'),
                _Bullet('Android foreground service'),
                _Bullet('Floating overlay'),
                _Bullet('Native Android intents'),
                _Bullet('Torch control'),
                _Bullet('Physical-device profiling and validation'),
              ],
            ),

            //
            // TESTING
            //
            _ProjectSection(
              icon: Icons.fact_check_rounded,
              title: '17. Testing & Validation',
              children: const [
                _InfoRow(
                  label: 'Flutter static analysis',
                  value: 'No issues found',
                ),
                _InfoRow(label: 'Physical Android testing', value: 'Completed'),
                _InfoRow(
                  label: 'Held-out benchmark test',
                  value: 'Evaluated once',
                ),
                _InfoRow(
                  label: 'Automated Flutter unit tests',
                  value: 'Not currently included',
                ),
                SizedBox(height: 12),
                _BodyText(
                  'The final Android workflow is validated primarily through '
                  'physical-device functional testing and frozen benchmark metrics.',
                ),
              ],
            ),

            //
            // MODEL IDENTITY
            //
            _ProjectSection(
              icon: Icons.fingerprint_rounded,
              title: '18. Frozen Champion Identity',
              children: const [
                _InfoRow(label: 'Champion', value: 'Champion V4'),
                _InfoRow(
                  label: 'Model artifact SHA-256',
                  value:
                      'c0abb44a8750a30ce6ca2e5e66f510e809f7fc892c60a1b9e1eb2fab01fa86ee',
                  selectable: true,
                ),
                SizedBox(height: 12),
                _Callout(
                  'ML is frozen. The untouched test set is not used for further tuning.',
                ),
              ],
            ),

            //
            // LIMITATIONS
            //
            _ProjectSection(
              icon: Icons.warning_amber_rounded,
              title: '19. Current Limitations',
              children: const [
                _Bullet(
                  'Background overlay ASR reliability can vary across Android OEMs.',
                ),
                _Bullet(
                  'Modern Android versions impose strict background microphone rules.',
                ),
                _Bullet(
                  'Device skills are intentionally limited rather than trying to control every phone function.',
                ),
                _Bullet('Current Whisper model is English-focused.'),
                _Bullet(
                  'Agent conversational context is lightweight and local.',
                ),
              ],
            ),

            //
            // FUTURE SCOPE
            //
            _ProjectSection(
              icon: Icons.rocket_launch_rounded,
              title: '20. Future Scope',
              children: const [
                _Bullet('Robust cross-OEM background voice capture'),
                _Bullet('Multilingual and Indian-language support'),
                _Bullet('Agent-owned CameraX skill'),
                _Bullet('Additional deterministic device skills'),
                _Bullet('Longer multi-turn context'),
                _Bullet('NPU / hardware-accelerated inference'),
                _Bullet('Further model quantization and compression'),
                _Bullet('Smaller/faster speech-recognition models'),
                _Bullet('Additional mobile performance optimization'),
              ],
            ),

            //
            // JUDGING NARRATIVE
            //
            _ProjectSection(
              icon: Icons.campaign_rounded,
              title: '21. Competition Positioning',
              initiallyExpanded: true,
              children: const [
                _Callout(
                  '89.86% exact command-frame accuracy, 32.55 MB NLU model, '
                  '~58 ms on a real Android phone, zero cloud dependency.',
                ),
                SizedBox(height: 12),
                _BodyText(
                  'The project demonstrates not only benchmark accuracy but also '
                  'a complete deployment path: tokenizer alignment, constrained '
                  'decoding, INT8 ONNX export, Android inference, offline voice, '
                  'device actions, and an Edge Agent product layer.',
                ),
              ],
            ),

            //
            // BUILD INFO
            //
            _ProjectSection(
              icon: Icons.build_circle_rounded,
              title: '22. Release & Build Information',
              children: const [
                _InfoRow(label: 'Flutter', value: '3.44.9'),
                _InfoRow(label: 'Dart', value: '3.12.2'),
                _InfoRow(label: 'Runtime', value: 'ONNX Runtime'),
                _InfoRow(label: 'Model precision', value: 'INT8'),
                _InfoRow(label: 'NLU size', value: '32.55 MB'),
                _InfoRow(label: 'Universal release APK', value: '~261 MiB'),
                _InfoRow(
                  label: 'Release APK SHA-256',
                  value:
                      'c6f77a14245c1bb2e45365ccb529e7f1bb95675c6ad85109cf9bbdae1ded35bf',
                  selectable: true,
                ),
              ],
            ),

            const SizedBox(height: 12),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.offline_bolt_rounded,
                    color: scheme.primary,
                    size: 34,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'C-DAC Offline AI Assistant',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Small. Fast. Private. On Device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  const _ProjectSection({
    required this.icon,
    required this.title,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: scheme.primary, size: 21),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          children: [
            Divider(color: scheme.outlineVariant),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _MetricData {
  final String value;
  final String label;
  final IconData icon;

  const _MetricData(this.value, this.label, this.icon);
}

class _MetricGrid extends StatelessWidget {
  final List<_MetricData> metrics;

  const _MetricGrid({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        //
        // Flutter can briefly provide zero-width constraints
        // during the first layout pass on some Android devices.
        // Never derive a negative child width from that state.
        //
        final availableWidth = constraints.maxWidth;

        if (!availableWidth.isFinite || availableWidth <= 0) {
          return const SizedBox.shrink();
        }

        final twoColumns = availableWidth >= 280;

        final width = twoColumns ? (availableWidth - 10) / 2 : availableWidth;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: metrics.map((metric) {
            return SizedBox(
              width: width,
              child: _MetricTile(metric: metric),
            );
          }).toList(),
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  final _MetricData metric;

  const _MetricTile({required this.metric});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(metric.icon, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            metric.value,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            metric.label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _StatusChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.82),
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

class _IntentInfoCard extends StatelessWidget {
  final IconData icon;
  final String intent;
  final String example;

  const _IntentInfoCard({
    required this.icon,
    required this.intent,
    required this.example,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  intent,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '"$example"',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _HighlightCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: TextStyle(
                    color: scheme.onTertiaryContainer,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool selectable;

  const _InfoRow({
    required this.label,
    required this.value,
    this.selectable = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 5,
            child: selectable
                ? SelectableText(
                    value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  )
                : Text(
                    value,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PipelineBox extends StatelessWidget {
  final List<String> lines;

  const _PipelineBox({required this.lines});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: SelectableText(
        lines.join('\n'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          height: 1.45,
        ),
      ),
    );
  }
}

class _BodyText extends StatelessWidget {
  final String text;

  const _BodyText(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
      ),
    );
  }
}

class _Subheading extends StatelessWidget {
  final String text;

  const _Subheading(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;

  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, size: 17, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  final String text;

  const _Callout(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w800,
          height: 1.45,
        ),
      ),
    );
  }
}
