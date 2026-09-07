import 'package:flutter/services.dart';

import 'action_router.dart';

class DeviceActionDispatcher {
  static const MethodChannel _channel = MethodChannel(
    'org.cdac.hackathon.cdac_assistant/device_actions',
  );

  Future<String> execute(DeviceCommand command) async {
    switch (command.action) {
      case DeviceActionType.openCamera:
        return _invoke('openCamera');

      case DeviceActionType.openCalculator:
        return _invoke('openCalculator');

      case DeviceActionType.openBrowser:
        return _invoke('openBrowser');

      case DeviceActionType.flashlight:
        final enabled = command.arguments['enabled'] as bool? ?? false;

        return _invoke('setFlashlight', <String, Object?>{'enabled': enabled});

      case DeviceActionType.playMusic:
        throw StateError('PlayMusic must execute after Champion V4 inference.');
    }
  }

  //
  // This method is called ONLY AFTER
  // Champion V4 predicts PlayMusic.
  //
  Future<String> playMusic({String query = ''}) async {
    return _invoke('playMusic', <String, Object?>{'query': query});
  }

  Future<String> pauseMusic() async {
    return _invoke('pauseMusic');
  }

  Future<String> resumeMusic() async {
    return _invoke('resumeMusic');
  }

  Future<String> stopMusic() async {
    return _invoke('stopMusic');
  }

  Future<String> sendWhatsApp({
    required String contact,
    required String message,
  }) async {
    return _invoke('sendWhatsApp', <String, Object?>{
      'contact': contact,
      'message': message,
    });
  }

  Future<String> captureFrontPhoto() async {
    return _invoke('captureFrontPhoto');
  }

  Future<String> captureBackPhoto() async {
    return _invoke('captureBackPhoto');
  }

  Future<String> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final response = await _channel.invokeMethod<String>(method, arguments);

    return response ?? 'Action completed';
  }
}
