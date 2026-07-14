import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui; // Required for the graph gradient

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
    "NETFLIX": "NFLX", "BERKSHIRE": "BRK/B", "GOLD": "XAU/USD", "SILVER": "XAG/USD", 
    "PLATINUM": "XPT/USD", "CRUDE_OIL": "WTICO/USD", "EURUSD": "EUR/USD", 
    "GBPUSD": "GBP/USD", "USDJPY": "USD/JPY", "AUDUSD": "AUD/USD", 
    "USDCAD": "USD/CAD", "USDCHF": "USD/CHF", "NZDUSD": "NZD/USD", 
    "EURGBP": "EUR/GBP", "EURJPY": "EUR/JPY", "GBPJPY": "GBP/JPY", 
    "AUDJPY": "AUD/JPY", "GBPAUD": "GBP/AUD"
  };

  final Map<String, String> _headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
  };

  final String _apiKey = "a9eeefb4ba19452b91adb75330fb05ae";

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

  double _parseDouble(dynamic val) {
    if (val == null) return 0.0;
    return double.tryParse(val.toString()) ?? 0.0;
  }

  Future<Map<String, dynamic>?> _processAssetMetrics(String name, String ticker) async {
    final url4h = "https://api.twelvedata.com/time_series?symbol=$ticker&interval=4h&outputsize=200&apikey=$_apiKey";
    final url1d = "https://api.twelvedata.com/time_series?symbol=$ticker&interval=1day&outputsize=100&apikey=$_apiKey";
    
    try {
      final res4h = await http.get(Uri.parse(url4h)).timeout(const Duration(seconds: 5));
      final res1d = await http.get(Uri.parse(url1d)).timeout(const Duration(seconds: 5));
      
      final data4h = jsonDecode(res4h.body);
      final data1d = jsonDecode(res1d.body);
      
      if (data4h['status'] == 'error' || data1d['status'] == 'error') return null;
      if (data4h['values'] == null || data1d['values'] == null) return null;

      List<dynamic> raw4h = (data4h['values'] as List).reversed.toList();
      List<dynamic> raw1d = (data1d['values'] as List).reversed.toList();
      
      if (raw4h.length < 26 || raw1d.length < 26) return null;

      List<double> closes4h = raw4h.map((e) => _parseDouble(e['close'])).toList();
      List<double> highs4h = raw4h.map((e) => _parseDouble(e['high'])).toList();
      List<double> lows4h = raw4h.map((e) => _parseDouble(e['low'])).toList();
      List<double> vols4h = raw4h.map((e) => _parseDouble(e['volume'])).toList();
      
      List<double> closes1d = raw1d.map((e) => _parseDouble(e['close'])).toList();

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

      double trSum = 0; int count = 0;
      for (int i = closes4h.length - 14; i < closes4h.length; i++) {
        if (i > 0) {
          double h = highs4h[i];
          double l = lows4h[i];
          double tr = math.max(h - l, math.max((h - closes4h[i - 1]).abs(), (l - closes4h[i - 1]).abs()));
          trSum += tr; count++;
        }
      }
      double atr = count > 0 ? trSum / count : cp * 0.01;

      double resis = highs4h.isNotEmpty ? highs4h.sublist(math.max(0, highs4h.length - 20)).reduce(math.max) : cp;
      double supp = lows4h.isNotEmpty ? lows4h.sublist(math.max(0, lows4h.length - 20)).reduce(math.min) : cp;

      double refVol = vols4h.length > 1 ? vols4h[vols4h.length - 2] : (vols4h.isNotEmpty ? vols4h.last : 0);
      double smaVol5 = _calculateLastSMA(vols4h, 5); 
      String volTrend = "LOW";
      
      if (refVol == 0 || smaVol5 == 0) {
        volTrend = "N/A"; 
      } else if (refVol >= (smaVol5 * 0.60)) { 
        volTrend = "HIGH";
      }

      // GRAPH DATA: Extract the last 30 periods for the sparkline
      List<double> sparklineData = closes4h.length >= 30 ? closes4h.sublist(closes4h.length - 30) : closes4h;

      return {
        "name": name, "cp": cp, "rsi": rsi, "bbPct": bbPct, "atr": atr, "macdHist": macdHist,
        "trend4h": trend4h, "trend1d": trend1d, "resis": resis, "supp": supp, "volTrend": volTrend,
        "sparkline": sparklineData // Exporting graph coordinates
      };
    } catch (_) { return null; }
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ticker Verification Failure: Check Twelve Data format (e.g. BTC/USD)")));
    }
    setState(() { _isLoading = false; });
  }

  void _compileRiskCard(Map<String, dynamic> m, double capital) {
    double rsiVal = (m['rsi'] as num).toDouble();
    double bbVal = (m['bbPct'] as num).toDouble();
    double macdVal = (m['macdHist'] as num).toDouble();
    String t4h = m['trend4h'] as String;
    String t1d = m['trend1d'] as String;
    String vTrend = (m['volTrend'] ?? "LOW") as String;

    double score = 0;
    if (_macroSentiment == "BUY") score += 1.0; else if (_macroSentiment == "SHORT") score -= 1.0;
    
    if (t4h == "BULL") score += 1.0; else score -= 1.0;
    if (t1d == "BULL") score += 1.5; else score -= 1.5;
    if (macdVal > 0) score += 0.5; else score -= 0.5;
    
    if (rsiVal < 45) score += 1.0; if (rsiVal > 55) score -= 1.0;
    if (bbVal < 30) score += 1.0; if (bbVal > 70) score -= 1.0;

    String finalRec = "WAIT";
    
    if (score >= 2.0) finalRec = "BUY";
    else if (score <= -2.0) finalRec = "SHORT";

    if (t1d == "BEAR" && finalRec == "BUY") finalRec = "WAIT";
    if (t1d == "BULL" && finalRec == "SHORT") finalRec = "WAIT";
    if (vTrend == "LOW" && finalRec != "WAIT") finalRec = "WAIT";

    String name = m['name'] as String;
    bool isFx = name.contains("USD") || name.contains("EUR") || name.contains("GBP") || name.contains("AUD") || name.contains("CAD") || name.contains("CHF") || name.contains("NZD");
    int dec = (isFx && !name.contains("JPY")) ? 4 : 2;

    double riskCapital = capital * 0.02;
    double atrVal = (m['atr'] as num).toDouble();
    double entry = (m['cp'] as num).toDouble(); 
    double supp = (m['supp'] as num).toDouble();
    double resis = (m['resis'] as num).toDouble();
    double sl = 0; 
    double tp = 0;

    if (finalRec == "BUY") {
      sl = math.min(entry - (atrVal * 2.0), supp - (atrVal * 0.5)); 
      tp = entry + ((entry - sl).abs() * 2.0); 
    } else if (finalRec == "SHORT") {
      sl = math.max(entry + (atrVal * 2.0), resis + (atrVal * 0.5)); 
      tp = entry - ((sl - entry).abs() * 2.0);
    } else {
      sl = entry - (atrVal * 2.0); 
      tp = entry + (atrVal * 2.0);
    }

    entry = roundDouble(entry, dec); sl = roundDouble(sl, dec); tp = roundDouble(tp, dec);
    double rawUnits = riskCapital / math.max((entry - sl).abs(), 0.00001);
    String lotRecommendation = "";
    
    if (finalRec == "WAIT") {
      lotRecommendation = "STANDBY - NO ENTRY";
    } else if (isFx) {
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
      "trend4h": t4h, "trend1d": t1d, "macd": macdVal > 0 ? "BULL" : "BEAR", "volTrend": vTrend,
      "score": score,
      "sparkline": m['sparkline'] // Pass graph data
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
                      hintText: "Inject TD asset (e.g. BTC/USD)", hintStyle: const TextStyle(color: Colors.grey),
                      filled: true, fillColor: const Color(0xFF1A1A22), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _injectAndScanCustomTicker,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const Text("Scan", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
                      bool isWait = c['rec'] == "WAIT";
                      int dec = c['dec'] as int;
                      double currentPrice = c['cp'] as double;
                      String assetName = c['name'] as String;
                      String t1d = c['trend1d'] as String;
                      String t4h = c['trend4h'] as String;
                      String macd = c['macd'] as String;
                      String vol = c['volTrend'] as String;
                      String rsi = c['rsi'].toString();
                      String bb = c['bbPct'].toString();
                      String entry = c['entry'].toString();
                      String sl = c['sl'].toString();
                      String tp = c['tp'].toString();
                      String positionSize = c['lots'] as String;
                      String scoreStr = (c['score'] as double).toStringAsFixed(1);
                      List<double> sparklineData = c['sparkline'] as List<double>;

                      // Determine Graph Color based on Signal
                      Color sigColor = isWait ? Colors.grey : (isBuy ? Colors.greenAccent : Colors.redAccent);

                      return Card(
                        color: const Color(0xFF1A1A22), margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8), 
                          side: BorderSide(color: isWait ? Colors.grey.withOpacity(0.3) : (isBuy ? Colors.green.withOpacity(0.4) : Colors.red.withOpacity(0.4)))
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(assetName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  // NEW FEATURE: NATIVE SPARKLINE GRAPH
                                  SizedBox(
                                    width: 80, height: 25,
                                    child: CustomPaint(painter: SparklinePainter(sparklineData, sigColor)),
                                  ),
                                  const SizedBox(width: 14),
                                  Text(isWait ? "WAIT ($scoreStr)" : (isBuy ? "BUY ($scoreStr)" : "SHORT ($scoreStr)"), 
                                       style: TextStyle(color: sigColor, fontWeight: FontWeight.bold, fontSize: 14)),
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
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: vol == "HIGH" ? Colors.purple.withOpacity(0.15) : Colors.grey.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                    child: Text("VOL: " + vol, style: TextStyle(color: vol == "HIGH" ? Colors.purpleAccent : Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text("• Price : \$ " + currentPrice.toStringAsFixed(dec) + " | RSI : " + rsi + " | BB Loc : " + bb + "%", style: const TextStyle(color: Colors.white, fontSize: 13)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text("Entry: " + entry, style: TextStyle(color: isWait ? Colors.grey : Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
                                  const SizedBox(width: 14),
                                  Text("SL: " + sl, style: TextStyle(color: isWait ? Colors.grey : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                  const SizedBox(width: 14),
                                  Text("TP: " + tp, style: TextStyle(color: isWait ? Colors.grey : Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity, padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                child: Text("RECOMMENDED POSITION SIZING: " + positionSize, style: TextStyle(color: isWait ? Colors.grey : Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12)),
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

// THE QUANTITATIVE SPARKLINE GENERATOR 
class SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  SparklinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double min = data.reduce(math.min);
    final double max = data.reduce(math.max);
    final double range = (max - min) == 0 ? 1 : (max - min);
    final double xStep = size.width / (data.length - 1);

    final Path linePath = Path();
    for (int i = 0; i < data.length; i++) {
      final double x = i * xStep;
      final double y = size.height - ((data[i] - min) / range * size.height);
      if (i == 0) linePath.moveTo(x, y); else linePath.lineTo(x, y);
    }

    // Creates the glowing gradient fill beneath the graph
    final Path fillPath = Path.from(linePath);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    final Paint fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, size.height),
        [color.withOpacity(0.4), color.withOpacity(0.0)],
      );
      
    final Paint linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
