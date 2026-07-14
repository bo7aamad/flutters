import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: QuantWorkstation()));
}

class QuantWorkstation extends StatefulWidget {
  const QuantWorkstation({super.key});
  @override
  State<QuantWorkstation> createState() => _QuantWorkstationState();
}

class _QuantWorkstationState extends State<QuantWorkstation> {
  final TextEditingController _balanceController = TextEditingController(text: "1000");
  final TextEditingController _customTickerController = TextEditingController();
  
  bool _isLoading = false;
  bool _watchdogActive = false;
  Timer? _watchdogTimer;
  String _macroSentiment = "NEUTRAL";
  final List<Map<String, dynamic>> _calculatedCards = [];
  List<String> _earningsRiskList = [];
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  final Map<String, String> _masterWatchlist = {
    "NVIDIA": "NVDA", "TESLA": "TSLA", "APPLE": "AAPL", "AMD": "AMD",
    "MICROSOFT": "MSFT", "AMAZON": "AMZN", "META": "META", "GOOGLE": "GOOGL",
    "NETFLIX": "NFLX", "BERKSHIRE": "BRK/B", "GOLD": "XAU/USD", "SILVER": "XAG/USD",
    "PLATINUM": "XPT/USD", "CRUDE_OIL": "WTICO/USD", "EURUSD": "EUR/USD",
    "GBPUSD": "GBP/USD", "USDJPY": "USD/JPY", "AUDUSD": "AUD/USD",
    "USDCAD": "USD/CAD", "USDCHF": "USD/CHF", "NZDUSD": "NZD/USD",
    "EURGBP": "EUR/GBP", "EURJPY": "EUR/JPY", "GBPJPY": "GBPJPY",
    "AUDJPY": "AUD/JPY", "GBPAUD": "GBP/AUD"
  };

  @override
  void initState() {
    super.initState();
    const AndroidInitializationSettings initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    _notifications.initialize(const InitializationSettings(android: initAndroid));
  }

  void _toggleWatchdog() {
    setState(() {
      _watchdogActive = !_watchdogActive;
      if (_watchdogActive) {
        _executeConcurrentScan();
        _watchdogTimer = Timer.periodic(const Duration(minutes: 60), (timer) { _executeConcurrentScan(); });
      } else {
        _watchdogTimer?.cancel();
      }
    });
  }

  Future<Map<String, dynamic>?> _processAssetMetrics(String name, String ticker) async {
    final url4h = "https://api.twelvedata.com/time_series?symbol=$ticker&interval=4h&outputsize=200&apikey=a9eeefb4ba19452b91adb75330fb05ae";
    try {
      final res = await http.get(Uri.parse(url4h)).timeout(const Duration(seconds: 5));
      final data = jsonDecode(res.body);
      if (data['values'] == null) return null;
      List<dynamic> raw = (data['values'] as List).reversed.toList();
      List<double> closes = raw.map((e) => double.tryParse(e['close'].toString()) ?? 0.0).toList();
      List<double> highs = raw.map((e) => double.tryParse(e['high'].toString()) ?? 0.0).toList();
      List<double> lows = raw.map((e) => double.tryParse(e['low'].toString()) ?? 0.0).toList();
      
      return {
        "name": name, "ticker": ticker, "cp": closes.last, "trend1d": "BULL", "trend4h": "BULL", 
        "volTrend": "HIGH", "rsi": 50.0, "bbPct": 50.0, "macdHist": 1.0, "atr": 0.5,
        "sparkline": closes.sublist(math.max(0, closes.length - 30)),
        "resis": highs.reduce(math.max), "supp": lows.reduce(math.min)
      };
    } catch (_) { return null; }
  }

  void _compileRiskCard(Map<String, dynamic> m) {
    double score = 2.5; 
    String baseRec = score >= 2.0 ? "BUY" : (score <= -2.0 ? "SHORT" : "WAIT");
    String finalRec = "$baseRec (SCORE: ${score.toStringAsFixed(1)})";
    
    _calculatedCards.add({
      "name": m['name'], "rec": finalRec, "baseRec": baseRec, "cp": m['cp'], "rsi": m['rsi'],
      "bbPct": m['bbPct'], "trend1d": m['trend1d'], "trend4h": m['trend4h'],
      "macd": "BULL", "volTrend": m['volTrend'], "sparkline": m['sparkline'],
      "entry": m['cp'], "sl": m['cp'] * 0.98, "tp": m['cp'] * 1.02, 
      "lots": "0.1", "dec": 2
    });
  }

  void _executeConcurrentScan() async {
    setState(() { _isLoading = true; _calculatedCards.clear(); });
    for (var entry in _masterWatchlist.entries) {
      _processAssetMetrics(entry.key, entry.value).then((m) {
        if (m != null && mounted) setState(() => _compileRiskCard(m));
        if (_calculatedCards.length == _masterWatchlist.length) setState(() => _isLoading = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121216),
      appBar: AppBar(
        title: const Text("ZEUS'S WORKSTATION", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1A22), centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.info_outline), onPressed: () {}),
          IconButton(icon: Icon(Icons.precision_manufacturing, color: _watchdogActive ? Colors.green : Colors.grey), onPressed: _toggleWatchdog)
        ],
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : ListView.builder(
        itemCount: _calculatedCards.length,
        itemBuilder: (ctx, i) {
          final c = _calculatedCards[i];
          return Card(
            color: const Color(0xFF1A1A22),
            child: Column(children: [
              Row(children: [
                Text(c['name'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                SizedBox(width: 80, height: 30, child: CustomPaint(painter: SparklinePainter(List<double>.from(c['sparkline']), Colors.greenAccent))),
                Text(c['rec'], style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))
              ]),
              Text("Entry: ${c['entry']} | SL: ${c['sl']} | TP: ${c['tp']}", style: const TextStyle(color: Colors.white))
            ])
          );
        }
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  final List<double> data; final Color color;
  SparklinePainter(this.data, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final double min = data.reduce(math.min);
    final double max = data.reduce(math.max);
    final double range = (max - min) == 0 ? 1 : (max - min);
    final Path path = Path();
    for (int i = 0; i < data.length; i++) {
      double x = i * (size.width / (data.length - 1));
      double y = size.height - ((data[i] - min) / range * size.height);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
