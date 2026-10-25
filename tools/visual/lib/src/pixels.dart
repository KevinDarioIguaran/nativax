import 'dart:math' as math;
import 'dart:typed_data';

import 'color.dart';
import 'model.dart';
import 'png.dart';

class RegionSample {
  const RegionSample({
    required this.chrome,
    required this.nativa,
    required this.meanDeltaE,
    required this.samples,
  });

  final Rgb chrome;
  final Rgb nativa;
  final double meanDeltaE;
  final int samples;
}

class PixelTotals {
  const PixelTotals({
    required this.width,
    required this.height,
    required this.pixels,
    required this.mismatched,
    required this.exact,
    required this.meanDeltaE,
    required this.maxDeltaE,
    required this.mae,
    required this.buckets,
    required this.inkPixels,
    required this.inkMismatched,
    required this.chromeInkPixels,
    required this.nativaInkPixels,
  });

  final int width;
  final int height;
  final int pixels;
  final int mismatched;
  final int exact;
  final double meanDeltaE;
  final double maxDeltaE;
  final double mae;
  final Map<String, int> buckets;

  /// Pixels that are not the page background in at least one screenshot.
  final int inkPixels;
  final int inkMismatched;
  final int chromeInkPixels;
  final int nativaInkPixels;

  double get exactPct => pixels == 0 ? 0 : 100 * exact / pixels;
  double get mismatchedPct => pixels == 0 ? 0 : 100 * mismatched / pixels;
  double get inkMismatchPct =>
      inkPixels == 0 ? 0 : 100 * inkMismatched / inkPixels;

  Map<String, Object> toJson() => {
    'width': width,
    'height': height,
    'pixels': pixels,
    'mismatchedPixels': mismatched,
    'mismatchedPct': _round(mismatchedPct, 2),
    'exactPixels': exact,
    'exactPct': _round(exactPct, 2),
    'meanDeltaE': _round(meanDeltaE, 2),
    'maxDeltaE': _round(maxDeltaE, 2),
    'meanAbsoluteError': _round(mae, 2),
    'buckets': buckets,
    'inkPixels': inkPixels,
    'inkMismatched': inkMismatched,
    'inkMismatchPct': _round(inkMismatchPct, 2),
    'chromeInkPixels': chromeInkPixels,
    'nativaInkPixels': nativaInkPixels,
  };
}

class RowStat {
  const RowStat(this.y, this.meanDeltaE, this.mismatched);
  final int y;
  final double meanDeltaE;
  final int mismatched;
  Map<String, Object> toJson() => {
    'y': y,
    'meanDeltaE': _round(meanDeltaE, 2),
    'mismatched': mismatched,
  };
}

class TileStat {
  const TileStat(this.x, this.y, this.size, this.meanDeltaE, this.mismatched);
  final int x;
  final int y;
  final int size;
  final double meanDeltaE;
  final int mismatched;
  Map<String, Object> toJson() => {
    'x': x,
    'y': y,
    'size': size,
    'meanDeltaE': _round(meanDeltaE, 2),
    'mismatched': mismatched,
  };
}

class PixelComparison {
  const PixelComparison({
    required this.totals,
    required this.rows,
    required this.worstTiles,
    required this.diff,
  });

  final PixelTotals totals;
  final List<RowStat> rows;
  final List<TileStat> worstTiles;
  final RasterImage diff;
}

