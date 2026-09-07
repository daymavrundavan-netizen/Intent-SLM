import 'dart:convert';

import 'package:flutter/material.dart';

import 'action_dispatcher.dart';
import 'action_router.dart';

class DeviceActionPage extends StatefulWidget {
  final DeviceCommand command;

  const DeviceActionPage({super.key, required this.command});

  @override
  State<DeviceActionPage> createState() => _DeviceActionPageState();
}

class _DeviceActionPageState extends State<DeviceActionPage> {
  final DeviceActionDispatcher _dispatcher = DeviceActionDispatcher();

  bool _running = true;

  bool _success = false;

  String _status = 'Preparing device action...';

  bool? _torchEnabled;

  @override
  void initState() {
    super.initState();

    if (widget.command.action == DeviceActionType.flashlight) {
      _torchEnabled = widget.command.arguments['enabled'] as bool? ?? false;
    }

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _execute(widget.command),
    );
  }

  IconData get _icon {
    switch (widget.command.action) {
      case DeviceActionType.openCamera:
        return Icons.camera_alt_rounded;

      case DeviceActionType.openCalculator:
        return Icons.calculate_rounded;

      case DeviceActionType.openBrowser:
        return Icons.language_rounded;

      case DeviceActionType.flashlight:
        return _torchEnabled == true
            ? Icons.flashlight_on_rounded
            : Icons.flashlight_off_rounded;

      case DeviceActionType.playMusic:
        return Icons.play_circle_fill_rounded;
    }
  }

  String get _title {
    switch (widget.command.action) {
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

  Future<void> _execute(DeviceCommand command) async {
    if (mounted) {
      setState(() {
        _running = true;
        _success = false;
        _status = 'Executing locally...';
      });
    }

    try {
      final result = await _dispatcher.execute(command);

      if (!mounted) {
        return;
      }

      setState(() {
        _running = false;
        _success = true;
        _status = result;

        if (command.action == DeviceActionType.flashlight) {
          _torchEnabled = command.arguments['enabled'] as bool?;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _running = false;
        _success = false;
        _status = error.toString();
      });
    }
  }

  Future<void> _setTorch(bool enabled) async {
    final command = DeviceCommand(
      action: DeviceActionType.flashlight,
      intent: 'Flashlight',
      slots: {'state': enabled ? 'on' : 'off'},
      arguments: {'enabled': enabled},
    );

    await _execute(command);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(widget.command.toJson());

    return Scaffold(
      appBar: AppBar(title: const Text('Device Action')),

      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),

          children: [
            Container(
              padding: const EdgeInsets.all(28),

              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primaryContainer, scheme.secondaryContainer],
                ),
                borderRadius: BorderRadius.circular(32),
              ),

              child: Column(
                children: [
                  Container(
                    width: 96,
                    height: 96,

                    decoration: BoxDecoration(
                      color: scheme.surface,
                      shape: BoxShape.circle,
                    ),

                    child: Icon(_icon, size: 46, color: scheme.primary),
                  ),

                  const SizedBox(height: 18),

                  Text(
                    _title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    'Executed directly on this Android device',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(20),

                child: Row(
                  children: [
                    if (_running)
                      const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    else
                      Icon(
                        _success
                            ? Icons.check_circle_rounded
                            : Icons.error_rounded,
                        size: 30,
                        color: _success ? scheme.primary : scheme.error,
                      ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _running
                                ? 'Working'
                                : _success
                                ? 'Completed'
                                : 'Action failed',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),

                          const SizedBox(height: 3),

                          Text(_status),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (widget.command.action == DeviceActionType.flashlight) ...[
              const SizedBox(height: 16),

              Card(
                elevation: 0,
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),

                  secondary: Icon(
                    _torchEnabled == true
                        ? Icons.flashlight_on_rounded
                        : Icons.flashlight_off_rounded,
                  ),

                  title: const Text(
                    'Flashlight',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),

                  subtitle: Text(
                    _torchEnabled == true ? 'Torch is ON' : 'Torch is OFF',
                  ),

                  value: _torchEnabled ?? false,

                  onChanged: _running ? null : _setTorch,
                ),
              ),
            ],

            const SizedBox(height: 20),

            Text(
              'Resolved command',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(18),

              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),

              child: SelectableText(
                json,
                style: const TextStyle(fontFamily: 'monospace', height: 1.5),
              ),
            ),

            const SizedBox(height: 24),

            OutlinedButton.icon(
              onPressed: _running ? null : () => _execute(widget.command),

              icon: const Icon(Icons.refresh_rounded),

              label: const Text('Run again'),
            ),
          ],
        ),
      ),
    );
  }
}
