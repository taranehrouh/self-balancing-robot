import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart'; // ✅ added

const String serviceUUID = "fa6c75b7-eb43-45c4-b5e5-e3371433a96f";
const String characteristicUUID = "fa6c75b7-eb43-45c4-b5e5-e3371433a96f";

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _ble = FlutterReactiveBle();

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectSub;
  StreamSubscription<List<int>>? _notifySub;

  final List<DiscoveredDevice> _devices = [];
  String? _selectedDeviceId;
  String? _selectedDeviceName;
  var _stateMessage = 'Scanning...';
  QualifiedCharacteristic? _writeCharacteristic;

  bool _isConnected = false;
  Timer? _scanTimer;

@override
void initState() {
  super.initState();
  _requestPermissions().then((_) {
    _startScan();
  });
}

void _startScan() {
  _scanSub?.cancel();

  _scanSub = _ble
      .scanForDevices(withServices: [])
      .listen(_onScanUpdate, onError: (error) {
    setState(() {
      _stateMessage = 'Scan error: $error. Retrying...';
    });

    // Retry after delay to avoid throttling
    Future.delayed(Duration(seconds: 10), () {
      _startScan();
    });
  });
}


  // ✅ permission request method
  Future<void> _requestPermissions() async {
    if (await Permission.location.isDenied) {
      await Permission.location.request();
    }
    if (await Permission.bluetoothScan.isDenied) {
      await Permission.bluetoothScan.request();
    }
    if (await Permission.bluetoothConnect.isDenied) {
      await Permission.bluetoothConnect.request();
    }
    if (await Permission.location.isPermanentlyDenied ||
        await Permission.bluetoothScan.isPermanentlyDenied ||
        await Permission.bluetoothConnect.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  @override
  void dispose() {
    _notifySub?.cancel();
    _connectSub?.cancel();
    _scanSub?.cancel();
    super.dispose();
  }

  void _onScanUpdate(DiscoveredDevice d) {
    if (d.name.contains("BLE") &&
        !_devices.any((device) => device.id == d.id)) {
      setState(() {
        _devices.add(d);
      });
    }
  }

  void _connectToDevice() {
    if (_selectedDeviceId != null) {
      setState(() {
        _stateMessage = 'Connecting to $_selectedDeviceName...';
      });

      _connectSub = _ble.connectToDevice(id: _selectedDeviceId!).listen(
        (update) {
          if (update.connectionState == DeviceConnectionState.connected) {
            setState(() {
              _stateMessage = 'Connected to $_selectedDeviceName!';
              _isConnected = true;
            });
            _onConnected(_selectedDeviceId!);
          }
        },
        onError: (error) {
          setState(() {
            _stateMessage = 'Connection error: $error';
          });
        },
      );
    }
  }

  void _disconnectFromDevice() {
    try {
      _notifySub?.cancel();
      _notifySub = null;

      _connectSub?.cancel();
      _connectSub = null;

      setState(() {
        _isConnected = false;
        _stateMessage = 'Disconnected from $_selectedDeviceName.';
        _writeCharacteristic = null;
      });
    } catch (e) {
      setState(() {
        _stateMessage = 'Error during disconnection: $e';
      });
    }
  }

  void _onConnected(String deviceId) {
    final characteristic = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(serviceUUID),
      characteristicId: Uuid.parse(characteristicUUID),
    );

    _writeCharacteristic = characteristic;

    _notifySub = _ble.subscribeToCharacteristic(characteristic).listen((bytes) {
      setState(() {
        _stateMessage = 'Data received: ${Utf8Decoder().convert(bytes)}';
      });
    });
  }

  Future<void> _sendCommand(String command) async {
    if (_writeCharacteristic != null) {
      try {
        await _ble.writeCharacteristicWithResponse(
          _writeCharacteristic!,
          value: utf8.encode(command),
        );
        setState(() {
          _stateMessage = "Command '$command' sent!";
        });
      } catch (e) {
        setState(() {
          _stateMessage = "Error sending command: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey[300],
            width: double.infinity,
            child: Text(
              _stateMessage,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          if (_devices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: DropdownButton<String>(
                isExpanded: true,
                hint: const Text("Select a BLE Device"),
                value: _selectedDeviceId,
                items: _devices.map((device) {
                  return DropdownMenuItem(
                    value: device.id,
                    child: Text(device.name),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedDeviceId = value;
                    _selectedDeviceName = _devices
                        .firstWhere((device) => device.id == value)
                        .name;
                  });
                },
              ),
            ),
          if (!_isConnected)
            ElevatedButton(
              onPressed: _selectedDeviceId != null ? _connectToDevice : null,
              child: const Text('Connect'),
            ),
          if (_isConnected)
            ElevatedButton(
              onPressed: _disconnectFromDevice,
              child: const Text('Disconnect'),
            ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed:
                          _isConnected ? () => _sendCommand('FORWARD') : null,
                      child: const Icon(Icons.arrow_upward),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed:
                          _isConnected ? () => _sendCommand('LEFT') : null,
                      child: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed:
                          _isConnected ? () => _sendCommand('BACKWARD') : null,
                      child: const Icon(Icons.arrow_downward),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed:
                          _isConnected ? () => _sendCommand('RIGHT') : null,
                      child: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _isConnected ? () => _sendCommand('A') : null,
                      child: const Text('Send A'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _isConnected ? () => _sendCommand('B') : null,
                      child: const Text('Send B'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _isConnected ? () => _sendCommand('C') : null,
                      child: const Text('Send C'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