/// Compares every pixel of the common area of both screenshots. Pixels with
/// ΔE > 2 count as mismatched; ΔE ≤ 2 is imperceptible in the CIE76 scale.
PixelComparison comparePixels(
  RasterImage chrome,
  RasterImage nativa, {
  int tileSize = 16,
  int worstTileCount = 12,
}) {
  final width = math.min(chrome.width, nativa.width);
  final height = math.min(chrome.height, nativa.height);
  final diff = Uint8List(width * height * 4);
  final buckets = <String, int>{
    'de<=2': 0,
    '2<de<=5': 0,
    '5<de<=10': 0,
    '10<de<=20': 0,
    'de>20': 0,
  };
  final rows = <RowStat>[];
  final tilesX = (width + tileSize - 1) ~/ tileSize;
  final tilesY = (height + tileSize - 1) ~/ tileSize;
  final tileSums = Float64List(tilesX * tilesY);
  final tileCounts = Int32List(tilesX * tilesY);

  final background = _pageBackground(chrome, width, height);

  var mismatched = 0;
  var exact = 0;
  var deltaSum = 0.0;
  var maxDelta = 0.0;
  var absoluteError = 0;
  var inkPixels = 0;
  var inkMismatched = 0;
  var chromeInkPixels = 0;
  var nativaInkPixels = 0;

  for (var y = 0; y < height; y++) {
    var rowMismatched = 0;
    var rowDelta = 0.0;
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final r1 = chrome.rgba[i],
          g1 = chrome.rgba[i + 1],
          b1 = chrome.rgba[i + 2];
      final r2 = nativa.rgba[i],
          g2 = nativa.rgba[i + 1],
          b2 = nativa.rgba[i + 2];
      final de = deltaE(r1, g1, b1, r2, g2, b2);
      final chromeInk =
          deltaE(r1, g1, b1, background.r, background.g, background.b) > 5;
      final nativaInk =
          deltaE(r2, g2, b2, background.r, background.g, background.b) > 5;
      if (chromeInk) chromeInkPixels++;
      if (nativaInk) nativaInkPixels++;
      if (chromeInk || nativaInk) {
        inkPixels++;
        if (de > 2) inkMismatched++;
      }
      deltaSum += de;
      rowDelta += de;
      if (de > maxDelta) maxDelta = de;
      absoluteError += (r1 - r2).abs() + (g1 - g2).abs() + (b1 - b2).abs();

      if (de <= 2) {
        exact++;
        buckets['de<=2'] = buckets['de<=2']! + 1;
        diff[i] = 245;
        diff[i + 1] = 245;
        diff[i + 2] = 245;
      } else {
        mismatched++;
        rowMismatched++;
        if (de <= 5) {
          buckets['2<de<=5'] = buckets['2<de<=5']! + 1;
        } else if (de <= 10) {
          buckets['5<de<=10'] = buckets['5<de<=10']! + 1;
        } else if (de <= 20) {
          buckets['10<de<=20'] = buckets['10<de<=20']! + 1;
        } else {
          buckets['de>20'] = buckets['de>20']! + 1;
        }
        final intensity = ((de - 2) / 24).clamp(0.0, 1.0);
        diff[i] = 255;
        diff[i + 1] = (255 * (1 - intensity)).round();
        diff[i + 2] = (255 * (1 - intensity)).round();
      }
      diff[i + 3] = 255;

      final tx = x ~/ tileSize;
      final ty = y ~/ tileSize;
      final t = ty * tilesX + tx;
      tileSums[t] += de;
      tileCounts[t] += 1;
    }
    rows.add(RowStat(y, height == 0 ? 0 : rowDelta / width, rowMismatched));
  }

  final tileStats = <TileStat>[];
  for (var ty = 0; ty < tilesY; ty++) {
    for (var tx = 0; tx < tilesX; tx++) {
      final t = ty * tilesX + tx;
      final count = tileCounts[t];
      if (count == 0) continue;
      final mean = tileSums[t] / count;
      if (mean <= 2) continue;
      tileStats.add(
        TileStat(
          tx * tileSize,
          ty * tileSize,
          tileSize,
          mean,
          (mean > 5 ? 1 : 0) * count,
        ),
      );
    }
  }
  tileStats.sort((a, b) => b.meanDeltaE.compareTo(a.meanDeltaE));

  final pixels = width * height;
  return PixelComparison(
    totals: PixelTotals(
      width: width,
      height: height,
      pixels: pixels,
      mismatched: mismatched,
      exact: exact,
      meanDeltaE: pixels == 0 ? 0 : deltaSum / pixels,
      maxDeltaE: maxDelta,
      mae: pixels == 0 ? 0 : absoluteError / (pixels * 3),
      inkPixels: inkPixels,
      inkMismatched: inkMismatched,
      chromeInkPixels: chromeInkPixels,
      nativaInkPixels: nativaInkPixels,
      buckets: buckets,
    ),
    rows: rows,
    worstTiles: tileStats.take(worstTileCount).toList(growable: false),
    diff: RasterImage(width, height, diff),
  );
}

