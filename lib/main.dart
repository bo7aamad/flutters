import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;

void main() {
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
  String _macroSentiment = "NEUTRAL";
  final List<Map<String, dynamic>> _calculatedCards = [];

  final Map<String, String> _masterWatchlist = {
    "NVIDIA": "NVDA", "TESLA": "TSLA", "APPLE": "AAPL", "AMD": "AMD", 
    "MICROSOFT": "MSFT", "AMAZON": "AMZN", "META": "META", "GOOGLE": "GOOGL", 
    "GOLD": "GC=F", "SILVER": "SI=F", "CRUDE_OIL": "CL=F", "EURUSD": "EURUSD=X"
  };

  final Map<String, String> _headers = {"User-Agent": "Mozilla/5.0"};

  Future<String> _calculateMacroSentiment() async {
    int bull = 0; int bear = 0;
    final feeds = ["https://finance.yahoo.com/rss/topstories", "https://rss.marketwatch.com/rss/topstories"];
    final reg = RegExp(r'<title>(.*?)</title>', caseSensitive: false);
    for (var url in feeds) {
      try {
        final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          for (var match in reg.allMatches(res.body)) {
            String txt = (match.group(1) ?? "").toLowerCase();
            if (txt.contains("inflation") || txt.contains("rate hike")) bear++;
            if (txt.contains("rate cut") || txt.contains("growth")) bull++;
          }
        }
      } catch (_) {}
    }
    return (bull - bear) > 0 ? "BUY" : (bear > bull ? "SHORT" : "NEUTRAL");
  }

  Future<Map<String, dynamic>?> _processAssetMetrics(String name, String ticker) async {
    final url4h = "https://query1.finance.yahoo.com/v8/finance/chart/$ticker?interval=4h&range=30d";
    try {
      final res = await http.get(Uri.parse(url4h), headers: _headers).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body)['chart']['result'][0];
      final ind = data['indicators']['quote'][0];
      List<double> closes = (ind['close'] as List).where((e) => e != null).map((e) => (e as num).toDouble()).toList();
      double cp = closes.last;
      
      double rsi = 50.0;
      if (closes.length > 14) {
        double gain = 0; double loss = 0;
        for (int i = closes.length - 14; i < closes.length; i++) {
          double diff = closes[i] - closes[i-1];
          if (diff > 0) gain += diff; else loss -= diff;
        }
        rsi = 100 - (100 / (1 + ((gain/14)/(loss/14 + 0.0001))));
      }
      
      return {
        "name": name, "cp": cp, "rsi": rsi, 
        "trend": cp > (closes.sublist(closes.length-20).reduce((a,b)=>a+b)/20) ? "BULL" : "BEAR"
      };
    } catch (_) { return null; }
  }

  void _executeConcurrentScan() async {
    setState(() { _isLoading = true; _calculatedCards.clear(); });
    String sentiment = await _calculateMacroSentiment();
    setState(() { _macroSentiment = sentiment; });
    for (var entry in _masterWatchlist.entries) {
      var m = await _processAssetMetrics(entry.key, entry.value);
      if (m != null && mounted) setState(() => _calculatedCards.add(m));
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121216),
      appBar: AppBar(title: const Text("QUANT CONFLUENCE WORKSTATION"), backgroundColor: const Color(0xFF1A1A22)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          ElevatedButton(onPressed: _isLoading ? null : _executeConcurrentScan, child: Text(_isLoading ? "Scanning..." : "LAUNCH STREAMING QUANT CONFLUENCE")),
          Expanded(child: ListView.builder(itemCount: _calculatedCards.length, itemBuilder: (_, i) => Card(color: const Color(0xFF1A1A22), child: ListTile(title: Text(_calculatedCards[i]['name'], style: const TextStyle(color: Colors.white)), subtitle: Text("Price: ${_calculatedCards[i]['cp']} | RSI: ${_calculatedCards[i]['rsi'].toStringAsFixed(1)} | Trend: ${_calculatedCards[i]['trend']}", style: const TextStyle(color: Colors.grey))))))
        ]),
      ),
    );
  }
}
