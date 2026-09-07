import 'package:android_intent_plus/android_intent.dart';
import 'package:torch_light/torch_light.dart';

class OverlayActionExecutor {
  static const int _newTask = 0x10000000;
  static const int _clearTop = 0x04000000;

  Future<String> openCalculator() async {
    //
    // Exact calculator installed on the RMX3853 / ColorOS device.
    //
    const intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      category: 'android.intent.category.LAUNCHER',
      package: 'com.coloros.calculator',
      componentName: 'com.android.calculator2.Calculator',
      flags: <int>[_newTask, _clearTop],
    );

    await intent.launch();

    return 'Calculator opened';
  }

  Future<String> openCamera() async {
    const intent = AndroidIntent(
      action: 'android.media.action.STILL_IMAGE_CAMERA',
      flags: <int>[_newTask],
    );

    await intent.launch();

    return 'Camera opened';
  }

  Future<String> openBrowser() async {
    const intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      category: 'android.intent.category.APP_BROWSER',
      flags: <int>[_newTask],
    );

    await intent.launch();

    return 'Browser opened';
  }

  Future<String> playMusic() async {
    //
    // The overlay runs in a separate Flutter engine, so it cannot use
    // MainActivity's MethodChannel directly.
    //
    // Launch the installed Realme/HeyTap music application.
    // Normal Assistant commands use native AudioManager media playback.
    //
    const intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      category: 'android.intent.category.LAUNCHER',
      package: 'com.heytap.music',
      flags: <int>[_newTask, _clearTop],
    );

    await intent.launch();

    return 'Music player opened';
  }

  Future<String> setTorch(bool enabled) async {
    final available = await TorchLight.isTorchAvailable();

    if (!available) {
      throw StateError('Torch is not available on this device.');
    }

    if (enabled) {
      await TorchLight.enableTorch();
      return 'Flashlight turned on';
    }

    await TorchLight.disableTorch();
    return 'Flashlight turned off';
  }
}