/// Samples an element interior on a regular grid. The box is inset by one
/// pixel so borders and antialiased edges do not dominate the sample.
RegionSample? sampleRegion(
  RasterImage chrome,
  RasterImage nativa,
  BoxRect box, {
  int maxSamples = 64,
}) {
  final inner = box.inset(1);
  if (inner.width < 1 || inner.height < 1) return null;
  final left = inner.x.floor();
  final top = inner.y.floor();
  final right = inner.right.ceil();
  final bottom = inner.bottom.ceil();
  if (left < 0 || top < 0 || right > chrome.width || bottom > chrome.height)
    return null;
  if (right > nativa.width || bottom > nativa.height) return null;

  final w = right - left;
  final h = bottom - top;
  if (w <= 0 || h <= 0) return null;
  final stride = math.max(1, math.sqrt(w * h / maxSamples).floor());
  var samples = 0;
  var sumR1 = 0, sumG1 = 0, sumB1 = 0;
  var sumR2 = 0, sumG2 = 0, sumB2 = 0;
  var sumDelta = 0.0;
  for (var y = top; y < bottom; y += stride) {
    for (var x = left; x < right; x += stride) {
      final i = (y * chrome.width + x) * 4;
      final r1 = chrome.rgba[i],
          g1 = chrome.rgba[i + 1],
          b1 = chrome.rgba[i + 2];
      final j = (y * nativa.width + x) * 4;
      final r2 = nativa.rgba[j],
          g2 = nativa.rgba[j + 1],
          b2 = nativa.rgba[j + 2];
      sumR1 += r1;
      sumG1 += g1;
      sumB1 += b1;
      sumR2 += r2;
      sumG2 += g2;
      sumB2 += b2;
      sumDelta += deltaE(r1, g1, b1, r2, g2, b2);
      samples++;
    }
  }
  if (samples == 0) return null;
  return RegionSample(
    chrome: Rgb(
      (sumR1 / samples).round(),
      (sumG1 / samples).round(),
      (sumB1 / samples).round(),
    ),
    nativa: Rgb(
      (sumR2 / samples).round(),
      (sumG2 / samples).round(),
      (sumB2 / samples).round(),
    ),
    meanDeltaE: sumDelta / samples,
    samples: samples,
  );
}

class PaletteColor {
  const PaletteColor(this.color, this.share);
  final Rgb color;
  final double share;
}

class ColorComparison {
  const ColorComparison({
    required this.chromeMean,
    required this.nativaMean,
    required this.meanDeltaE,
    required this.paletteDeltaE,
    required this.score,
    required this.chromePalette,
    required this.nativaPalette,
  });

  final Rgb chromeMean;
  final Rgb nativaMean;
  final double meanDeltaE;
  final double paletteDeltaE;

  /// 0..1: 60 % dominant-palette agreement, 40 % mean-colour agreement.
  final double score;
  final List<PaletteColor> chromePalette;
  final List<PaletteColor> nativaPalette;
}

