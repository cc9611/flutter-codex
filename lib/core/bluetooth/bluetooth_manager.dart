import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothManager {
  Stream<List<ScanResult>> scanForDevices() {
    return FlutterBluePlus.scanResults;
  }

  Future<void> startScan() {
    return FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
  }

  Future<void> stopScan() {
    return FlutterBluePlus.stopScan();
  }
}
