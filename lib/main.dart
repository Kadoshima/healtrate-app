// main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // アプリケーションのルートウィジェット
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter BLE Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'BLE Heart Rate Monitor'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  StreamSubscription? scanSubscription;
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? heartRateCharacteristic;
  int heartRate = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    startScan();
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    disconnectDevice();
    timer?.cancel();
    super.dispose();
  }

  // デバイスのスキャンを開始
  void startScan() async {
    try {
      // スキャンを開始
      await FlutterBluePlus.startScan(
        withServices: [
          Guid("0000180d-0000-1000-8000-00805f9b34fb")
        ], // 心拍サービスのUUID
        // 他のフィルタパラメータも必要に応じて追加
      );

      // スキャン結果をリッスン
      scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var scanResult in results) {
          final device = scanResult.device;
          final advertisementData = scanResult.advertisementData;

          // デバイス名またはサービスUUIDでフィルタリング
          if (device.platformName.toLowerCase().contains("heart rate") ||
              advertisementData.serviceUuids
                  .contains(Guid("0000180d-0000-1000-8000-00805f9b34fb"))) {
            connectToDevice(device);
            FlutterBluePlus.stopScan(); // スキャンを停止
            scanSubscription?.cancel(); // リッスンを解除
            break;
          }
        }
      });

      // スキャンのタイムアウトを設定（例: 10秒後にスキャンを停止）
      Future.delayed(const Duration(seconds: 10), () {
        FlutterBluePlus.stopScan();
        scanSubscription?.cancel();
        if (connectedDevice == null) {
          // 必要に応じて再スキャンを開始
          startScan();
        }
      });
    } catch (e) {
      debugPrint("スキャン中にエラーが発生しました: $e");
    }
  }

  // デバイスに接続
  Future<void> connectToDevice(BluetoothDevice device) async {
    setState(() {
      connectedDevice = device;
    });

    try {
      await device.connect();
      await discoverServices();
    } catch (e) {
      debugPrint("デバイスへの接続中にエラーが発生しました: $e");
      setState(() {
        connectedDevice = null;
      });
    }
  }

  // サービスとキャラクタリスティックを探索
  Future<void> discoverServices() async {
    if (connectedDevice == null) return;

    List<BluetoothService> services = await connectedDevice!.discoverServices();
    for (var service in services) {
      if (service.uuid.toString().toLowerCase() ==
          "0000180d-0000-1000-8000-00805f9b34fb") {
        // 心拍サービス
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString().toLowerCase() ==
              "00002a37-0000-1000-8000-00805f9b34fb") {
            // 心拍測定キャラクタリスティック
            heartRateCharacteristic = characteristic;
            startHeartRateMonitoring();
            break;
          }
        }
      }
    }
  }

  // 心拍数のモニタリングを開始（1Hzで読み取る）
  void startHeartRateMonitoring() {
    if (heartRateCharacteristic == null) return;

    // 通知を購読する場合
    heartRateCharacteristic!.setNotifyValue(true);
    heartRateCharacteristic!.lastValueStream.listen((value) {
      setState(() {
        heartRate = parseHeartRate(value);
      });
    });

    // または1Hzで定期的に読み取る場合
    /*
    timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      List<int> value = await heartRateCharacteristic!.read();
      setState(() {
        heartRate = parseHeartRate(value);
      });
    });
    */
  }

  // 心拍数の値をパース
  int parseHeartRate(List<int> value) {
    // Heart Rate Measurementの仕様に基づいてパース
    // 最初のバイトはフラグ
    int flag = value[0];
    bool isHeartRateValueSizeLong = (flag & 0x01) != 0;
    int hrValue;

    if (isHeartRateValueSizeLong) {
      hrValue = value[1] + (value[2] << 8);
    } else {
      hrValue = value[1];
    }

    return hrValue;
  }

  // デバイスの接続を解除
  Future<void> disconnectDevice() async {
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
      setState(() {
        connectedDevice = null;
        heartRateCharacteristic = null;
        heartRate = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String statusText;
    if (connectedDevice == null) {
      statusText = "デバイスをスキャン中...";
    } else {
      statusText = "接続中: ${connectedDevice!.platformName}";
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(statusText),
            const SizedBox(height: 20),
            Text(
              heartRate > 0 ? '心拍数: $heartRate bpm' : '心拍数を取得中...',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 40),
            connectedDevice != null
                ? ElevatedButton(
                    onPressed: disconnectDevice,
                    child: const Text("接続解除"),
                  )
                : Container(),
          ],
        ),
      ),
      floatingActionButton: connectedDevice == null
          ? FloatingActionButton(
              onPressed: () {
                // 再スキャンを開始
                startScan();
              },
              tooltip: '再スキャン',
              child: const Icon(Icons.refresh),
            )
          : null,
    );
  }
}
