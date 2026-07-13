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
      "https://rss.marketwatch.com/rss/topstories",
      "https://search.cnbc.com/rs/search/view.xml?partnerId=2000&keywords=macroeconomics",
      "https://www.investing.com/rss/news_285.rss", 
      "https://www.investing.com/rss/news_95.rss",  
      "https://rsshub.app/twitter/user/Fxhedgsteam", 
    ];
    
    final RegExp titleRegex = RegExp(r'<title>(.*?)</title>', caseSensitive: false);
    final List<String> bearWords = ["inflation", "rate hike", "hawkish", "slowdown", "recession", "drop", "bearish", "crash", "contraction"];
    final List<String> bullWords = ["rate cut", "dovish", "gdp growth", "demand spike", "rally", "surge", "bullish", "expansion"];

    for (var url in feeds) {
      try {
        final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final matches = titleRegex.allMatches(res.body);
          int count = 0;
          for (var match in matches) {
            if (count > 8) break;
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
    return score > 0.03 ? "BUY" : (score < -0.03 ? "SHORT" : "NEUTRAL");
  }

  Future<Map<String, dynamic>?> _processAssetMetrics(String name, String ticker) async {
    final url4h = "https://query1.finance.yahoo.com/v8/finance/chart/$ticker?interval=4h&range=30d";
    final url1d = "https://query1.finance.yahoo.com/v8/finance/chart/$ticker?interval=1d&range=90d";
    
    try {
      final res4h = await http.get(Uri.parse(url4h), headers: _headers).timeout(const Duration(seconds: 4));
      final res1d = await http.get(Uri.parse(url1d), headers: _headers).timeout(const Duration(seconds: 4));
      
      if (res4h.statusCode != 200 || res1d.statusCode != 200) return null;
      
      final data4h = jsonDecode(res4h.body)['chart']['result'][0];
      final ind4h = data4h['indicators']['quote'][0];
      List<double> closes4h = _extractCloses(ind4h);
      
      final data1d = jsonDecode(res1d.body)['chart']['result'][0];
      final ind1d = data1d['indicators']['quote'][0];
      List<double> closes1d = _extractCloses(ind1d);
      
      if (closes4h.length < 26 || closes1d.length < 26) return null;
      double cp = closes4h.last;

      double ema12 = _calculateLastEMA(closes4h, 12);
      double ema26 = _calculateLastEMA(closes4h, 26);
      double macdLine = ema12 - ema26;
      List<double> macdHistory = [];
      for (int i = 26; i <= closes4h.length; i++) {
        double e12 = _calculateLastEMA(closes4h.sublist(0, i), 12);
        double e26 = _calculateLastEMA(closes4h.sublist(0, i), 26);
        macdHistory.add(e12 - e26);
      }
      double macdSignal = _calculateLastEMA(macdHistory, 9);
      double macdHist = macdLine - macdSignal;

      double sma20_4h = _calculateLastSMA(closes4h, 20);
      double sma20_1d = _calculateLastSMA(closes1d, 20);
      String trend4h = cp > sma20_4h ? "BULL" : "BEAR";
      String trend1d = closes1d.last > sma20_1d ? "BULL" : "BEAR";

      double rsi = _calculateLastRSI(closes4h, 14);
      List<double> seg20 = closes4h.sublist(closes4h.length - 20);
      double variance = seg20.map((x) => math.pow(x - sma20_4h, 2)).reduce((a, b) => a + b) / 20;
      double std20 = math.sqrt(variance);
      double upperBB = sma20_4h + (std20 * 2);
      double lowerBB = sma20_4h - (std20 * 2);
      double bbPct = ((cp - lowerBB) / math.max(upperBB - lowerBB, 0.01)) * 100;

      final indHighs = ind4h['high'] ?? [];
      final indLows = ind4h['low'] ?? [];
      double trSum = 0; int count = 0;
      for (int i = closes4h.length - 14; i < closes4h.length; i++) {
        if (i < indHighs.length && i < indLows.length && i > 0 && indHighs[i] != null && indLows[i] != null) {
          double h = (indHighs[i] as num).toDouble();
          double l = (indLows[i] as num).toDouble();
          double tr = math.max(h - l, math.max((h - closes4h[i - 1]).abs(), (l - closes4h[i - 1]).abs()));
          trSum += tr; count++;
        }
      }
      double atr = count > 0 ? trSum / count : cp * 0.01;

      List<double> rawHighs = ind4h['high'].where((x) => x != null).map<double>((x) => (x as num).toDouble()).toList();
      List<double> rawLows = ind4h['low'].where((x) => x != null).map<double>((x) => (x as num).toDouble()).toList();
      double resis = rawHighs.isNotEmpty ? rawHighs.sublist(math.max(0, rawHighs.length - 20)).reduce(math.max) : cp;
      double supp = rawLows.isNotEmpty ? rawLows.sublist(math.max(0, rawLows.length - 20)).reduce(math.min) : cp;

      return {
        "name": name, "cp": cp, "rsi": rsi, "bbPct": bbPct, "atr": atr, "macdHist": macdHist,
        "trend4h": trend4h, "trend1d": trend1d, "resis": resis, "supp": supp
      };
    } catch (_) { return null; }
  }

  List<double> _extractCloses(Map<String, dynamic> indicators) {
    List<dynamic> rawCloses = indicators['close'] ?? [];
    List<double> closes = [];
    for (var c in rawCloses) { if (c != null) { closes.add((c as num).toDouble()); } }
    return closes;
  }

  double _calculateLastSMA(List<double> data, int period) {
    if (data.length < period) return data.isEmpty ? 0.0 : data.last;
    return data.sublist(data.length - period).reduce((a, b) => a + b) / period;
  }

  double _calculateLastEMA(List<double> data, int period) {
    if (data.length < period) return data.isEmpty ? 0.0 : data.last;
    double k = 2 / (period + 1);
    double ema = data.sublist(0, period).reduce((a, b) => a + b) / period;
    for (int i = period; i < data.length; i++) { ema = (data[i] * k) + (ema * (1 - k)); }
    return ema;
  }

  double _calculateLastRSI(List<double> closes, int period) {
    if (closes.length <= period) return 50.0;
    double gainSum = 0; double lossSum = 0;
    for (int i = closes.length - period; i < closes.length; i++) {
      double diff = closes[i] - closes[i - 1];
      if (diff > 0) { gainSum += diff; } else { lossSum -= diff; }
    }
    return 100 - (100 / (1 + ((gainSum / period) / math.max(lossSum / period, 0.00001))));
  }

  double roundDouble(double val, int places) {
    double mod = math.pow(10, places).toDouble();
    return ((val * mod).round().toDouble() / mod);
  }

  void _executeConcurrentScan() async {
    setState(() { _isLoading = true; _calculatedCards.clear(); });
    
    String sentiment = await _calculateMacroSentiment();
    setState(() { _macroSentiment = sentiment; });
    double capital = double.tryParse(_balanceController.text) ?? 1000.0;

    int completedCount = 0;
    for (var entry in _masterWatchlist.entries) {
      _processAssetMetrics(entry.key, entry.value).then((metrics) {
        if (metrics != null && mounted) {
          setState(() { _compileRiskCard(metrics, capital); });
        }
        completedCount++;
        if (completedCount == _masterWatchlist.length) {
          setState(() { _isLoading = false; });
        }
      });
    }
  }

  void _injectAndScanCustomTicker() async {
    String sym = _customTickerController.text.trim().toUpperCase();
    if (sym.isEmpty) return;
    setState(() { _isLoading = true; });
    double capital = double.tryParse(_balanceController.text) ?? 1000.0;
    
    var customMetrics = await _processAssetMetrics(sym, sym);
    if (customMetrics != null && mounted) {
      setState(() { _compileRiskCard(customMetrics, capital); _customTickerController.clear(); });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ticker Verification Failure: Symbol '$sym' unrecognized.")));
    }
    setState(() { _isLoading = false; });
  }

  void _compileRiskCard(Map<String, dynamic> m, double capital) {
    double rsiVal = (m['rsi'] as num).toDouble();
    double bbVal = (m['bbPct'] as num).toDouble();
    double macdVal = (m['macdHist'] as num).toDouble();
    String t4h = m['trend4h'] as String;
    String t1d = m['trend1d'] as String;

    double score = 0;
    if (_macroSentiment == "BUY") score += 1.0; if (_macroSentiment == "SHORT") score -= 1.0;
    if (t4h == "BULL") score += 1.0; else score -= 1.0;
    if (t1d == "BULL") score += 1.5; else score -= 1.5;
    if (macdVal > 0) score += 0.5; else score -= 0.5;
    if (rsiVal < 40) score += 1.0; if (rsiVal > 60) score -= 1.0;

    String finalRec = score > 0.5 ? "BUY" : "SHORT";
    String name = m['name'] as String;
    bool isFx = name.contains("USD") || name.contains("EUR") || name.contains("GBP") || name.contains("AUD") || name.contains("CAD") || name.contains("CHF") || name.contains("NZD");
    int dec = (isFx && !name.contains("JPY")) ? 4 : 2;

    double riskCapital = capital * 0.02;
    double atrBuffer = (m['atr'] as num).toDouble() * 2.0;
    double entry = (m['cp'] as num).toDouble(); 
    double sl = 0; 
    double tp = 0;

    if (finalRec == "BUY") {
      sl = entry - atrBuffer; tp = entry + ((m['atr'] as num).toDouble() * 3.5);
    } else {
      sl = entry + atrBuffer; tp = entry - ((m['atr'] as num).toDouble() * 3.5);
    }

    entry = roundDouble(entry, dec); sl = roundDouble(sl, dec); tp = roundDouble(tp, dec);
    double rawUnits = riskCapital / math.max((entry - sl).abs(), 0.00001);
    String lotRecommendation = "";
    
    if (isFx) {
      lotRecommendation = "${roundDouble(rawUnits / 100000.0, 2)} Standard Lots";
    } else if (name == "GOLD") {
      lotRecommendation = "${roundDouble(rawUnits / 100.0, 2)} Contracts (Oz)";
    } else if (name == "CRUDE_OIL") {
      lotRecommendation = "${roundDouble(rawUnits / 1000.0, 2)} Contracts (Bbl)";
    } else {
      lotRecommendation = "${rawUnits.round()} Shares / Lots";
    }

    _calculatedCards.add({
      "name": name, "rec": finalRec, "cp": entry, "rsi": roundDouble(rsiVal, 1), "bbPct": roundDouble(bbVal, 1),
      "entry": entry, "sl": sl, "tp": tp, "lots": lotRecommendation, "dec": dec,
      "trend4h": t4h, "trend1d": t1d, "macd": macdVal > 0 ? "BULL" : "BEAR"
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121216),
      appBar: AppBar(
        title: const Text("QUANT CONFLUENCE WORKSTATION", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF1A1A22), centerTitle: true, elevation: 4,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _balanceController, keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Vault Capital Floor (\$)", labelStyle: const TextStyle(color: Colors.grey),
                      filled: true, fillColor: const Color(0xFF1A1A22), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                    controller: _customTickerController, style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Inject asset token (e.g. AMD, META)", hintStyle: const TextStyle(color: Colors.grey),
                      filled: true, fillColor: const Color(0xFF1A1A22), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _executeConcurrentScan,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF007A53), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("LAUNCH STREAMING QUANT CONFLUENCE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 15),
            Expanded(
              child: _calculatedCards.isEmpty 
                ? const Center(child: Text("Terminals Idle. Awaiting streaming vectors...", style: TextStyle(color: Colors.grey, fontSize: 14)))
                : ListView.builder(
                    itemCount: _calculatedCards.length,
                    itemBuilder: (context, idx) {
                      final c = _calculatedCards[idx];
                      bool isBuy = c['rec'] == "BUY"; 
                      int dec = c['dec'] as int;
                      double currentPrice = c['cp'] as double;
                      String assetName = c['name'] as String;
                      String t1d = c['trend1d'] as String;
                      String t4h = c['trend4h'] as String;
                      String macd = c['macd'] as String;
                      String rsi = c['rsi'].toString();
                      String bb = c['bbPct'].toString();
                      String entry = c['entry'].toString();
                      String sl = c['sl'].toString();
                      String tp = c['tp'].toString();
                      String positionSize = c['lots'] as String;

                      return Card(
                        color: const Color(0xFF1A1A22), margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: isBuy ? Colors.green.withOpacity(0.4) : Colors.red.withOpacity(0.4))),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(assetName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                  Text(isBuy ? "BUY SIGNAL" : "SHORT SIGNAL", style: TextStyle(color: isBuy ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                              const Divider(color: Colors.grey, thickness: 0.3, height: 16),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: t1d == "BULL" ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                    child: Text("1D: " + t1d, style: TextStyle(color: t1d == "BULL" ? Colors.green : Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: t4h == "BULL" ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                    child: Text("4H: " + t4h, style: TextStyle(color: t4h == "BULL" ? Colors.green : Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: macd == "BULL" ? Colors.blue.withOpacity(0.15) : Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                    child: Text("MACD: " + macd, style: TextStyle(color: macd == "BULL" ? Colors.blueAccent : Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text("• Price : \$ " + currentPrice.toStringAsFixed(dec) + " | RSI : " + rsi + " | BB Loc : " + bb + "%", style: const TextStyle(color: Colors.white, fontSize: 13)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text("Entry: " + entry, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
                                  const SizedBox(width: 14),
                                  Text("SL: " + sl, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                  const SizedBox(width: 14),
                                  Text("TP: " + tp, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity, padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                child: Text("RECOMMENDED POSITION SIZING: " + positionSize, style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8.0, bottom: 2.0),
              child: Text(
                "Built by M.AlSalamah",
                style: TextStyle(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 1.2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
