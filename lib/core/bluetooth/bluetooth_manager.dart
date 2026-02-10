import 'dart:async';

import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum BluetoothConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
}

class BluetoothState {
  const BluetoothState({
    this.status = BluetoothConnectionStatus.disconnected,
    this.workstationId,
    this.rssi,
  });

  final BluetoothConnectionStatus status;
  final String? workstationId;
  final int? rssi;

  BluetoothState copyWith({
    BluetoothConnectionStatus? status,
    String? workstationId,
    int? rssi,
    bool clearWorkstationId = false,
    bool clearRssi = false,
  }) {
    return BluetoothState(
      status: status ?? this.status,
      workstationId:
          clearWorkstationId ? null : (workstationId ?? this.workstationId),
      rssi: clearRssi ? null : (rssi ?? this.rssi),
    );
  }
}

final bluetoothNotifierProvider =
    StateNotifierProvider<BluetoothNotifier, BluetoothState>(
  (ref) => BluetoothNotifier(),
);

class BluetoothNotifier extends StateNotifier<BluetoothState> {
  BluetoothNotifier() : super(const BluetoothState());

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  Timer? _rssiTimer;

  Future<List<BluetoothDevice>> startScan({
    String? targetName,
    Guid? targetServiceUuid,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    state = state.copyWith(status: BluetoothConnectionStatus.scanning);

    final foundDevices = <String, BluetoothDevice>{};

    await _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final device = result.device;
        final matchesName =
            targetName == null ||
            result.advertisementData.advName.contains(targetName) ||
            device.platformName.contains(targetName);
        final matchesService =
            targetServiceUuid == null ||
            result.advertisementData.serviceUuids.contains(targetServiceUuid);

        if (matchesName && matchesService) {
          foundDevices[device.remoteId.str] = device;
        }
      }
    });

    await FlutterBluePlus.startScan(
      timeout: timeout,
      withServices: targetServiceUuid == null ? [] : [targetServiceUuid],
    );

    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;

    state = state.copyWith(
      status: _connectedDevice == null
          ? BluetoothConnectionStatus.disconnected
          : BluetoothConnectionStatus.connected,
    );

    return foundDevices.values.toList();
  }

  Future<void> connect(BluetoothDevice device) async {
    await _clearConnectionState();

    state = state.copyWith(
      status: BluetoothConnectionStatus.connecting,
      workstationId: device.remoteId.str,
      clearRssi: true,
    );

    await FlutterBluePlus.stopScan();

    await device.connect(timeout: const Duration(seconds: 15));

    try {
      await device.requestMtu(512);
    } catch (_) {
      // iOS does not allow MTU request; ignore failures here.
    }

    _connectedDevice = device;
    _connectionSubscription =
        device.connectionState.listen(_handleConnectionStateChanged);

    await _discoverCharacteristics(device);
    await _refreshRssi();
    _startRssiPolling();

    state = state.copyWith(status: BluetoothConnectionStatus.connected);
  }

  Future<void> writeData(List<int> data) async {
    if (_connectedDevice == null || state.status != BluetoothConnectionStatus.connected) {
      throw StateError('No connected bluetooth device.');
    }

    if (_writeCharacteristic == null) {
      await _discoverCharacteristics(_connectedDevice!);
    }

    final characteristic = _writeCharacteristic;
    if (characteristic == null) {
      throw StateError('No writable characteristic found.');
    }

    final allowLongWrite = data.length > 20;
    await characteristic.write(data, allowLongWrite: allowLongWrite);
  }

  Future<Stream<List<int>>> subscribeToData() async {
    if (_connectedDevice == null || state.status != BluetoothConnectionStatus.connected) {
      throw StateError('No connected bluetooth device.');
    }

    if (_notifyCharacteristic == null) {
      await _discoverCharacteristics(_connectedDevice!);
    }

    final characteristic = _notifyCharacteristic;
    if (characteristic == null) {
      throw StateError('No notify characteristic found.');
    }

    await characteristic.setNotifyValue(true);
    return characteristic.lastValueStream;
  }

  Future<void> disconnect() async {
    final device = _connectedDevice;
    await _clearConnectionState();
    if (device != null) {
      await device.disconnect();
    }
    state = state.copyWith(
      status: BluetoothConnectionStatus.disconnected,
      clearWorkstationId: true,
      clearRssi: true,
    );
  }

  Future<void> _discoverCharacteristics(BluetoothDevice device) async {
    final services = await device.discoverServices();

    BluetoothCharacteristic? writable;
    BluetoothCharacteristic? notifiable;

    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (writable == null &&
            (characteristic.properties.write ||
                characteristic.properties.writeWithoutResponse)) {
          writable = characteristic;
        }

        if (notifiable == null &&
            (characteristic.properties.notify ||
                characteristic.properties.indicate)) {
          notifiable = characteristic;
        }
      }
    }

    _writeCharacteristic = writable;
    _notifyCharacteristic = notifiable;
  }

  void _handleConnectionStateChanged(BluetoothConnectionState connectionState) {
    if (connectionState == BluetoothConnectionState.disconnected) {
      _clearConnectionState(showError: true);
      state = state.copyWith(
        status: BluetoothConnectionStatus.disconnected,
        clearWorkstationId: true,
        clearRssi: true,
      );
    }
  }

  void _startRssiPolling() {
    _rssiTimer?.cancel();
    _rssiTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshRssi();
    });
  }

  Future<void> _refreshRssi() async {
    final device = _connectedDevice;
    if (device == null || state.status != BluetoothConnectionStatus.connected) {
      return;
    }

    try {
      final value = await device.readRssi();
      state = state.copyWith(rssi: value);
    } catch (_) {
      // Ignore RSSI read errors while keeping latest known value.
    }
  }

  Future<void> _clearConnectionState({bool showError = false}) async {
    _rssiTimer?.cancel();
    _rssiTimer = null;

    await _scanSubscription?.cancel();
    _scanSubscription = null;

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _connectedDevice = null;

    if (showError) {
      EasyLoading.showError('蓝牙连接已断开');
    }
  }

  @override
  void dispose() {
    _clearConnectionState();
    super.dispose();
  }
}
