import 'dart:math' as math;

/// One-sided Mann-Kendall trend test result (alternative: increasing trend).
class MannKendall {
  const MannKendall({
    required this.n,
    required this.s,
    required this.pValue,
    required this.method,
  });

  /// Number of points in the series.
  final int n;

  /// Kendall S statistic: sum of sign(x_j - x_i) over all i < j.
  final int s;

  /// P(S' >= S) under the null hypothesis of no trend.
  final double pValue;

  /// `exact-permutation` (n <= [mannKendallExactLimit], ties handled by
  /// enumerating every ordering) or `normal-tie-corrected` (continuity
  /// correction and tie-corrected variance).
  final String method;

  Map<String, Object?> toJson() => {
    'test': 'mann-kendall',
    'alternative': 'increasing',
    'n': n,
    's': s,
    'pValue': pValue,
    'method': method,
  };
}

/// Largest series length for which the exact null distribution is computed by
/// enumerating every permutation (9! = 362 880 orderings).
const mannKendallExactLimit = 9;

int kendallS(List<double> x) {
  var s = 0;
  for (var i = 0; i < x.length; i++) {
    for (var j = i + 1; j < x.length; j++) {
      s += (x[j] - x[i]).sign.toInt();
    }
  }
  return s;
}

MannKendall mannKendall(List<double> x) {
  final n = x.length;
  final s = kendallS(x);
  if (n < 2) {
    return MannKendall(n: n, s: s, pValue: 1, method: 'exact-permutation');
  }
  if (n <= mannKendallExactLimit) {
    // Exact permutation null: every ordering of the observed values is
    // equally likely when there is no trend. Ties are kept as ties.
    var atLeast = 0;
    var total = 0;
    final values = List<double>.of(x);
    void permute(int k) {
      if (k == values.length) {
        total++;
        if (kendallS(values) >= s) atLeast++;
        return;
      }
      for (var i = k; i < values.length; i++) {
        final t = values[k];
        values[k] = values[i];
        values[i] = t;
        permute(k + 1);
        values[i] = values[k];
        values[k] = t;
      }
    }

    permute(0);
    return MannKendall(
      n: n,
      s: s,
      pValue: atLeast / total,
      method: 'exact-permutation',
    );
  }
  final ties = <double, int>{};
  for (final v in x) {
    ties[v] = (ties[v] ?? 0) + 1;
  }
  var tieTerm = 0.0;
  for (final t in ties.values) {
    tieTerm += t * (t - 1) * (2 * t + 5);
  }
  final variance = (n * (n - 1) * (2 * n + 5) - tieTerm) / 18;
  if (variance <= 0) {
    return MannKendall(n: n, s: s, pValue: 1, method: 'normal-tie-corrected');
  }
  final z = s > 0
      ? (s - 1) / math.sqrt(variance)
      : s < 0
      ? (s + 1) / math.sqrt(variance)
      : 0.0;
  return MannKendall(
    n: n,
    s: s,
    pValue: 1 - normalCdf(z),
    method: 'normal-tie-corrected',
  );
}

/// Theil-Sen slope: median of the pairwise slopes (x_j - x_i) / (j - i).
double senSlope(List<double> x) {
  if (x.length < 2) return 0;
  final slopes = <double>[
    for (var i = 0; i < x.length; i++)
      for (var j = i + 1; j < x.length; j++) (x[j] - x[i]) / (j - i),
  ];
  return median(slopes);
}

double median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.of(values)..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Standard normal CDF (Abramowitz-Stegun 7.1.26 erf approximation,
/// absolute error below 1.5e-7).
double normalCdf(double z) {
  final x = z.abs() / math.sqrt2;
  final t = 1 / (1 + 0.3275911 * x);
  final y =
      1 -
      (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
                      0.284496736) *
                  t +
              0.254829592) *
          t *
          math.exp(-x * x);
  return z >= 0 ? (1 + y) / 2 : (1 - y) / 2;
}
