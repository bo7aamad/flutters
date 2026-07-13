import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: QuantWorkstation()));

class QuantWorkstation extends StatefulWidget {
  const QuantWorkstation({super.key});
  @override
  State<QuantWorkstation> createState() => _QuantWorkstationState();
}

class _QuantWorkstationState extends State<QuantWorkstation> {
  final _balanceController = TextEditingController(text: "1000");
  final _customTickerController = TextEditingController();
  final _emailController = TextEditingController();
  final _msgController = TextEditingController();
  bool _isLoading = false;
  String _macroSentiment = "NEUTRAL";
  final List<Map<String, dynamic>> _cards = [];

  final Map<String, String> _watchlist = {
    "NVIDIA": "NVDA", "TESLA": "TSLA", "APPLE": "AAPL", "AMD": "AMD", 
    "MICROSOFT": "MSFT", "AMAZON": "AMZN", "META": "META", "GOOGLE": "GOOGL", 
    "GOLD": "GC=F", "SILVER": "SI=F", "OIL": "CL=F", "EURUSD": "EURUSD=X"
  };

  Future<String> _getMacro() async {
    int bull = 0; int bear = 0;
    final feeds = ["https://finance.yahoo.com/rss/topstories", "https://rss.marketwatch.com/rss/topstories"];
    final reg = RegExp(r'<title>(.*?)</title>', caseSensitive: false);
    for (var url in feeds) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
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

  Future<Map<String, dynamic>?> _getAsset(String name, String ticker) async {
    final url = "https://query1.finance.yahoo.com/v8/finance/chart/$ticker?interval=4h&range=30d";
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body)['chart']['result'][0];
      final quote = data['indicators']['quote'][0];
      List<double> closes = (quote['close'] as List).where((e) => e != null).map((e) => (e as num).toDouble()).toList();
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
      
      return {"name": name, "cp": cp, "rsi": rsi, "trend": cp > (closes.sublist(closes.length-20).reduce((a,b)=>a+b)/20) ? "BULL" : "BEAR"};
    } catch (_) { return null; }
  }

  void _scan() async {
    setState(() { _isLoading = true; _cards.clear(); });
    String macro = await _getMacro();
    setState(() { _macroSentiment = macro; });
    for (var entry in _watchlist.entries) {
      var m = await _getAsset(entry.key, entry.value);
      if (m != null && mounted) {
        setState(() => _cards.add(m));
      }
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121216),
      appBar: AppBar(title: const Text("QUANT WORKSTATION")),
      body: Column(children: [
        ElevatedButton(onPressed: _isLoading ? null : _scan, child: Text(_isLoading ? "Scanning..." : "RUN SCAN")),
        Expanded(child: ListView.builder(itemCount: _cards.length, itemBuilder: (_, i) => Card(child: ListTile(title: Text(_cards[i]['name']), subtitle: Text("Price: ${_cards[i]['cp']} | RSI: ${_cards[i]['rsi'].toStringAsFixed(1)}")))))
      ])
    );
  }
}
