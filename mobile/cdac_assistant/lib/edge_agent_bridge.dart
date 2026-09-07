import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_screen_overlay/flutter_screen_overlay.dart';

import 'action_dispatcher.dart';
import 'action_router.dart';
import 'agent_context.dart';
import 'calculator_skill.dart';

class EdgeAgentBridge {
  final ActionRouter _router = ActionRouter();

  final DeviceActionDispatcher _dispatcher = DeviceActionDispatcher();

  final CalculatorSkill _calculator = CalculatorSkill();

  final AgentContext context = AgentContext();

  StreamSubscription<dynamic>? _subscription;

  void start() {
    _subscription ??= FlutterScreenOverlay.overlayListener.listen(
      _handleMessage,
      onError: (Object error) {
        debugPrint('EdgeAgentBridge error: $error');
      },
    );

    debugPrint('EDGE AGENT BRIDGE READY');
  }

  Future<void> _handleMessage(dynamic event) async {
    if (event is! Map) {
      return;
    }

    final type = event['type']?.toString();

    if (type != 'edge_command') {
      return;
    }

    final text = event['text']?.toString().trim();

    if (text == null || text.isEmpty) {
      return;
    }

    debugPrint('EDGE AGENT COMMAND: $text');

    context.observe(text);

    await _process(text);
  }

  Future<void> _process(String text) async {
    //
    // CALCULATOR SKILL
    //
    if (_calculator.canHandle(text, context)) {
      final result = _calculator.evaluate(text, context);

      if (result != null) {
        await _sendResult(
          title: 'Calculator',
          message: result.display,
          success: true,
          context: 'Turn ${context.turn}',
        );

        return;
      }

      await _sendResult(
        title: 'Calculator',
        message: 'I could not understand that calculation.',
        success: false,
      );

      return;
    }

    //
    // EXISTING DEVICE ROUTER
    //
    final device = _router.route(text);

    if (device != null) {
      _updateContext(device);

      try {
        final status = await _dispatcher.execute(device);

        await _sendResult(
          title: _titleFor(device),
          message: status,
          success: true,
          context: _contextLabel(),
        );
      } catch (error) {
        await _sendResult(
          title: 'Device action',
          message: error.toString(),
          success: false,
        );
      }

      return;
    }

    //
    // CAMERA FOLLOW-UP PLACEHOLDER.
    //
    // We will replace this with real
    // Camera Skill capture in the next step.
    //
    final normalized = text.toLowerCase();

    if (context.activeSkill == AgentSkill.camera &&
        (normalized.contains('take a photo') ||
            normalized.contains('take photo') ||
            normalized.contains('click photo') ||
            normalized.contains('capture'))) {
      await _sendResult(
        title: 'Camera',
        message: 'Camera context understood. Capture Skill is the next module.',
        success: false,
        context: 'Camera',
      );

      return;
    }

    await _sendResult(
      title: 'Edge Agent',
      message: 'Command not handled by an Agent Skill yet.',
      success: false,
      context: _contextLabel(),
    );
  }

  void _updateContext(DeviceCommand command) {
    switch (command.action) {
      case DeviceActionType.openCamera:
        context.setSkill(AgentSkill.camera);
        break;

      case DeviceActionType.openCalculator:
        context.setSkill(AgentSkill.calculator);
        break;

      case DeviceActionType.openBrowser:
        context.setSkill(AgentSkill.browser);
        break;

      case DeviceActionType.flashlight:
        break;

      case DeviceActionType.playMusic:
        break;
    }
  }

  String _titleFor(DeviceCommand command) {
    switch (command.action) {
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

  String _contextLabel() {
    switch (context.activeSkill) {
      case AgentSkill.camera:
        return 'Camera context';

      case AgentSkill.calculator:
        return 'Calculator context';

      case AgentSkill.browser:
        return 'Browser context';

      case AgentSkill.none:
        return 'General context';
    }
  }

  Future<void> _sendResult({
    required String title,
    required String message,
    required bool success,
    String? context,
  }) async {
    await FlutterScreenOverlay.shareData({
      'type': 'edge_result',
      'title': title,
      'message': message,
      'success': success,
      'context': context,
    });
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
