enum DeviceActionType {
  openCamera,
  openCalculator,
  openBrowser,
  flashlight,
  playMusic,
}

class DeviceCommand {
  final DeviceActionType action;

  final String intent;

  final Map<String, String> slots;

  final Map<String, Object?> arguments;

  const DeviceCommand({
    required this.action,
    required this.intent,
    required this.slots,
    this.arguments = const {},
  });

  Map<String, Object> toJson() {
    return {'intent': intent, 'slots': slots};
  }
}

class ActionRouter {
  String _normalize(String input) {
    return input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[.!?,;:]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  DeviceCommand? route(String input) {
    final text = _normalize(input);

    //
    // OPEN APP COMMANDS
    //

    final openApp = RegExp(
      r'^(?:please )?'
      r'(?:open|launch|start|show) '
      r'(?:the )?'
      r'(camera|calculator|calc|browser|chrome)'
      r'(?: app)?$',
    ).firstMatch(text);

    if (openApp != null) {
      final raw = openApp.group(1)!;

      if (raw == 'camera') {
        return const DeviceCommand(
          action: DeviceActionType.openCamera,
          intent: 'OpenApp',
          slots: {'app': 'camera'},
        );
      }

      if (raw == 'calculator' || raw == 'calc') {
        return const DeviceCommand(
          action: DeviceActionType.openCalculator,
          intent: 'OpenApp',
          slots: {'app': 'calculator'},
        );
      }

      if (raw == 'browser' || raw == 'chrome') {
        return DeviceCommand(
          action: DeviceActionType.openBrowser,
          intent: 'OpenApp',
          slots: {'app': raw},
        );
      }
    }

    //
    // GENERIC MUSIC PLAYBACK
    //
    // Only generic playback-control phrases are intercepted.
    //
    // Specific benchmark commands such as:
    //   "play songs by adele"
    //   "play the album thriller"
    // continue to Champion V4 for PlayMusic + slot extraction.
    //
    final playMusic = RegExp(
      r'^(?:please )?'
      r'(?:play|resume|continue|start) '
      r'(?:the )?music'
      r'(?: please)?$',
    ).hasMatch(text);

    if (playMusic) {
      return const DeviceCommand(
        action: DeviceActionType.playMusic,
        intent: 'MediaControl',
        slots: {'action': 'play', 'media': 'music'},
      );
    }

    //
    // FLASHLIGHT
    //

    final hasTorch = RegExp(r'\b(?:torch|flashlight)\b').hasMatch(text);

    if (hasTorch) {
      final turnOn =
          RegExp(r'\b(?:turn on|switch on|enable|start)\b').hasMatch(text) ||
          RegExp(r'\b(?:torch|flashlight) on\b').hasMatch(text);

      final turnOff =
          RegExp(r'\b(?:turn off|switch off|disable|stop)\b').hasMatch(text) ||
          RegExp(r'\b(?:torch|flashlight) off\b').hasMatch(text);

      if (turnOn) {
        return _flashlight(true);
      }

      if (turnOff) {
        return _flashlight(false);
      }
    }

    //
    // NOT A DEVICE COMMAND.
    //
    // Champion V4 handles it.
    //

    return null;
  }

  DeviceCommand _flashlight(bool enabled) {
    final state = enabled ? 'on' : 'off';

    return DeviceCommand(
      action: DeviceActionType.flashlight,
      intent: 'Flashlight',
      slots: {'state': state},
      arguments: {'enabled': enabled},
    );
  }
}