/// Returns the most frequent colours of a box, quantized to 5 bits per
/// channel so antialiasing variations collapse into the same bucket.
List<PaletteColor> dominantColors(
  RasterImage image,
  BoxRect box, {
  int maxColors = 5,
}) {
  final bounds = BoxRect(0, 0, image.width.toDouble(), image.height.toDouble());
  final inner = box.inset(1).intersect(bounds);
  if (inner.width < 1 || inner.height < 1) return const [];
  final left = inner.x.floor();
  final top = inner.y.floor();
  final right = inner.right.ceil().clamp(left + 1, image.width);
  final bottom = inner.bottom.ceil().clamp(top + 1, image.height);
  final counts = <int, int>{};
  final sums = <int, List<int>>{};
  var total = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final i = (y * image.width + x) * 4;
      final r = image.rgba[i];
      final g = image.rgba[i + 1];
      final b = image.rgba[i + 2];
      final key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      counts[key] = (counts[key] ?? 0) + 1;
      final acc = sums.putIfAbsent(key, () => [0, 0, 0]);
      acc[0] += r;
      acc[1] += g;
      acc[2] += b;
      total++;
    }
  }
  final keys = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return [
    for (final key in keys.take(maxColors))
      PaletteColor(
        Rgb(
          sums[key]![0] ~/ counts[key]!,
          sums[key]![1] ~/ counts[key]!,
          sums[key]![2] ~/ counts[key]!,
        ),
        counts[key]! / total,
      ),
  ];
}

/// Shift-invariant colour comparison: each element is sampled inside its own
/// rendered box, so a moved element is a layout problem, not a colour problem.
ColorComparison? compareColors(
  RasterImage chrome,
  RasterImage nativa,
  BoxRect chromeBox,
  BoxRect nativaBox,
) {
  if (chromeBox.isEmpty || nativaBox.isEmpty) return null;
  final chromeMean = averageColor(chrome, chromeBox);
  final nativaMean = averageColor(nativa, nativaBox);
  if (chromeMean == null || nativaMean == null) return null;
  final chromePalette = dominantColors(chrome, chromeBox);
  final nativaPalette = dominantColors(nativa, nativaBox);
  if (chromePalette.isEmpty || nativaPalette.isEmpty) return null;

  final meanDelta = deltaE(
    chromeMean.r,
    chromeMean.g,
    chromeMean.b,
    nativaMean.r,
    nativaMean.g,
    nativaMean.b,
  );
  final paletteDelta = _paletteDistance(chromePalette, nativaPalette);
  final score = 0.4 * deltaEScore(meanDelta) + 0.6 * deltaEScore(paletteDelta);
  return ColorComparison(
    chromeMean: chromeMean,
    nativaMean: nativaMean,
    meanDeltaE: meanDelta,
    paletteDeltaE: paletteDelta,
    score: score,
    chromePalette: chromePalette,
    nativaPalette: nativaPalette,
  );
}

double _paletteDistance(List<PaletteColor> a, List<PaletteColor> b) {
  final left = _significantPalette(a);
  final right = _significantPalette(b);
  var sum = 0.0;
  var weight = 0.0;

  void accumulate(List<PaletteColor> from, List<PaletteColor> to) {
    for (final color in from) {
      var nearest = double.infinity;
      var nearestShare = 0.0;
      for (final other in to) {
        final d = deltaE(
          color.color.r,
          color.color.g,
          color.color.b,
          other.color.r,
          other.color.g,
          other.color.b,
        );
        if (d < nearest) {
          nearest = d;
          nearestShare = other.share;
        }
      }
      if (nearest <= 5) {
        // Same colour: what matters is how much of the element it covers.
        // `{99 % white, 1 % blue}` vs `{60 % white, 40 % blue}` are different
        // even though both palettes contain the same two colours.
        final sharePenalty = (color.share - nearestShare).abs() * 50;
        final w = (color.share + nearestShare) / 2;
        sum += sharePenalty * w;
        weight += w;
      } else {
        // No equivalent colour on the other side.
        sum += math.min(nearest, 100) * color.share;
        weight += color.share;
      }
    }
  }

  accumulate(left, right);
  accumulate(right, left);
  return weight == 0 ? 0 : sum / weight;
}

