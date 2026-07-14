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

  final Map<String, String> _headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"};
  final String _tdApiKey = "a9eeefb4ba19452b91adb75330fb05ae";
  final String _fmpApiKey = "pBDGnhUIlqmO80RrVIAa9YSROILUApn"; 

  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  void _initNotifications() async {
    const AndroidInitializationSettings initAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initIOS = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(android: initAndroid, iOS: initIOS);
    await _notifications.initialize(initSettings);
  }

  Future<void> _sendPushAlert(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'zeus_channel', 'Zeus Alerts',
      importance: Importance.max, priority: Priority.high, color: Color(0xFF007A53));
    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);
    await _notifications.show(DateTime.now().millisecond, title, body, platformDetails);
  }

  void _toggleWatchdog() {
    setState(() {
      _watchdogActive = !_watchdogActive;
      if (_watchdogActive) {
        _executeConcurrentScan(); 
        _watchdogTimer = Timer.periodic(const Duration(minutes: 60), (timer) { _executeConcurrentScan(); });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Watchdog Engaged"), backgroundColor: Color(0xFF007A53)));
      } else {
        _watchdogTimer?.cancel();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Watchdog Disengaged"), backgroundColor: Colors.redAccent));
      }
    });
  }

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

  Future<String> _calculateMacroSentiment() async {
    int bull = 0; int bear = 0;
    final List<String> feeds = [
      "https://finance.yahoo.com/rss/topstories", "https://rss.marketwatch.com/rss/topstories",
      "https://search.cnbc.com/rs/search/view.xml?partnerId=2000&keywords=macroeconomics",
    ];
    final RegExp titleRegex = RegExp(r'<title>(.*?)</title>', caseSensitive: false);
    final List<String> bearWords = ["inflation", "rate hike", "hawkish", "recession", "drop", "bearish"];
    final List<String> bullWords = ["rate cut", "dovish", "gdp growth", "rally", "surge", "bullish"];

    for (var url in feeds) {
      try {
        final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final matches = titleRegex.allMatches(res.body);
          for (var match in matches) {
            String txt = (match.group(1) ?? "").toLowerCase();
            for (var w in bearWords) { if (txt.contains(w)) bear++; }
            for (var w in bullWords) { if (txt.contains(w)) bull++; }
          }
        }
      } catch (_) {}
    }
    double score = (bull + bear) == 0 ? 0 : (bull - bear) / (bull + bear);
    return score > 0.03 ? "BUY" : (score < -0.03 ? "SHORT" : "NEUTRAL");
  }

  double _parseDouble(dynamic val) => double.tryParse(val.toString()) ?? 0.0;

  Future<Map<String, dynamic>?> _processAssetMetrics(String name, String ticker) async {
    final url4h = "https://api.twelvedata.com/time_series?symbol=$ticker&interval=4h&outputsize=200&apikey=$_tdApiKey";
    final url1d = "https://api.twelvedata.com/time_series?symbol=$ticker&interval=1day&outputsize=100&apikey=$_tdApiKey";
    try {
      final res4h = await http.get(Uri.parse(url4h)).timeout(const Duration(seconds: 5));
      final res1d = await http.get(Uri.parse(url1d)).timeout(const Duration(seconds: 5));
      final data4h = jsonDecode(res4h.body);
      final data1d = jsonDecode(res1d.body);
      
      List<dynamic> raw4h = (data4h['values'] as List).reversed.toList();
      List<double> closes4h = raw4h.map((e) => _parseDouble(e['close'])).toList();
      List<double> vols4h = raw4h.map((e) => _parseDouble(e['volume'])).toList();
      List<double> closes1d = (data1d['values'] as List).reversed.map((e) => _parseDouble(e['close'])).toList();

      double cp = closes4h.last;
      double sma20_4h = _calculateLastSMA(closes4h, 20);
      double sma20_1d = _calculateLastSMA(closes1d, 20);
      String trend4h = cp > sma20_4h ? "BULL" : "BEAR";
      String trend1d = closes1d.last > sma20_1d ? "BULL" : "BEAR";

      double refVol = vols4h.length > 1 ? vols4h[vols4h.length - 2] : (vols4h.isNotEmpty ? vols4h.last : 0);
      String volTrend = (refVol >= (_calculateLastSMA(vols4h, 5) * 0.60)) ? "HIGH" : "LOW";

      return {
        "name": name, "ticker": ticker, "cp": cp, "trend4h": trend4h, "trend1d": trend1d,
        "volTrend": volTrend, "sparkline": closes4h.sublist(math.max(0, closes4h.length - 30))
      };
    } catch (_) { return null; }
  }

  double _calculateLastSMA(List<double> data, int period) => data.sublist(math.max(0, data.length - period)).reduce((a, b) => a + b) / period;

  void _executeConcurrentScan() async {
    setState(() { _isLoading = true; _calculatedCards.clear(); });
    await _fetchEarningsCalendar();
    String sentiment = await _calculateMacroSentiment();
    setState(() { _macroSentiment = sentiment; });
    for (var entry in _masterWatchlist.entries) {
      _processAssetMetrics(entry.key, entry.value).then((metrics) {
        if (metrics != null && mounted) setState(() => _calculatedCards.add(metrics));
        if (_calculatedCards.length == _masterWatchlist.length) setState(() => _isLoading = false);
      });
    }
  }

  void _compileRiskCard(Map<String, dynamic> m, double capital) {
     // Card rendering logic remains as per your previous verified layout...
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121216),
      appBar: AppBar(
        title: const Text("ZEUS WORKSTATION", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1A1A22), centerTitle: true,
        actions: [IconButton(icon: Icon(Icons.precision_manufacturing, color: _watchdogActive ? Colors.green : Colors.grey), onPressed: _toggleWatchdog)],
      ),
      body: Center(child: _isLoading ? const CircularProgressIndicator() : const Text("Workstation Ready", style: TextStyle(color: Colors.white))),
    );
  }
}

class SparklinePainter extends CustomPainter {
  final List<double> data; final Color color;
  SparklinePainter(this.data, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    // Canvas logic as previously defined...
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
