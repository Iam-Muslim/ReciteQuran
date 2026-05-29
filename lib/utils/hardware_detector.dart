import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import '../core/types.dart';
import 'file_logger.dart';

// Detects the hardware capabilities of the device to optimize ASR performance.
class HardwareDetector {
  /// Returns the appropriate [HardwareTier] for the current device.
  ///
  /// - iOS: Assumes flagship (Apple Silicon is universally capable).
  /// - Android: Evaluates the SDK int to estimate the device's age and tier.
  static Future<HardwareTier> getDeviceTier() async {
    try {
      if (Platform.isIOS) {
        return HardwareTier.flagship;
      }

      if (Platform.isAndroid) {
        final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        final int sdkInt = androidInfo.version.sdkInt;

        FileLogger.instance.log('[HARDWARE] Detected Android SDK: $sdkInt');

        if (sdkInt >= 33) {
          // Android 13+ (Typically newer, more capable devices)
          return HardwareTier.flagship;
        } else if (sdkInt >= 30) {
          // Android 11 to 12
          return HardwareTier.standard;
        } else {
          // Android 10 and below
          return HardwareTier.budget;
        }
      }
    } catch (e) {
      FileLogger.instance.log('[HARDWARE] Error detecting device tier: $e');
    }

    // Default fallback
    return HardwareTier.standard;
  }
}
