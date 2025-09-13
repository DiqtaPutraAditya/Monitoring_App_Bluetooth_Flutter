import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'dart:math';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Drying',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const BluetoothDeviceListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BluetoothDeviceListScreen extends StatefulWidget {
  const BluetoothDeviceListScreen({super.key});

  @override
  State<BluetoothDeviceListScreen> createState() => _BluetoothDeviceListScreenState();
}

class _BluetoothDeviceListScreenState extends State<BluetoothDeviceListScreen> {
  BluetoothDevice? selectedDevice;

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      final connection = await BluetoothConnection.toAddress(device.address);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(connection: connection),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Gagal terhubung ke perangkat Bluetooth")),
      );
    }
  }

  void _showNotConnectedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Tanpa Koneksi Bluetooth"),
        content: const Text("Anda akan membuka aplikasi dalam mode offline. Data sensor tidak akan update."),
        actions: [
          TextButton(onPressed: Navigator.of(context).pop, child: const Text("Batal")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HomeScreen.offline(), // Mode offline
                ),
              );
            },
            child: const Text("Lanjut Offline"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 49, 255, 203), 
        foregroundColor: Colors.blue,
        elevation: 0,
        title: const Text("Pilih Perangkat", style: TextStyle(color: Colors.black87)),
        centerTitle: true,
      ),
      body: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color.fromARGB(255, 9, 255, 193), const Color.fromARGB(255, 240, 255, 227)],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<List<BluetoothDevice>>(
                future: FlutterBluetoothSerial.instance.getBondedDevices(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text("Tidak ada perangkat Bluetooth tersedia"));
                  }

                  final devices = snapshot.data!;
                  return ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return Card(
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: ListTile(
                          leading: Icon(Icons.bluetooth_connected_rounded, color: Colors.blue),
                          title: Text(device.name ?? "Unnamed Device", style: TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(device.address),
                          onTap: () => connectToDevice(device),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ElevatedButton.icon(
                label: const Text("Masuk Tanpa Bluetooth"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent.shade100,
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
                onPressed: () => _showNotConnectedDialog(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ParsedData {
  final String mode;
  final double temperature;
  final double humidity;
  final int light;
  final String rain;
  final String drying;
  final DateTime timestamp;

  ParsedData({
    required this.mode,
    required this.temperature,
    required this.humidity,
    required this.light,
    required this.rain,
    required this.drying,
    required this.timestamp,
  });

  factory ParsedData.fromRaw(String raw) {
    final parts = raw.split('|');
    final Map<String, String> map = {};
    for (var part in parts) {
      var split = part.split(':');
      if (split.length == 2) {
        map[split[0]] = split[1];
      }
    }

    return ParsedData(
      mode: map['MODE'] ?? 'AUTO',
      temperature: double.tryParse(map['T'] ?? '') ?? 0,
      humidity: double.tryParse(map['H'] ?? '') ?? 0,
      light: int.tryParse(map['L'] ?? '') ?? 0,
      rain: map['R'] ?? 'N/A',
      drying: map['D'] ?? 'N/A',
      timestamp: DateTime.now(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final BluetoothConnection? connection;
  final bool isOffline;

  const HomeScreen({super.key, required this.connection}) : isOffline = false;

  factory HomeScreen.offline() => HomeScreen._offline();

  HomeScreen._offline({Key? key})
      : connection = null,
        isOffline = true,
        super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ParsedData> dataList = [];
  int selectedIndex = 0;

  final StringBuffer _buffer = StringBuffer();
  bool _isReading = false;
  late ScrollController _scrollController;

  bool isAuto = true;
  bool isCoverIn = true;
  String currentMode = 'AUTO';
  String currentDrying = 'IN';

  void _sendCommand(String command) {
    if (!widget.isOffline && widget.connection != null && widget.connection!.isConnected) {
      Uint8List bytes = Uint8List.fromList(command.codeUnits);
      widget.connection!.output.add(bytes);
      print("Perintah '$command' dikirim");
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak terhubung ke perangkat")),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('id_ID', null);
    _scrollController = ScrollController();

    if (!widget.isOffline && widget.connection != null) {
      widget.connection!.input!.listen((data) {
        final String chunk = String.fromCharCodes(data).trim();

        for (int i = 0; i < chunk.length; i++) {
          final char = chunk[i];

          if (char == '<') {
            _buffer.clear();
            _isReading = true;
          } else if (char == '>') {
            _isReading = false;
            final raw = _buffer.toString().trim();

            try {
              final parsed = ParsedData.fromRaw(raw);
              setState(() {
                dataList.insert(0, parsed);
              });

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    0.0,
                    duration: Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              });
            } catch (e) {
              print("Parsing gagal: $raw");
            }
          } else if (_isReading) {
            _buffer.write(char);
          }
        }
      });
    } else {
      Future.delayed(Duration.zero, () {
        setState(() {
          dataList.insert(
            0,
            ParsedData(
              mode: "AUTO",
              temperature: 30.0,
              humidity: 65.0,
              light: 800,
              rain: "DRY",
              drying: "IN",
              timestamp: DateTime.now(),
            ),
          );
        });
      });
    }
  }

  @override
  void dispose() {
    if (widget.connection != null && widget.connection!.isConnected) {
      widget.connection!.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      buildDashboard(),
      buildGraphPage(),
      buildRawDataPage(),
    ];

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 11, 255, 222),
      body: SafeArea(child: pages[selectedIndex]),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        currentIndex: selectedIndex,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Grafik'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Raw Data'),
        ],
      ),
    );
  }

  IconData getWeatherIcon(ParsedData? latest) {
    if (latest?.rain == "RAINING") return Icons.cloud_queue;
    if ((latest?.light ?? 0) < 300) return Icons.wb_cloudy;
    return Icons.wb_sunny;
  }

 Widget buildDashboard() {
  final latest = dataList.isNotEmpty ? dataList.first : null;
  final now = DateTime.now();
  final time = DateFormat.Hm('id_ID').format(now);
  final date = DateFormat('d EEEE MMMM yyyy', 'id_ID').format(now);

  return Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.fromARGB(255, 11, 255, 222), Colors.white], // Gradient dari Cyan ke Putih
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text("SMART DRYING RACK",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wb_sunny_rounded, color: Colors.amber, size: 48),
                  const SizedBox(width: 10),
                  Text(time,
                      style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w600, color: Colors.black87)),
                ],
              ),
              Text(date, style: const TextStyle(fontSize: 18, color: Color.fromARGB(255, 0, 0, 0))),
              const SizedBox(height: 20),

              if (widget.isOffline)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                      SizedBox(width: 8),
                      Text("Mode Offline", style: TextStyle(fontSize: 14, color: Colors.black87)),
                    ],
                  ),
                ),

              if (latest != null)
                Expanded(
                  child: GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    children: [
                      buildInfoCard("Temp", "${latest.temperature} °C", "", Colors.green.shade400, Icons.thermostat),
                      buildInfoCard("Humidity", "${latest.humidity}%", "", Colors.blue.shade400, Icons.water_drop_rounded),
                      buildInfoCard("Light", "${latest.light}", "", Colors.red.shade400, Icons.light_mode),
                      buildInfoCard("Status", latest.rain, latest.drying, Colors.yellow.shade100, getWeatherIcon(latest)),
                    ],
                  ),
                )
              else
                const Expanded(
                  child: Center(child: Text("Menunggu data...")),
                ),

              // 🔘 Tombol Kontrol Utama
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: widget.isOffline ? null : () {
                          setState(() {
                            isAuto = !isAuto;
                            currentMode = isAuto ? "AUTO" : "MANUAL";
                            _sendCommand('m');
                          });
                        },
                        icon: Icon(Icons.settings_backup_restore_rounded),
                        label: Text(currentMode, style: const TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: currentMode == "AUTO"
                              ? Colors.blue.withAlpha(25)
                              : Colors.deepOrange.withAlpha(25),
                          foregroundColor: currentMode == "AUTO" ? Colors.blue : Colors.deepOrange,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: widget.isOffline ? null : () {
                          setState(() {
                            isCoverIn = !isCoverIn;
                            currentDrying = isCoverIn ? "OUT" : "IN";
                            _sendCommand('c');
                          });
                        },
                        icon: Icon(isCoverIn ? Icons.back_hand_rounded : Icons.open_in_new_rounded),
                        label: Text(currentDrying, style: const TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: currentDrying == "IN"
                              ? Colors.green.withAlpha(25)
                              : Colors.red.withAlpha(25),
                          foregroundColor: currentDrying == "IN" ? Colors.green : Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget buildGraphPage() {
    final limitedList = dataList.length > 20 ? dataList.sublist(0, 20) : dataList;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text("Grafik Real-time", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),

          // Grafik Suhu
          _buildSingleChart(
            context,
            "Suhu (°C)",
            limitedList.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.temperature)).toList(),
            const Color.fromARGB(255, 223, 29, 16),
          ),
          SizedBox(height: 24),

          // Grafik Kelembapan
          _buildSingleChart(
            context,
            "Kelembapan (%)",
            limitedList.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.humidity)).toList(),
            const Color.fromARGB(255, 4, 90, 160),
          ),
          SizedBox(height: 24),

          // Grafik Cahaya (LDR)
          _buildSingleChart(
            context,
            "Cahaya (LDR)",
            limitedList.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.light.toDouble())).toList(),
            const Color.fromARGB(255, 51, 218, 0),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleChart(
    BuildContext context,
    String title,
    List<FlSpot> spots,
    Color lineColor,
  ) {
    if (spots.isEmpty) return Container();

    final minY = spots.map((s) => s.y).reduce(min);
    final maxY = spots.map((s) => s.y).reduce(max);

    return Container(
      height: 200,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                titlesData: FlTitlesData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey.withAlpha(51),
                      strokeWidth: 1,
                    );
                  },
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: spots.length.toDouble(),
                minY: minY - 5,
                maxY: maxY + 5,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: lineColor,
                    barWidth: 3,
                    belowBarData: BarAreaData(
                      show: true,
                      color: lineColor.withAlpha(51), // 0.2 opacity → 51 alpha
                    ),
                    dotData: FlDotData(show: false),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

 Widget buildRawDataPage() {
  return Scaffold(
    backgroundColor: Colors.transparent,
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.fromARGB(255, 43, 253, 218), Colors.white],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.isOffline)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.orange, size: 18),
                    SizedBox(width: 8),
                    Text("Mode Offline",
                        style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),

            Expanded(
              child: dataList.isEmpty
                  ? const Center(child: Text("Belum ada data"))
                  : ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      itemCount: dataList.length,
                      itemBuilder: (context, index) {
                        final d = dataList[index];
                        return Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          margin:
                              const EdgeInsets.symmetric(vertical: 6),
                          child: Padding(
                            padding:
                                const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    "${DateFormat.Hms().format(d.timestamp)} | MODE:${d.mode}",
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 6),
                                Text("Suhu: ${d.temperature} °C",
                                    style: const TextStyle(fontSize: 14)),
                                Text("Kelembapan: ${d.humidity} %",
                                    style: const TextStyle(fontSize: 14)),
                                Text("Cahaya: ${d.light}",
                                    style: const TextStyle(fontSize: 14)),
                                Text("Hujan: ${d.rain}",
                                    style: const TextStyle(fontSize: 14)),
                                Text("Posisi: ${d.drying}",
                                    style: const TextStyle(fontSize: 14)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget buildInfoCard(String title, String value, String subtitle, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(2, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.black87),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          if (subtitle.isNotEmpty)
            Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ],
      ),
    );
  }
}