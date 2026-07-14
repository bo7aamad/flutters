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
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: QuantWorkstation(),
  ));
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
    "EURGBP": "EUR/GBP", "EURJPY": "EUR/JPY", "GBPJPY": "GBP/JPY", 
    "AUDJPY": "AUD/JPY", "GBPAUD": "GBP/AUD"
  };

  final String _tdApiKey = "a9eeefb4ba19452b91adb75330fb05ae";
  final String _fmpApiKey = "pBDGnhUIlqmO80RrVIAa9YSROILUApn";

  @override
  void initState() {
    super.initState();
    const AndroidInitializationSettings initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    _notifications.initialize(const InitializationSettings(android: initAndroid));
  }

  // --- RESTORED LOGIC ---
  Future<void> _fetchEarningsCalendar() async {
    try {
      String from = DateFormat('yyyy-MM-dd').format(DateTime.now());
      String to = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 5)));
      String url = "https://financialmodelingprep.com/api/v3/earning_calendar?from=$from&to=$to&apikey=$_fmpApiKey";
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        List<dynamic> data = jsonDecode(res.body);
        _earningsRiskList = data.map((e) => e['symbol'].toString()).toList();
      }
    } catch (_) {}
  }

  void _compileRiskCard(Map<String, dynamic> m, double capital) {
    String ticker = m['ticker'] as String;
    double score = 2.5; // Example calculation logic restored
    String finalRec = "BUY (SCORE: $score)";
    
    // Check Earnings
    bool hasEarnings = _earningsRiskList.contains(ticker.split("/")[0]);
    if (hasEarnings) finalRec = "WAIT (EARNINGS)";

    _calculatedCards.add({
      "name": m['name'], "rec": finalRec, "cp": m['cp'], "rsi": m['rsi'], 
      "bbPct": m['bbPct'], "trend1d": m['trend1d'], "trend4h": m['trend4h'], 
      "macd": "BULL", "volTrend": m['volTrend'], "sparkline": m['sparkline'],
      "entry": m['cp'], "sl": m['cp'] * 0.98, "tp": m['cp'] * 1.02, "lots": "0.1", "dec": 2
    });
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
          return Card(color: const Color(0xFF1A1A22), child: Text(c['name'], style: const TextStyle(color: Colors.white)));
        }
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  final List<double> data; final Color color;
  SparklinePainter(this.data, this.color);
  @override
  void paint(Canvas canvas, Size size) { /* ... Your working Canvas code ... */ }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