/// Drops palette entries below 2 %: they are almost always antialiasing or a
/// rounded corner and must not dominate the comparison.
List<PaletteColor> _significantPalette(List<PaletteColor> palette) {
  final kept = palette.where((c) => c.share >= 0.02).toList();
  final total = kept.fold<double>(0, (sum, c) => sum + c.share);
  if (total <= 0) return palette;
  return [for (final c in kept) PaletteColor(c.color, c.share / total)];
}

/// Mean colour of a box, used for palette reports.
Rgb? averageColor(RasterImage image, BoxRect box, {int maxSamples = 64}) {
  final bounds = BoxRect(0, 0, image.width.toDouble(), image.height.toDouble());
  final inner = box.inset(1).intersect(bounds);
  if (inner.width < 1 || inner.height < 1) return null;
  final left = inner.x.floor();
  final top = inner.y.floor();
  final right = inner.right.ceil().clamp(left + 1, image.width);
  final bottom = inner.bottom.ceil().clamp(top + 1, image.height);
  final stride = math.max(
    1,
    math.sqrt((right - left) * (bottom - top) / maxSamples).floor(),
  );
  var samples = 0;
  var r = 0, g = 0, b = 0;
  for (var y = top; y < bottom; y += stride) {
    for (var x = left; x < right; x += stride) {
      final i = (y * image.width + x) * 4;
      r += image.rgba[i];
      g += image.rgba[i + 1];
      b += image.rgba[i + 2];
      samples++;
    }
  }
  if (samples == 0) return null;
  return Rgb(
    (r / samples).round(),
    (g / samples).round(),
    (b / samples).round(),
  );
}

String pixelCsvHeader() =>
    'x,y,chrome_r,chrome_g,chrome_b,nativa_r,nativa_g,nativa_b,delta_e';

/// Writes one row per mismatched pixel (ΔE > 2). Used by `--pixel-csv`.
String pixelCsv(
  RasterImage chrome,
  RasterImage nativa, {
  bool includeMatching = false,
}) {
  final buffer = StringBuffer()..writeln(pixelCsvHeader());
  final width = math.min(chrome.width, nativa.width);
  final height = math.min(chrome.height, nativa.height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final r1 = chrome.rgba[i],
          g1 = chrome.rgba[i + 1],
          b1 = chrome.rgba[i + 2];
      final r2 = nativa.rgba[i],
          g2 = nativa.rgba[i + 1],
          b2 = nativa.rgba[i + 2];
      final de = deltaE(r1, g1, b1, r2, g2, b2);
      if (!includeMatching && de <= 2) continue;
      buffer.writeln('$x,$y,$r1,$g1,$b1,$r2,$g2,$b2,${de.toStringAsFixed(2)}');
    }
  }
  return buffer.toString();
}

/// Most frequent quantized colour, used as the page background for the "ink"
/// metric. Sampling every second pixel keeps this cheap; the background of a
/// page is by definition the dominant flat colour.
Rgb _pageBackground(RasterImage image, int width, int height) {
  if (width <= 0 || height <= 0) return const Rgb(255, 255, 255);
  final counts = <int, int>{};
  final sums = <int, List<int>>{};
  for (var y = 0; y < height; y += 2) {
    for (var x = 0; x < width; x += 2) {
      final i = (y * width + x) * 4;
      final r = image.rgba[i], g = image.rgba[i + 1], b = image.rgba[i + 2];
      final key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
      counts[key] = (counts[key] ?? 0) + 1;
      final acc = sums.putIfAbsent(key, () => [0, 0, 0]);
      acc[0] += r;
      acc[1] += g;
      acc[2] += b;
    }
  }
  if (counts.isEmpty) return const Rgb(255, 255, 255);
  final best = counts.keys.reduce((a, b) => counts[a]! >= counts[b]! ? a : b);
  final count = counts[best]!;
  final sum = sums[best]!;
  return Rgb(sum[0] ~/ count, sum[1] ~/ count, sum[2] ~/ count);
}

double _round(double value, int digits) {
  final factor = math.pow(10, digits);
  return (value * factor).round() / factor;
}
