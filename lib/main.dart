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
  List<Map<String, dynamic>> _calculatedCards = [];

  final Map<String, String> _masterWatchlist = {
    "NVIDIA": "NVDA", "TESLA": "TSLA", "APPLE": "AAPL", "AMD": "AMD", 
    "MICROSOFT": "MSFT", "AMAZON": "AMZN", "META": "META", "GOOGLE": "GOOGL", 
    "NETFLIX": "NFLX", "BERKSHIRE": "BRK-B", "GOLD": "GC=F", "SILVER": "SI=F", 
    "PLATINUM": "PL=F", "CRUDE_OIL": "CL=F", "EURUSD": "EURUSD=X", 
    "GBPUSD": "GBPUSD=X", "USDJPY": "USDJPY=X", "AUDUSD": "AUDUSD=X", 
    "USDCAD": "USDCAD=X", "USDCHF": "USDCHF=X", "NZDUSD": "NZDUSD=X", 
    "EURGBP": "EURGBP=X", "EURJPY": "EURJPY=X", "GBPJPY": "GBPJPY=X", 
    "AUDJPY": "AUDJPY=X", "GBPAUD": "GBPAUD=X"
  };

  final Map<String, String> _headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
  };

  Future<String> _calculateMacroSentiment() async {
    int bull = 0; int bear = 0;
    final List<String> feeds = [
      "https://finance.yahoo.com/rss/topstories",
      "https://rss.marketwatch.com/rss/topstories"
    ];
    
    final RegExp titleRegex = RegExp(r'<title>(.*?)</title>', caseSensitive: false);
    final List<String> bearWords = ["inflation", "rate hike", "hawkish", "slowdown", "recession", "drop"];
    final List<String> bullWords = ["rate cut", "dovish", "gdp growth", "demand spike", "rally", "surge"];

    for (var url in feeds) {
      try {
        final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final matches = titleRegex.allMatches(res.body);
          int count = 0;
          for (var match in matches) {
            if (count > 4) break;
            String txt = (match.group(1) ?? "").toLowerCase();
            for (var w in bearWords) { if (txt.contains(w)) bear++; }
            for (var w in bullWords) { if (txt.contains(w)) bull++; }
            count++;
          }
        }
      } catch (_) {}
    }
    int total = bull + bear;
    if (total == 0) return "NEUTRAL";
    // FIXED: Locked down the required semicolon on this math calculation string
    double score = (bull - bear) / total;
    return score > 0.05 ? "BUY" : (score < -0.05 ? "SHORT" : "NEUTRAL");
  }

  Future<Map<String, dynamic>?> _processAssetMetrics(String name, String ticker) async {
    final url = "https://query1.finance.yahoo.com/v8/finance/chart/$ticker?interval=4h&range=30d";
    try {
      final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      
      final data = jsonDecode(res.body);
      final result = data['chart']['result'][0];
      final indicators = result['indicators']['quote'][0];
      
      List<double> highs = [];
      List<double> lows = [];
      List<double> closes = [];
      List<dynamic> rawVols = indicators['volume'] ?? [];

      List<dynamic> rawHighs = indicators['high'] ?? [];
      List<dynamic> rawLows = indicators['low'] ?? [];
      List<dynamic> rawCloses = indicators['close'] ?? [];

      for (int i = 0; i < rawCloses.length; i++) {
        if (rawHighs[i] != null && rawLows[i] != null && rawCloses[i] != null) {
          highs.add((rawHighs[i] as num).toDouble());
          lows.add((rawLows[i] as num).toDouble());
          closes.add((rawCloses[i] as num).toDouble());
        }
      }

      if (closes.length < 21) return null;
      double cp = closes.last;

      double gainSum = 0; double lossSum = 0;
      for (int i = closes.length - 14; i < closes.length; i++) {
        double diff = closes[i] - closes[i - 1];
        if (diff > 0) { gainSum += diff; } else { lossSum -= diff; }
      }
      double rs = (gainSum / 14) / math.max(lossSum / 14, 0.00001);
      double rsi = roundDouble(100 - (100 / (1 + rs)), 1);

      List<double> segment20 = closes.sublist(closes.length - 20);
      double sma20 = segment20.reduce((a, b) => a + b) / 20;
      double variance = segment20.map((x) => math.pow(x - sma20, 2)).reduce((a, b) => a + b) / 20;
      double std20 = math.sqrt(variance);
      double upperBB = sma20 + (std20 * 2);
      double lowerBB = sma20 - (std20 * 2);
      double bbPct = roundDouble(((cp - lowerBB) / math.max(upperBB - lowerBB, 0.01)) * 100, 1);

      double trSum = 0;
      for (int i = closes.length - 14; i < closes.length; i++) {
        double h = highs[i]; double l = lows[i]; double prevC = closes[i - 1];
        double tr = math.max(h - l, math.max((h - prevC).abs(), (l - prevC).abs()));
        trSum += tr;
      }
      double atr = trSum / 14;

      String rvolStr = "N/A";
      List<int> validVols = rawVols.where((v) => v != null && v > 0).map((v) => v as int).toList();
      if (validVols.length >= 20) {
        double avgVol = validVols.sublist(validVols.length - 20).reduce((a, b) => a + b) / 20;
        if (avgVol > 0) {
          rvolStr = "${roundDouble(validVols.last / avgVol, 1)}x";
        }
      }

      List<double> range20Highs = highs.sublist(highs.length - 20);
      List<double> range20Lows = lows.sublist(lows.length - 20);

      return {
        "name": name, "cp": cp, "rsi": rsi, "bbPct": bbPct, "atr": atr, "rvol": rvolStr,
        "techTrend": cp > sma20 ? "BUY" : "SHORT",
        "resis": range20Highs.reduce(math.max), "supp": range20Lows.reduce(math.min)
      };
    } catch (_) { return null; }
  }

  double roundDouble(double val, int places) {
    double mod = math.pow(10, places).toDouble();
    return ((val * mod).round().toDouble() / mod);
  }

  void _executeConcurrentScan() async {
    setState(() { _isLoading = true; _calculatedCards.clear(); });
    
    double capital = double.tryParse(_balanceController.text) ?? 1000.0;
    String sentiment = await _calculateMacroSentiment();
    setState(() { _macroSentiment = sentiment; });

    List<Future<Map<String, dynamic>?>> parallelPipelines = [];
    _masterWatchlist.forEach((name, ticker) {
      parallelPipelines.add(_processAssetMetrics(name, ticker));
    });

    final outputArrays = await Future.wait(parallelPipelines);

    for (var metrics in outputArrays) {
      if (metrics != null) { _compileRiskCard(metrics, capital); }
    }
    setState(() { _isLoading = false; });
  }

  void _injectAndScanCustomTicker() async {
    String sym = _customTickerController.text.trim().toUpperCase();
    if (sym.isEmpty) return;
    
    setState(() { _isLoading = true; });
    double capital = double.tryParse(_balanceController.text) ?? 1000.0;
    
    var customMetrics = await _processAssetMetrics(sym, sym);
    
    if (customMetrics != null) {
      setState(() {
        _compileRiskCard(customMetrics, capital);
        _customTickerController.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ticker Verification Failure: Symbol '$sym' unrecognized.")),
      );
    }
    setState(() { _isLoading = false; });
  }

  void _compileRiskCard(Map<String, dynamic> m, double capital) {
    String rsiBias = m['rsi'] < 45 ? "BUY" : (m['rsi'] > 55 ? "SHORT" : "NEUTRAL");
    double score = 0;
    if (_macroSentiment == "BUY") score += 1; if (_macroSentiment == "SHORT") score -= 1;
    if (rsiBias == "BUY") score += 1; if (rsiBias == "SHORT") score -= 1;
    if (m['techTrend'] == "BUY") score += 1.5; else score -= 1.5;

    String finalRec = score > 0 ? "BUY" : "SHORT";
    String name = m['name'];
    bool isFx = name.contains("USD") || name.contains("EUR") || name.contains("GBP") || name.contains("AUD") || name.contains("CAD") || name.contains("CHF") || name.contains("NZD");
    int dec = (isFx && !name.contains("JPY")) ? 4 : 2;

    double riskCapital = capital * 0.02;
    double atrBuffer = m['atr'] * 2.2;
    double entry = 0; double sl = 0; double tp = 0;

    if (finalRec == "BUY") {
      entry = roundDouble(m['supp'] * 0.998, dec);
      sl = roundDouble(entry - atrBuffer, dec);
      tp = roundDouble(entry + (m['atr'] * 4.0), dec);
    } else {
      entry = roundDouble(m['resis'] * 1.002, dec);
      sl = roundDouble(entry + atrBuffer, dec);
      tp = roundDouble(entry - (m['atr'] * 4.0), dec);
    }

    double rawUnits = riskCapital / math.max((entry - sl).abs(), 0.00001);
    String lotRecommendation = "";
    
    if (isFx) {
      double lots = rawUnits / 100000.0;
      lotRecommendation = "${roundDouble(lots, 2)} Standard Lots";
    } else if (name == "GOLD") {
      double lots = rawUnits / 100.0;
      lotRecommendation = "${roundDouble(lots, 2)} Contracts (Oz)";
    } else if (name == "CRUDE_OIL") {
      double lots = rawUnits / 1000.0;
      lotRecommendation = "${roundDouble(lots, 2)} Contracts (Bbl)";
    } else {
      lotRecommendation = "${rawUnits.round()} Shares / Lots";
    }

    _calculatedCards.add({
      "name": name, "rec": finalRec, "cp": m['cp'], "rsi": m['rsi'], "bbPct": m['bbPct'],
      "rvol": m['rvol'], "entry": entry, "sl": sl, "tp": tp, "lots": lotRecommendation, "dec": dec
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121216),
      appBar: AppBar(
        title: const Text("QUANT LAB INTERACTIVE MATRIX", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF1A1A22),
        centerTitle: true,
        elevation: 4,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _balanceController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Vault Capital Floor (\$)",
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A22),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(color: const Color(0xFF1A1A22), borderRadius: BorderRadius.circular(8)),
                  child: Text("MACRO: $_macroSentiment", style: TextStyle(color: _macroSentiment == "BUY" ? Colors.green : (_macroSentiment == "SHORT" ? Colors.red : Colors.amber), fontWeight: FontWeight.bold)),
                )
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customTickerController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Add custom ticker (e.g. AMD, META)",
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A22),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _injectAndScanCustomTicker,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Text("Scan Ticker", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                )
              ],
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _executeConcurrentScan,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007A53), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("RUN LIVE CONCURRENT SCAN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 15),
            Expanded(
              child: _calculatedCards.isEmpty 
                ? const Center(child: Text("Workstation Idle. Trigger master scan array.", style: TextStyle(color: Colors.grey, fontSize: 15)))
                : ListView.builder(
                    itemCount: _calculatedCards.length,
                    itemBuilder: (context, idx) {
                      final c = _calculatedCards[idx];
                      bool isBuy = c['rec'] == "BUY";
                      int dec = c['dec'];
                      return Card(
                        color: const Color(0xFF1A1A22),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: isBuy ? Colors.green.withOpacity(0.4) : Colors.red.withOpacity(0.4))),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(c['name'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                  Text(isBuy ? "BUY LIMIT" : "SHORT TRAP", style: TextStyle(color: isBuy ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 15)),
                                ],
                              ),
                              const Divider(color: Colors.grey, thickness: 0.3, height: 20),
                              Text("• Market Price : \$${c['cp'].toStringAsFixed(dec)} | RSI Momentum : ${c['rsi']} | BB Location : ${c['bbPct']}%", style: const TextStyle(color: Colors.white, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text("• Flow Volume (RVOL) : ${c['rvol']}", style: const TextStyle(color: Colors.white, fontSize: 14)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text("Entry: ${c['entry'].toStringAsFixed(dec)}", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 15),
                                  Text("SL: ${c['sl'].toStringAsFixed(dec)}", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 15),
                                  Text("TP: ${c['tp'].toStringAsFixed(dec)}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                child: Text("RECOMMENDED LOT SIZE: ${c['lots']}", style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            )
          ],
        ),
      ),
    );
  }
}

  final Map<String, String> _headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
  };

  Future<String> _calculateMacroSentiment() async {
    int bull = 0; int bear = 0;
    final List<String> feeds = [
      "https://finance.yahoo.com/rss/topstories",
      "https://rss.marketwatch.com/rss/topstories"
    ];
    
    final RegExp titleRegex = RegExp(r'<title>(.*?)</title>', caseSensitive: false);
    final List<String> bearWords = ["inflation", "rate hike", "hawkish", "slowdown", "recession", "drop"];
    final List<String> bullWords = ["rate cut", "dovish", "gdp growth", "demand spike", "rally", "surge"];

    for (var url in feeds) {
      try {
        final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final matches = titleRegex.allMatches(res.body);
          int count = 0;
          for (var match in matches) {
            if (count > 4) break;
            String txt = (match.group(1) ?? "").toLowerCase();
            for (var w in bearWords) { if (txt.contains(w)) bear++; }
            for (var w in bullWords) { if (txt.contains(w)) bull++; }
            count++;
          }
        }
      } catch (_) {}
    }
    int total = bull + bear;
    if (total == 0) return "NEUTRAL";
    // FIXED: Added missing semicolon at the end of this math statement
    double score = (bull - bear) / total;
    return score > 0.05 ? "BUY" : (score < -0.05 ? "SHORT" : "NEUTRAL");
  }

  Future<Map<String, dynamic>?> _processAssetMetrics(String name, String ticker) async {
    final url = "https://query1.finance.yahoo.com/v8/finance/chart/$ticker?interval=4h&range=30d";
    try {
      final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      
      final data = jsonDecode(res.body);
      final result = data['chart']['result'][0];
      final indicators = result['indicators']['quote'][0];
      
      List<double> highs = [];
      List<double> lows = [];
      List<double> closes = [];
      List<dynamic> rawVols = indicators['volume'] ?? [];

      List<dynamic> rawHighs = indicators['high'] ?? [];
      List<dynamic> rawLows = indicators['low'] ?? [];
      List<dynamic> rawCloses = indicators['close'] ?? [];

      for (int i = 0; i < rawCloses.length; i++) {
        if (rawHighs[i] != null && rawLows[i] != null && rawCloses[i] != null) {
          highs.add((rawHighs[i] as num).toDouble());
          lows.add((rawLows[i] as num).toDouble());
          closes.add((rawCloses[i] as num).toDouble());
        }
      }

      if (closes.length < 21) return null;
      double cp = closes.last;

      double gainSum = 0; double lossSum = 0;
      for (int i = closes.length - 14; i < closes.length; i++) {
        double diff = closes[i] - closes[i - 1];
        if (diff > 0) { gainSum += diff; } else { lossSum -= diff; }
      }
      double rs = (gainSum / 14) / math.max(lossSum / 14, 0.00001);
      double rsi = roundDouble(100 - (100 / (1 + rs)), 1);

      List<double> segment20 = closes.sublist(closes.length - 20);
      double sma20 = segment20.reduce((a, b) => a + b) / 20;
      double variance = segment20.map((x) => math.pow(x - sma20, 2)).reduce((a, b) => a + b) / 20;
      double std20 = math.sqrt(variance);
      double upperBB = sma20 + (std20 * 2) ;
      double lowerBB = sma20 - (std20 * 2);
      double bbPct = roundDouble(((cp - lowerBB) / math.max(upperBB - lowerBB, 0.01)) * 100, 1);

      double trSum = 0;
      for (int i = closes.length - 14; i < closes.length; i++) {
        double h = highs[i]; double l = lows[i]; double prevC = closes[i - 1];
        double tr = math.max(h - l, math.max((h - prevC).abs(), (l - prevC).abs()));
        trSum += tr;
      }
      double atr = trSum / 14;

      String rvolStr = "N/A";
      List<int> validVols = rawVols.where((v) => v != null && v > 0).map((v) => v as int).toList();
      if (validVols.length >= 20) {
        double avgVol = validVols.sublist(validVols.length - 20).reduce((a, b) => a + b) / 20;
        if (avgVol > 0) {
          rvolStr = "${roundDouble(validVols.last / avgVol, 1)}x";
        }
      }

      List<double> range20Highs = highs.sublist(highs.length - 20);
      List<double> range20Lows = lows.sublist(lows.length - 20);

      return {
        "name": name, "cp": cp, "rsi": rsi, "bbPct": bbPct, "atr": atr, "rvol": rvolStr,
        "techTrend": cp > sma20 ? "BUY" : "SHORT",
        "resis": range20Highs.reduce(math.max), "supp": range20Lows.reduce(math.min)
      };
    } catch (_) { return null; }
  }

  double roundDouble(double val, int places) {
    double mod = math.pow(10, places).toDouble();
    return ((val * mod).round().toDouble() / mod);
  }

  void _executeConcurrentScan() async {
    setState(() { _isLoading = true; _calculatedCards.clear(); });
    
    double capital = double.tryParse(_balanceController.text) ?? 1000.0;
    String sentiment = await _calculateMacroSentiment();
    setState(() { _macroSentiment = sentiment; });

    List<Future<Map<String, dynamic>?>> parallelPipelines = [];
    _masterWatchlist.forEach((name, ticker) {
      parallelPipelines.add(_processAssetMetrics(name, ticker));
    });

    final outputArrays = await Future.wait(parallelPipelines);

    for (var metrics in outputArrays) {
      if (metrics != null) { _compileRiskCard(metrics, capital); }
    }
    setState(() { _isLoading = false; });
  }

  void _injectAndScanCustomTicker() async {
    String sym = _customTickerController.text.trim().toUpperCase();
    if (sym.isEmpty) return;
    
    setState(() { _isLoading = true; });
    double capital = double.tryParse(_balanceController.text) ?? 1000.0;
    
    var customMetrics = await _processAssetMetrics(sym, sym);
    
    if (customMetrics != null) {
      setState(() {
        _compileRiskCard(customMetrics, capital);
        _customTickerController.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ticker Verification Failure: Symbol '$sym' unrecognized.")),
      );
    }
    setState(() { _isLoading = false; });
  }

  void _compileRiskCard(Map<String, dynamic> m, double capital) {
    String rsiBias = m['rsi'] < 45 ? "BUY" : (m['rsi'] > 55 ? "SHORT" : "NEUTRAL");
    double score = 0;
    if (_macroSentiment == "BUY") score += 1; if (_macroSentiment == "SHORT") score -= 1;
    if (rsiBias == "BUY") score += 1; if (rsiBias == "SHORT") score -= 1;
    if (m['techTrend'] == "BUY") score += 1.5; else score -= 1.5;

    String finalRec = score > 0 ? "BUY" : "SHORT";
    String name = m['name'];
    bool isFx = name.contains("USD") || name.contains("EUR") || name.contains("GBP") || name.contains("AUD") || name.contains("CAD") || name.contains("CHF") || name.contains("NZD");
    int dec = (isFx && !name.contains("JPY")) ? 4 : 2;

    double riskCapital = capital * 0.02;
    double atrBuffer = m['atr'] * 2.2;
    double entry = 0; double sl = 0; double tp = 0;

    if (finalRec == "BUY") {
      entry = roundDouble(m['supp'] * 0.998, dec);
      sl = roundDouble(entry - atrBuffer, dec);
      tp = roundDouble(entry + (m['atr'] * 4.0), dec);
    } else {
      entry = roundDouble(m['resis'] * 1.002, dec);
      sl = roundDouble(entry + atrBuffer, dec);
      tp = roundDouble(entry - (m['atr'] * 4.0), dec);
    }

    double rawUnits = riskCapital / math.max((entry - sl).abs(), 0.00001);
    String lotRecommendation = "";
    
    if (isFx) {
      double lots = rawUnits / 100000.0;
      lotRecommendation = "${roundDouble(lots, 2)} Standard Lots";
    } else if (name == "GOLD") {
      double lots = rawUnits / 100.0;
      lotRecommendation = "${roundDouble(lots, 2)} Contracts (Oz)";
    } else if (name == "CRUDE_OIL") {
      double lots = rawUnits / 1000.0;
      lotRecommendation = "${roundDouble(lots, 2)} Contracts (Bbl)";
    } else {
      lotRecommendation = "${rawUnits.round()} Shares / Lots";
    }

    _calculatedCards.add({
      "name": name, "rec": finalRec, "cp": m['cp'], "rsi": m['rsi'], "bbPct": m['bbPct'],
      "rvol": m['rvol'], "entry": entry, "sl": sl, "tp": tp, "lots": lotRecommendation, "dec": dec
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121216),
      appBar: AppBar(
        title: const Text("QUANT LAB INTERACTIVE MATRIX", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF1A1A22),
        centerTitle: true,
        elevation: 4,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _balanceController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Vault Capital Floor (\$)",
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A22),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(color: const Color(0xFF1A1A22), borderRadius: BorderRadius.circular(8)),
                  child: Text("MACRO: $_macroSentiment", style: TextStyle(color: _macroSentiment == "BUY" ? Colors.green : (_macroSentiment == "SHORT" ? Colors.red : Colors.amber), fontWeight: FontWeight.bold)),
                )
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customTickerController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Add custom ticker (e.g. AMD, META)",
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A22),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _injectAndScanCustomTicker,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Text("Scan Ticker", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                )
              ],
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _executeConcurrentScan,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007A53), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("RUN LIVE CONCURRENT SCAN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 15),
            Expanded(
              child: _calculatedCards.isEmpty 
                ? const Center(child: Text("Workstation Idle. Trigger master scan array.", style: TextStyle(color: Colors.grey, fontSize: 15)))
                : ListView.builder(
                    itemCount: _calculatedCards.length,
                    itemBuilder: (context, idx) {
                      final c = _calculatedCards[idx];
                      bool isBuy = c['rec'] == "BUY";
                      int dec = c['dec'];
                      return Card(
                        color: const Color(0xFF1A1A22),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: isBuy ? Colors.green.withOpacity(0.4) : Colors.red.withOpacity(0.4))),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(c['name'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                  Text(isBuy ? "BUY LIMIT" : "SHORT TRAP", style: TextStyle(color: isBuy ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 15)),
                                ],
                              ),
                              const Divider(color: Colors.grey, thickness: 0.3, height: 20),
                              Text("• Market Price : \$${c['cp'].toStringAsFixed(dec)} | RSI Momentum : ${c['rsi']} | BB Location : ${c['bbPct']}%", style: const TextStyle(color: Colors.white, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text("• Flow Volume (RVOL) : ${c['rvol']}", style: const TextStyle(color: Colors.white, fontSize: 14)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text("Entry: ${c['entry'].toStringAsFixed(dec)}", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 15),
                                  Text("SL: ${c['sl'].toStringAsFixed(dec)}", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 15),
                                  Text("TP: ${c['tp'].toStringAsFixed(dec)}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                child: Text("RECOMMENDED LOT SIZE: ${c['lots']}", style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            )
          ],
        ),
      ),
    );
  }
}

  final Map<String, String> _headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
  };

  Future<String> _calculateMacroSentiment() async {
    int bull = 0; int bear = 0;
    final List<String> feeds = [
      "https://finance.yahoo.com/rss/topstories",
      "https://rss.marketwatch.com/rss/topstories"
    ];
    
    final RegExp titleRegex = RegExp(r'<title>(.*?)</title>', caseSensitive: false);
    final List<String> bearWords = ["inflation", "rate hike", "hawkish", "slowdown", "recession", "drop"];
    final List<String> bullWords = ["rate cut", "dovish", "gdp growth", "demand spike", "rally", "surge"];

    for (var url in feeds) {
      try {
        final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final matches = titleRegex.allMatches(res.body);
          int count = 0;
          for (var match in matches) {
            if (count > 4) break;
            String txt = (match.group(1) ?? "").toLowerCase();
            for (var w in bearWords) { if (txt.contains(w)) bear++; }
            for (var w in bullWords) { if (txt.contains(w)) bull++; }
            count++;
          }
        }
      } catch (_) {}
    }
    int total = bull + bear;
    if (total == 0) return "NEUTRAL";
    double score = (bull - bear) / total
    return score > 0.05 ? "BUY" : (score < -0.05 ? "SHORT" : "NEUTRAL");
  }

  Future<Map<String, dynamic>?> _processAssetMetrics(String name, String ticker) async {
    final url = "https://query1.finance.yahoo.com/v8/finance/chart/$ticker?interval=4h&range=30d";
    try {
      final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      
      final data = jsonDecode(res.body);
      final result = data['chart']['result'][0];
      final indicators = result['indicators']['quote'][0];
      
      List<double> highs = [];
      List<double> lows = [];
      List<double> closes = [];
      List<dynamic> rawVols = indicators['volume'] ?? [];

      List<dynamic> rawHighs = indicators['high'] ?? [];
      List<dynamic> rawLows = indicators['low'] ?? [];
      List<dynamic> rawCloses = indicators['close'] ?? [];

      for (int i = 0; i < rawCloses.length; i++) {
        if (rawHighs[i] != null && rawLows[i] != null && rawCloses[i] != null) {
          highs.add((rawHighs[i] as num).toDouble());
          lows.add((rawLows[i] as num).toDouble());
          closes.add((rawCloses[i] as num).toDouble());
        }
      }

      if (closes.length < 21) return null;
      double cp = closes.last;

      double gainSum = 0; double lossSum = 0;
      for (int i = closes.length - 14; i < closes.length; i++) {
        double diff = closes[i] - closes[i - 1];
        if (diff > 0) { gainSum += diff; } else { lossSum -= diff; }
      }
      double rs = (gainSum / 14) / math.max(lossSum / 14, 0.00001);
      double rsi = roundDouble(100 - (100 / (1 + rs)), 1);

      List<double> segment20 = closes.sublist(closes.length - 20);
      double sma20 = segment20.reduce((a, b) => a + b) / 20;
      double variance = segment20.map((x) => math.pow(x - sma20, 2)).reduce((a, b) => a + b) / 20;
      double std20 = math.sqrt(variance);
      double upperBB = sma20 + (std20 * 2);
      double lowerBB = sma20 - (std20 * 2);
      double bbPct = roundDouble(((cp - lowerBB) / math.max(upperBB - lowerBB, 0.01)) * 100, 1);

      double trSum = 0;
      for (int i = closes.length - 14; i < closes.length; i++) {
        double h = highs[i]; double l = lows[i]; double prevC = closes[i - 1];
        double tr = math.max(h - l, math.max((h - prevC).abs(), (l - prevC).abs()));
        trSum += tr;
      }
      double atr = trSum / 14;

      String rvolStr = "N/A";
      List<int> validVols = rawVols.where((v) => v != null && v > 0).map((v) => v as int).toList();
      if (validVols.length >= 20) {
        double avgVol = validVols.sublist(validVols.length - 20).reduce((a, b) => a + b) / 20;
        if (avgVol > 0) {
          rvolStr = "${roundDouble(validVols.last / avgVol, 1)}x";
        }
      }

      List<double> range20Highs = highs.sublist(highs.length - 20);
      List<double> range20Lows = lows.sublist(lows.length - 20);

      return {
        "name": name, "cp": cp, "rsi": rsi, "bbPct": bbPct, "atr": atr, "rvol": rvolStr,
        "techTrend": cp > sma20 ? "BUY" : "SHORT",
        "resis": range20Highs.reduce(math.max), "supp": range20Lows.reduce(math.min)
      };
    } catch (_) { return null; }
  }

  double roundDouble(double val, int places) {
    double mod = math.pow(10, places).toDouble();
    return ((val * mod).round().toDouble() / mod);
  }

  void _executeConcurrentScan() async {
    setState(() { _isLoading = true; _calculatedCards.clear(); });
    
    double capital = double.tryParse(_balanceController.text) ?? 1000.0;
    String sentiment = await _calculateMacroSentiment();
    setState(() { _macroSentiment = sentiment; });

    List<Future<Map<String, dynamic>?>> parallelPipelines = [];
    _masterWatchlist.forEach((name, ticker) {
      parallelPipelines.add(_processAssetMetrics(name, ticker));
    });

    final outputArrays = await Future.wait(parallelPipelines);

    for (var metrics in outputArrays) {
      if (metrics != null) { _compileRiskCard(metrics, capital); }
    }
    setState(() { _isLoading = false; });
  }

  void _injectAndScanCustomTicker() async {
    String sym = _customTickerController.text.trim().toUpperCase();
    if (sym.isEmpty) return;
    
    setState(() { _isLoading = true; });
    double capital = double.tryParse(_balanceController.text) ?? 1000.0;
    
    var customMetrics = await _processAssetMetrics(sym, sym);
    
    if (customMetrics != null) {
      setState(() {
        _compileRiskCard(customMetrics, capital);
        _customTickerController.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ticker Verification Failure: Symbol '$sym' unrecognized.")),
      );
    }
    setState(() { _isLoading = false; });
  }

  void _compileRiskCard(Map<String, dynamic> m, double capital) {
    String rsiBias = m['rsi'] < 45 ? "BUY" : (m['rsi'] > 55 ? "SHORT" : "NEUTRAL");
    double score = 0;
    if (_macroSentiment == "BUY") score += 1; if (_macroSentiment == "SHORT") score -= 1;
    if (rsiBias == "BUY") score += 1; if (rsiBias == "SHORT") score -= 1;
    if (m['techTrend'] == "BUY") score += 1.5; else score -= 1.5;

    String finalRec = score > 0 ? "BUY" : "SHORT";
    String name = m['name'];
    bool isFx = name.contains("USD") || name.contains("EUR") || name.contains("GBP") || name.contains("AUD") || name.contains("CAD") || name.contains("CHF") || name.contains("NZD");
    int dec = (isFx && !name.contains("JPY")) ? 4 : 2;

    double riskCapital = capital * 0.02;
    double atrBuffer = m['atr'] * 2.2;
    double entry = 0; double sl = 0; double tp = 0;

    if (finalRec == "BUY") {
      entry = roundDouble(m['supp'] * 0.998, dec);
      sl = roundDouble(entry - atrBuffer, dec);
      tp = roundDouble(entry + (m['atr'] * 4.0), dec);
    } else {
      entry = roundDouble(m['resis'] * 1.002, dec);
      sl = roundDouble(entry + atrBuffer, dec);
      tp = roundDouble(entry - (m['atr'] * 4.0), dec);
    }

    double rawUnits = riskCapital / math.max((entry - sl).abs(), 0.00001);
    String lotRecommendation = "";
    
    if (isFx) {
      double lots = rawUnits / 100000.0;
      lotRecommendation = "${roundDouble(lots, 2)} Standard Lots";
    } else if (name == "GOLD") {
      double lots = rawUnits / 100.0;
      lotRecommendation = "${roundDouble(lots, 2)} Contracts (Oz)";
    } else if (name == "CRUDE_OIL") {
      double lots = rawUnits / 1000.0;
      lotRecommendation = "${roundDouble(lots, 2)} Contracts (Bbl)";
    } else {
      lotRecommendation = "${rawUnits.round()} Shares / Lots";
    }

    _calculatedCards.add({
      "name": name, "rec": finalRec, "cp": m['cp'], "rsi": m['rsi'], "bbPct": m['bbPct'],
      "rvol": m['rvol'], "entry": entry, "sl": sl, "tp": tp, "lots": lotRecommendation, "dec": dec
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121216),
      appBar: AppBar(
        title: const Text("QUANT LAB INTERACTIVE MATRIX", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF1A1A22),
        centerTitle: true,
        elevation: 4,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _balanceController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Vault Capital Floor (\$)",
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A22),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(color: const Color(0xFF1A1A22), borderRadius: BorderRadius.circular(8)),
                  child: Text("MACRO: $_macroSentiment", style: TextStyle(color: _macroSentiment == "BUY" ? Colors.green : (_macroSentiment == "SHORT" ? Colors.red : Colors.amber), fontWeight: FontWeight.bold)),
                )
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customTickerController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Add custom ticker (e.g. AMD, META)",
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A22),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _injectAndScanCustomTicker,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Text("Scan Ticker", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                )
              ],
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _executeConcurrentScan,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007A53), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("RUN LIVE CONCURRENT SCAN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 15),
            Expanded(
              child: _calculatedCards.isEmpty 
                ? const Center(child: Text("Workstation Idle. Trigger master scan array.", style: TextStyle(color: Colors.grey, fontSize: 15)))
                : ListView.builder(
                    itemCount: _calculatedCards.length,
                    itemBuilder: (context, idx) {
                      final c = _calculatedCards[idx];
                      bool isBuy = c['rec'] == "BUY";
                      int dec = c['dec'];
                      return Card(
                        color: const Color(0xFF1A1A22),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: isBuy ? Colors.green.withOpacity(0.4) : Colors.red.withOpacity(0.4))),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(c['name'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                  Text(isBuy ? "BUY LIMIT" : "SHORT TRAP", style: TextStyle(color: isBuy ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 15)),
                                ],
                              ),
                              const Divider(color: Colors.grey, thickness: 0.3, height: 20),
                              // FIXED: Shifted non-existent Colors.white90 strictly to clean Colors.white constants
                              Text("• Market Price : \$${c['cp'].toStringAsFixed(dec)} | RSI Momentum : ${c['rsi']} | BB Location : ${c['bbPct']}%", style: const TextStyle(color: Colors.white, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text("• Flow Volume (RVOL) : ${c['rvol']}", style: const TextStyle(color: Colors.white, fontSize: 14)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text("Entry: ${c['entry'].toStringAsFixed(dec)}", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 15),
                                  Text("SL: ${c['sl'].toStringAsFixed(dec)}", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 15),
                                  Text("TP: ${c['tp'].toStringAsFixed(dec)}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                child: Text("RECOMMENDED LOT SIZE: ${c['lots']}", style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            )
          ],
        ),
      ),
    );
  }
}
  };

  final Map<String, String> _headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
  };

  // Asynchronous Macro News Extraction Engine
  Future<String> _calculateMacroSentiment() async {
    int bull = 0; int bear = 0;
    final List<String> feeds = [
      "https://finance.yahoo.com/rss/topstories",
      "https://rss.marketwatch.com/rss/topstories"
    ];
    
    final RegExp titleRegex = RegExp(r'<title>(.*?)</title>', caseSensitive: false);
    final List<String> bearWords = ["inflation", "rate hike", "hawkish", "slowdown", "recession", "drop"];
    final List<String> bullWords = ["rate cut", "dovish", "gdp growth", "demand spike", "rally", "surge"];

    for (var url in feeds) {
      try {
        final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final matches = titleRegex.allMatches(res.body);
          int count = 0;
          for (var match in matches) {
            if (count > 4) break;
            String txt = (match.group(1) ?? "").toLowerCase();
            for (var w in bearWords) { if (txt.contains(w)) bear++; }
            for (var w in bullWords) { if (txt.contains(w)) bull++; }
            count++;
          }
        }
      } catch (_) {}
    }
    int total = bull + bear;
    if (total == 0) return "NEUTRAL";
    double score = (bull - bear) / total;
    return score > 0.05 ? "BUY" : (score < -0.05 ? "SHORT" : "NEUTRAL");
  }

  // Pure Math Vector Pipeline Processing Unit
  Future<Map<String, dynamic>?> _processAssetMetrics(String name, String ticker) async {
    final url = "https://query1.finance.yahoo.com/v8/finance/chart/$ticker?interval=4h&range=30d";
    try {
      final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      
      final data = jsonDecode(res.body);
      final result = data['chart']['result'][0];
      final indicators = result['indicators']['quote'][0];
      
      List<double> highs = [];
      List<double> lows = [];
      List<double> closes = [];
      List<dynamic> rawVols = indicators['volume'] ?? [];

      List<dynamic> rawHighs = indicators['high'] ?? [];
      List<dynamic> rawLows = indicators['low'] ?? [];
      List<dynamic> rawCloses = indicators['close'] ?? [];

      for (int i = 0; i < rawCloses.length; i++) {
        if (rawHighs[i] != null && rawLows[i] != null && rawCloses[i] != null) {
          highs.add((rawHighs[i] as num).toDouble());
          lows.add((rawLows[i] as num).toDouble());
          closes.add((rawCloses[i] as num).toDouble());
        }
      }

      if (closes.length < 21) return null;
      double cp = closes.last;

      // 1. RSI Vector Engine
      double gainSum = 0; double lossSum = 0;
      for (int i = closes.length - 14; i < closes.length; i++) {
        double diff = closes[i] - closes[i - 1];
        if (diff > 0) { gainSum += diff; } else { lossSum -= diff; }
      }
      double rs = (gainSum / 14) / math.max(lossSum / 14, 0.00001);
      double rsi = roundDouble(100 - (100 / (1 + rs)), 1);

      // 2. SMA & Bollinger Band Location Engine
      List<double> segment20 = closes.sublist(closes.length - 20);
      double sma20 = segment20.reduce((a, b) => a + b) / 20;
      double variance = segment20.map((x) => math.pow(x - sma20, 2)).reduce((a, b) => a + b) / 20;
      double std20 = math.sqrt(variance);
      double upperBB = sma20 + (std20 * 2);
      double lowerBB = sma20 - (std20 * 2);
      double bbPct = roundDouble(((cp - lowerBB) / math.max(upperBB - lowerBB, 0.01)) * 100, 1);

      // 3. Average True Range (ATR) Vector Engine
      double trSum = 0;
      for (int i = closes.length - 14; i < closes.length; i++) {
        double h = highs[i]; double l = lows[i]; double prevC = closes[i - 1];
        double tr = math.max(h - l, math.max((h - prevC).abs(), (l - prevC).abs()));
        trSum += tr;
      }
      double atr = trSum / 14;

      // 4. Volume Signature Analysis Panel
      String rvolStr = "N/A";
      List<int> validVols = rawVols.where((v) => v != null && v > 0).map((v) => v as int).toList();
      if (validVols.length >= 20) {
        double avgVol = validVols.sublist(validVols.length - 20).reduce((a, b) => a + b) / 20;
        if (avgVol > 0) {
          rvolStr = "${roundDouble(validVols.last / avgVol, 1)}x";
        }
      }

      // 5. Native Boundary Resistance Trackers
      List<double> range20Highs = highs.sublist(highs.length - 20);
      List<double> range20Lows = lows.sublist(lows.length - 20);

      return {
        "name": name, "cp": cp, "rsi": rsi, "bbPct": bbPct, "atr": atr, "rvol": rvolStr,
        "techTrend": cp > sma20 ? "BUY" : "SHORT",
        "resis": range20Highs.reduce(math.max), "supp": range20Lows.reduce(math.min)
      };
    } catch (_) { return null; }
  }

  double roundDouble(double val, int places) {
    double mod = math.pow(10, places).toDouble();
    return ((val * mod).round().toDouble() / mod);
  }

  // Execution Master Control Pipeline Loop
  void _executeConcurrentScan() async {
    setState(() { _isLoading = true; _calculatedCards.clear(); });
    
    double capital = double.tryParse(_balanceController.text) ?? 1000.0;
    String sentiment = await _calculateMacroSentiment();
    setState(() { _macroSentiment = sentiment; });

    // Parallel Worker Stream Execution
    List<Future<Map<String, dynamic>?>> parallelPipelines = [];
    _masterWatchlist.forEach((name, ticker) {
      parallelPipelines.add(_processAssetMetrics(name, ticker));
    });

    final outputArrays = await Future.wait(parallelPipelines);

    for (var metrics in outputArrays) {
      if (metrics != null) { _compileRiskCard(metrics, capital); }
    }
    setState(() { _isLoading = false; });
  }

  // Dynamic Custom Ticker Injection Engine
  void _injectAndScanCustomTicker() async {
    String sym = _customTickerController.text.trim().toUpperCase();
    if (sym.isEmpty) return;
    
    setState(() { _isLoading = true; });
    double capital = double.tryParse(_balanceController.text) ?? 1000.0;
    
    // Process asset metrics natively on the fly
    var customMetrics = await _processAssetMetrics(sym, sym);
    
    if (customMetrics != null) {
      setState(() {
        _compileRiskCard(customMetrics, capital);
        _customTickerController.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ticker Verification Failure: Symbol '$sym' unrecognized.")),
      );
    }
    setState(() { _isLoading = false; });
  }

  void _compileRiskCard(Map<String, dynamic> m, double capital) {
    String rsiBias = m['rsi'] < 45 ? "BUY" : (m['rsi'] > 55 ? "SHORT" : "NEUTRAL");
    double score = 0;
    if (_macroSentiment == "BUY") score += 1; if (_macroSentiment == "SHORT") score -= 1;
    if (rsiBias == "BUY") score += 1; if (rsiBias == "SHORT") score -= 1;
    if (m['techTrend'] == "BUY") score += 1.5; else score -= 1.5;

    String finalRec = score > 0 ? "BUY" : "SHORT";
    String name = m['name'];
    bool isFx = name.contains("USD") || name.contains("EUR") || name.contains("GBP") || name.contains("AUD") || name.contains("CAD") || name.contains("CHF") || name.contains("NZD");
    int dec = (isFx && !name.contains("JPY")) ? 4 : 2;

    double riskCapital = capital * RISK_PERCENT;
    double atrBuffer = m['atr'] * 2.2;
    double entry = 0; double sl = 0; double tp = 0;

    if (finalRec == "BUY") {
      entry = roundDouble(m['supp'] * 0.998, dec);
      sl = roundDouble(entry - atrBuffer, dec);
      tp = roundDouble(entry + (m['atr'] * 4.0), dec);
    } else {
      entry = roundDouble(m['resis'] * 1.002, dec);
      sl = roundDouble(entry + atrBuffer, dec);
      tp = roundDouble(entry - (m['atr'] * 4.0), dec);
    }

    double rawUnits = riskCapital / math.max((entry - sl).abs(), 0.00001);
    String lotRecommendation = "";
    
    // SMART CALIBRATION SIZING LAYER
    if (isFx) {
      double lots = rawUnits / 100000.0;
      lotRecommendation = "${roundDouble(lots, 2)} Standard Lots";
    } else if (name == "GOLD") {
      double lots = rawUnits / 100.0;
      lotRecommendation = "${roundDouble(lots, 2)} Contracts (Oz)";
    } else if (name == "CRUDE_OIL") {
      double lots = rawUnits / 1000.0;
      lotRecommendation = "${roundDouble(lots, 2)} Contracts (Bbl)";
    } else {
      // Equity/Stock specification sizing structure logic
      lotRecommendation = "${rawUnits.round()} Shares / Lots";
    }

    _calculatedCards.add({
      "name": name, "rec": finalRec, "cp": m['cp'], "rsi": m['rsi'], "bbPct": m['bbPct'],
      "rvol": m['rvol'], "entry": entry, "sl": sl, "tp": tp, "lots": lotRecommendation, "dec": dec
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121216),
      appBar: AppBar(
        title: const Text("QUANT LAB INTERACTIVE MATRIX", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        backgroundColor: const Color(0xFF1A1A22),
        centerTitle: true,
        elevation: 4,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Top Frame Dashboard Control Center Panel
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _balanceController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Vault Capital Floor (\$)",
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A22),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(color: const Color(0xFF1A1A22), borderRadius: BorderRadius.circular(8)),
                  child: Text("MACRO: $_macroSentiment", style: TextStyle(color: _macroSentiment == "BUY" ? Colors.green : (_macroSentiment == "SHORT" ? Colors.red : Colors.amber), fontWeight: FontWeight.bold)),
                )
              ],
            ),
            const SizedBox(height: 12),
            
            // Dynamic Custom Stock Search/Input Module Node
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customTickerController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Add custom ticker (e.g. AMD, META)",
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A22),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _injectAndScanCustomTicker,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Text("Scan Ticker", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                )
              ],
            ),
            const SizedBox(height: 15),
            
            // Execution Launch Command Bar Trigger Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _executeConcurrentScan,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007A53), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("RUN LIVE CONCURRENT SCAN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 15),
            
            // Responsive Vector Output Card List Deck
            Expanded(
              child: _calculatedCards.isEmpty 
                ? const Center(child: Text("Workstation Idle. Trigger master scan array.", style: TextStyle(color: Colors.grey, fontSize: 15)))
                : ListView.builder(
                    itemCount: _calculatedCards.length,
                    itemBuilder: (context, idx) {
                      final c = _calculatedCards[idx];
                      bool isBuy = c['rec'] == "BUY";
                      int dec = c['dec'];
                      return Card(
                        color: const Color(0xFF1A1A22),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: isBuy ? Colors.green.withOpacity(0.4) : Colors.red.withOpacity(0.4))),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(c['name'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                  Text(isBuy ? "BUY LIMIT" : "SHORT TRAP", style: TextStyle(color: isBuy ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 15)),
                                ],
                              ),
                              const Divider(color: Colors.grey, thickness: 0.3, height: 20),
                              Text("• Market Price : \$${c['cp'].toStringAsFixed(dec)} | RSI Momentum : ${c['rsi']} | BB Location : ${c['bbPct']}%", style: const TextStyle(color: Colors.white90, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text("• Flow Volume (RVOL) : ${c['rvol']}", style: const TextStyle(color: Colors.white90, fontSize: 14)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text("Entry: ${c['entry'].toStringAsFixed(dec)}", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 15),
                                  Text("SL: ${c['sl'].toStringAsFixed(dec)}", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 15),
                                  Text("TP: ${c['tp'].toStringAsFixed(dec)}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                child: Text("RECOMMENDED LOT SIZE: ${c['lots']}", style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            )
          ],
        ),
      ),
    );
  }
}
