import 'dart:convert';
import 'dart:io';

import 'color.dart';
import 'model.dart';
import 'pixels.dart';
import 'png.dart';
import 'score.dart';
import 'styles.dart';

class PageReport {
  PageReport({
    required this.page,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.scheme,
    required this.artifactsDir,
    required this.checks,
    this.chromeProbe,
    this.nativaProbe,
    this.evaluation,
    this.chromeDuration,
    this.nativaDuration,
    this.failure,
    this.notes = const [],
  });

  final PageSource page;
  final int viewportWidth;
  final int viewportHeight;
  final String scheme;
  final String artifactsDir;
  final List<EnvCheck> checks;
  final ProbeSnapshot? chromeProbe;
  final ProbeSnapshot? nativaProbe;
  final Evaluation? evaluation;
  final Duration? chromeDuration;
  final Duration? nativaDuration;

  /// Fatal harness failure (no reference or no NativaX render).
  final String? failure;
  final List<String> notes;

  Verdict get verdict => evaluation?.verdict ?? Verdict.invalid;
  double? get overall => evaluation?.overall;

  Map<String, Object?> toJson() {
    final eval = evaluation;
    return {
      'page': page.id,
      'suite': page.suite,
      'entry': page.entry,
      'scheme': scheme,
      'viewport': {'width': viewportWidth, 'height': viewportHeight},
      'verdict': verdict.label,
      if (failure != null) 'failure': failure,
      if (eval != null) ...{
        'scores': {
          'overall': _score(eval.overall),
          'position': _score(eval.position),
          'layout': _score(eval.layout),
          'color': _score(eval.color),
          'design': _score(eval.design),
        },
        'reason': eval.reason,
        'geometry': {
          ...geometryMap(eval),
          'rootCauses': [for (final d in eval.geometry.rootCauses) d.toJson()],
        },
        'pixels': {
          ...eval.pixels.totals.toJson(),
          'worstTiles': [for (final t in eval.pixels.worstTiles) t.toJson()],
        },
        'colors': {
          'comparableElements': eval.colorComparable,
          'withinDeltaE2': eval.colorWithin2,
          'withinDeltaE5': eval.colorWithin5,
          'failures': [
            for (final e in eval.colorFailures.take(30))
              {
                'path': e.delta.path,
                'tag': e.delta.tag,
                'meanDeltaE': _round(e.sample!.meanDeltaE),
                'paletteDeltaE': _round(e.sample!.paletteDeltaE),
                'colorScore': _round(e.sample!.score * 100),
                'chromeSampled': e.sample!.chromeMean.toString(),
                'nativaSampled': e.sample!.nativaMean.toString(),
                'chromePalette': [
                  for (final color in e.sample!.chromePalette)
                    {
                      'color': color.color.toString(),
                      'share': _round(color.share),
                    },
                ],
                'nativaPalette': [
                  for (final color in e.sample!.nativaPalette)
                    {
                      'color': color.color.toString(),
                      'share': _round(color.share),
                    },
                ],
                'chromeComputedBackground': chromeProbe
                    ?.byPath[e.delta.path]
                    ?.styles['background-color'],
                'nativaComputedBackground': nativaProbe
                    ?.byPath[e.delta.path]
                    ?.styles['background-color'],
                'chromeComputedColor':
                    chromeProbe?.byPath[e.delta.path]?.styles['color'],
                'nativaComputedColor':
                    nativaProbe?.byPath[e.delta.path]?.styles['color'],
              },
          ],
        },
        'designFailures': [
          for (final s in eval.designFailures.take(40))
            {
              'path': s.element.path,
              'tag': s.element.tag,
              'score': _round(s.score),
              'mismatches': [for (final m in s.mismatches) m.toJson()],
            },
        ],
      },
      'elements': [
        for (final e in eval?.elements ?? const <ElementReport>[])
          {
            ...e.delta.toJson(),
            if (e.style != null) 'designScore': _round(e.style!.score * 100),
            if (e.sample != null) ...{
              'colorMeanDeltaE': _round(e.sample!.meanDeltaE),
              'colorPaletteDeltaE': _round(e.sample!.paletteDeltaE),
              'colorScore': _round(e.sample!.score * 100),
              'chromeSampled': e.sample!.chromeMean.toString(),
              'nativaSampled': e.sample!.nativaMean.toString(),
            },
            if (e.style != null && e.style!.mismatches.isNotEmpty)
              'styleMismatches': [
                for (final m in e.style!.mismatches) m.toJson(),
              ],
          },
      ],
      'environment': [for (final c in checks) c.toJson()],
      'timing': {
        'chromeMs': chromeDuration?.inMilliseconds,
        'nativaMs': nativaDuration?.inMilliseconds,
      },
      'notes': notes,
    };
  }

  /// Per-element results table (JSON counterpart of `elements.csv`).
  Map<String, Object?> elementsJson() {
    final eval = evaluation;
    return {
      'page': page.id,
      'viewport': {'width': viewportWidth, 'height': viewportHeight},
      'columns': [
        'path',
        'tag',
        'chrome_x',
        'chrome_y',
        'chrome_w',
        'chrome_h',
        'nativa_x',
        'nativa_y',
        'nativa_w',
        'nativa_h',
        'dx',
        'dy',
        'dw',
        'dh',
        'position_delta',
        'size_delta',
        'iou',
        'position_match',
        'size_match',
        'root_cause',
        'missing',
        'extra',
        'design_score',
        'color_mean_delta_e',
        'color_palette_delta_e',
        'color_score',
        'chrome_background',
        'nativa_background',
        'chrome_color',
        'nativa_color',
        'sampled_chrome',
        'sampled_nativa',
        'style_mismatches',
      ],
      'rows': [
        for (final element in eval?.elements ?? const <ElementReport>[])
          () {
            final d = element.delta;
            final comparable = d.chromeRect != null && d.nativaRect != null;
            final chromeStyle = chromeProbe?.byPath[d.path]?.styles;
            final nativaStyle = nativaProbe?.byPath[d.path]?.styles;
            return {
              'path': d.path,
              'tag': d.tag,
              'chrome_x': d.chromeRect?.x,
              'chrome_y': d.chromeRect?.y,
              'chrome_w': d.chromeRect?.width,
              'chrome_h': d.chromeRect?.height,
              'nativa_x': d.nativaRect?.x,
              'nativa_y': d.nativaRect?.y,
              'nativa_w': d.nativaRect?.width,
              'nativa_h': d.nativaRect?.height,
              'dx': comparable
                  ? _round(d.nativaRect!.x - d.chromeRect!.x)
                  : null,
              'dy': comparable
                  ? _round(d.nativaRect!.y - d.chromeRect!.y)
                  : null,
              'dw': comparable
                  ? _round(d.nativaRect!.width - d.chromeRect!.width)
                  : null,
              'dh': comparable
                  ? _round(d.nativaRect!.height - d.chromeRect!.height)
                  : null,
              'position_delta': d.positionDelta.isFinite
                  ? _round(d.positionDelta)
                  : null,
              'size_delta': d.sizeDelta.isFinite ? _round(d.sizeDelta) : null,
              'iou': _round(d.iou),
              'position_match': d.positionMatch,
              'size_match': d.sizeMatch,
              'root_cause': d.rootCause,
              'missing': d.missing,
              'extra': d.extra,
              'design_score': element.style == null
                  ? null
                  : _round(element.style!.score * 100),
              'color_mean_delta_e': element.sample == null
                  ? null
                  : _round(element.sample!.meanDeltaE),
              'color_palette_delta_e': element.sample == null
                  ? null
                  : _round(element.sample!.paletteDeltaE),
              'color_score': element.sample == null
                  ? null
                  : _round(element.sample!.score * 100),
              'chrome_background': chromeStyle?['background-color'],
              'nativa_background': nativaStyle?['background-color'],
              'chrome_color': chromeStyle?['color'],
              'nativa_color': nativaStyle?['color'],
              'sampled_chrome': element.sample?.chromeMean.toString(),
              'sampled_nativa': element.sample?.nativaMean.toString(),
              'style_mismatches': [
                for (final m
                    in element.style?.mismatches ?? const <StyleMismatch>[])
                  {
                    'property': m.property,
                    'chrome': m.chrome,
                    'nativa': m.nativa,
                  },
              ],
            };
          }(),
      ],
    };
  }

  void writeArtifacts({
    RasterImage? chromeImage,
    RasterImage? nativaImage,
    bool writePixelCsv = false,
    bool writePixelCsvAll = false,
  }) {
    final dir = Directory(artifactsDir)..createSync(recursive: true);
    File(
      '${dir.path}/report.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(toJson()));
    final eval = evaluation;
    if (eval == null) return;

    File('${dir.path}/diff.png').writeAsBytesSync(encodePng(eval.pixels.diff));
    File('${dir.path}/pixels.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'totals': eval.pixels.totals.toJson(),
        'worstTiles': [for (final t in eval.pixels.worstTiles) t.toJson()],
        'rows': [for (final r in eval.pixels.rows) r.toJson()],
      }),
    );
    File('${dir.path}/elements.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(elementsJson()),
    );
    _writeElementsCsv(File('${dir.path}/elements.csv'));
    _writePositionsCsv(File('${dir.path}/positions.csv'));
    _writeColorsCsv(File('${dir.path}/colors.csv'));
    if (writePixelCsv && chromeImage != null && nativaImage != null) {
      File('${dir.path}/pixels.csv').writeAsStringSync(
        pixelCsv(chromeImage, nativaImage, includeMatching: writePixelCsvAll),
      );
    }
  }

  void _writeElementsCsv(File file) {
    final eval = evaluation;
    if (eval == null) return;
    final out = StringBuffer()
      ..writeln(
        'path,tag,chrome_x,chrome_y,chrome_w,chrome_h,'
        'nativa_x,nativa_y,nativa_w,nativa_h,position_delta,size_delta,iou,'
        'position_match,size_match,missing,extra,design_score,'
        'color_mean_delta_e,color_palette_delta_e,color_score,'
        'chrome_background,nativa_background,chrome_color,nativa_color,'
        'sampled_chrome,sampled_nativa,mismatched_properties',
      );
    for (final element in eval.elements) {
      final d = element.delta;
      final chromeStyle = chromeProbe?.byPath[d.path]?.styles;
      final nativaStyle = nativaProbe?.byPath[d.path]?.styles;
      out.writeln(
        [
          _csv(d.path),
          d.tag,
          _num(d.chromeRect?.x),
          _num(d.chromeRect?.y),
          _num(d.chromeRect?.width),
          _num(d.chromeRect?.height),
          _num(d.nativaRect?.x),
          _num(d.nativaRect?.y),
          _num(d.nativaRect?.width),
          _num(d.nativaRect?.height),
          _num(d.positionDelta),
          _num(d.sizeDelta),
          _num(d.iou),
          d.positionMatch,
          d.sizeMatch,
          d.missing,
          d.extra,
          element.style == null ? '' : _num(element.style!.score * 100),
          element.sample == null ? '' : _num(element.sample!.meanDeltaE),
          element.sample == null ? '' : _num(element.sample!.paletteDeltaE),
          element.sample == null ? '' : _num(element.sample!.score * 100),
          _csv(chromeStyle?['background-color'] ?? ''),
          _csv(nativaStyle?['background-color'] ?? ''),
          _csv(chromeStyle?['color'] ?? ''),
          _csv(nativaStyle?['color'] ?? ''),
          element.sample?.chromeMean.toString() ?? '',
          element.sample?.nativaMean.toString() ?? '',
          _csv(
            element.style?.mismatches.map((m) => m.property).join(' ') ?? '',
          ),
        ].join(','),
      );
    }
    file.writeAsStringSync(out.toString());
  }

  void _writePositionsCsv(File file) {
    final eval = evaluation;
    if (eval == null) return;
    final out = StringBuffer()
      ..writeln(
        'path,tag,chrome_x,chrome_y,chrome_w,chrome_h,'
        'nativa_x,nativa_y,nativa_w,nativa_h,dx,dy,dw,dh,position_delta,'
        'size_delta,iou,position_match,size_match,root_cause,missing,extra',
      );
    for (final d in eval.geometry.deltas) {
      final comparable = d.chromeRect != null && d.nativaRect != null;
      out.writeln(
        [
          _csv(d.path),
          d.tag,
          _num(d.chromeRect?.x),
          _num(d.chromeRect?.y),
          _num(d.chromeRect?.width),
          _num(d.chromeRect?.height),
          _num(d.nativaRect?.x),
          _num(d.nativaRect?.y),
          _num(d.nativaRect?.width),
          _num(d.nativaRect?.height),
          comparable ? _num(d.nativaRect!.x - d.chromeRect!.x) : '',
          comparable ? _num(d.nativaRect!.y - d.chromeRect!.y) : '',
          comparable ? _num(d.nativaRect!.width - d.chromeRect!.width) : '',
          comparable ? _num(d.nativaRect!.height - d.chromeRect!.height) : '',
          _num(d.positionDelta),
          _num(d.sizeDelta),
          _num(d.iou),
          d.positionMatch,
          d.sizeMatch,
          d.rootCause,
          d.missing,
          d.extra,
        ].join(','),
      );
    }
    file.writeAsStringSync(out.toString());
  }

  void _writeColorsCsv(File file) {
    final eval = evaluation;
    if (eval == null) return;
    final out = StringBuffer()
      ..writeln(
        'path,tag,chrome_background,nativa_background,background_match,'
        'chrome_color,nativa_color,text_color_match,sampled_chrome,'
        'sampled_nativa,mean_delta_e,palette_delta_e,color_score',
      );
    for (final element in eval.elements) {
      final path = element.delta.path;
      final chromeStyle = chromeProbe?.byPath[path]?.styles;
      final nativaStyle = nativaProbe?.byPath[path]?.styles;
      final cb = chromeStyle?['background-color'] ?? '';
      final nb = nativaStyle?['background-color'] ?? '';
      final cf = chromeStyle?['color'] ?? '';
      final nf = nativaStyle?['color'] ?? '';
      // Compare canonical forms so `rgb(1, 2, 3)` and `rgb(1,2,3)` agree.
      final cbCanonical = canonicalCssColor(cb);
      final nbCanonical = canonicalCssColor(nb, current: cf);
      final cfCanonical = canonicalCssColor(cf);
      final nfCanonical = canonicalCssColor(nf);
      out.writeln(
        [
          _csv(path),
          element.delta.tag,
          _csv(cb),
          _csv(nb),
          cbCanonical == nbCanonical,
          _csv(cf),
          _csv(nf),
          cfCanonical == nfCanonical,
          element.sample?.chromeMean.toString() ?? '',
          element.sample?.nativaMean.toString() ?? '',
          element.sample == null ? '' : _num(element.sample!.meanDeltaE),
          element.sample == null ? '' : _num(element.sample!.paletteDeltaE),
          element.sample == null ? '' : _num(element.sample!.score * 100),
        ].join(','),
      );
    }
    file.writeAsStringSync(out.toString());
  }
}

Map<String, Object> geometryMap(Evaluation eval) {
  final g = eval.geometry;
  return {
    'matchedElements': g.matched,
    'positionMatches': g.positionMatches,
    'positionMatchPct': _round(g.positionMatchPct),
    'sizeMatches': g.sizeMatches,
    'sizeMatchPct': _round(g.sizeMatchPct),
    'missingElements': g.missing,
    'extraElements': g.extra,
    'orderViolations': g.orderViolations,
    'documentHeightDelta': g.documentHeightDelta,
  };
}

class RunReport {
  RunReport({
    required this.startedAt,
    required this.duration,
    required this.chromeVersion,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.scheme,
    required this.frozenAnimations,
    required this.outputDir,
    required this.pages,
    required this.command,
  });

  final DateTime startedAt;
  final Duration duration;
  final String chromeVersion;
  final int viewportWidth;
  final int viewportHeight;
  final String scheme;
  final bool frozenAnimations;
  final String outputDir;
  final List<PageReport> pages;
  final String command;

  int count(Verdict verdict) => pages.where((p) => p.verdict == verdict).length;

  double get meanOverall {
    final scored = pages.where((p) => p.overall != null).toList();
    if (scored.isEmpty) return 0;
    return scored.fold<double>(0, (sum, p) => sum + p.overall!) / scored.length;
  }

  Map<String, Object?> toJson() => {
    'tool': 'nativa_visual',
    'version': '0.1.0',
    'startedAt': startedAt.toIso8601String(),
    'durationSeconds': _round(duration.inMilliseconds / 1000),
    'command': command,
    'chrome': chromeVersion,
    'viewport': {'width': viewportWidth, 'height': viewportHeight},
    'scheme': scheme,
    'frozenAnimations': frozenAnimations,
    'summary': {
      'pages': pages.length,
      'pass': count(Verdict.pass),
      'warn': count(Verdict.warn),
      'fail': count(Verdict.fail),
      'invalid': count(Verdict.invalid),
      'meanOverall': _score(meanOverall),
    },
    'pages': [for (final p in pages) p.toJson()],
  };

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# NativaX visual fidelity')
      ..writeln()
      ..writeln('- Reference: $chromeVersion (headless, no window)')
      ..writeln(
        '- Viewport: ${viewportWidth}x$viewportHeight, scheme: $scheme, '
        'animations frozen: ${frozenAnimations ? 'yes' : 'no'}',
      )
      ..writeln('- Started: ${startedAt.toIso8601String()}')
      ..writeln(
        '- Duration: ${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s',
      )
      ..writeln('- Command: `$command`')
      ..writeln()
      ..writeln('| Verdict | Pages |')
      ..writeln('|---|---:|')
      ..writeln('| PASS | ${count(Verdict.pass)} |')
      ..writeln('| WARN | ${count(Verdict.warn)} |')
      ..writeln('| FAIL | ${count(Verdict.fail)} |')
      ..writeln('| INVALID | ${count(Verdict.invalid)} |')
      ..writeln()
      ..writeln('## Pages')
      ..writeln()
      ..writeln(
        '| Page | Verdict | Overall | Position | Layout | Color | Design | '
        'Elements | Missing | Px mismatch | Ink mismatch | Mean ΔE |',
      )
      ..writeln('|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
    for (final page in pages) {
      final e = page.evaluation;
      buffer.writeln(
        '| `${page.page.id}` | ${page.verdict.label} | '
        '${_pctOrDash(page.overall)} | ${_pctOrDash(e?.position)} | '
        '${_pctOrDash(e?.layout)} | ${_pctOrDash(e?.color)} | '
        '${_pctOrDash(e?.design)} | ${e?.geometry.total ?? 0} | '
        '${e?.geometry.missing ?? 0} | '
        '${e == null ? '—' : '${e.mismatchedPixelPct.toStringAsFixed(2)} %'} | '
        '${e == null ? '—' : '${e.pixels.totals.inkMismatchPct.toStringAsFixed(2)} %'} | '
        '${e == null ? '—' : e.pixels.totals.meanDeltaE.toStringAsFixed(2)} |',
      );
    }
    buffer
      ..writeln()
      ..writeln(
        'Scores are percentages. `—` means not measurable: colour is only '
        'scored on elements whose position and size match, otherwise layout '
        'error would be counted twice.',
      )
      ..writeln()
      ..writeln('## Details');
    for (final page in pages) {
      buffer
        ..writeln()
        ..writeln('### `${page.page.id}` — ${page.verdict.label}')
        ..writeln();
      final eval = page.evaluation;
      if (page.failure != null) {
        buffer
          ..writeln('Harness failure: ${page.failure}')
          ..writeln();
        continue;
      }
      if (eval == null) continue;
      buffer
        ..writeln(
          'Overall **${_pct(eval.overall)}** (${eval.reason}). '
          'Viewport ${page.viewportWidth}x${page.viewportHeight}; '
          'document height ${page.chromeProbe?.documentHeight ?? 0} px in '
          'Chromium vs ${page.nativaProbe?.documentHeight ?? 0} px in NativaX.',
        )
        ..writeln()
        ..writeln('Artifacts: `${page.artifactsDir}`')
        ..writeln()
        ..writeln(
          'Pixel report: **${eval.pixels.totals.pixels}** pixels compared, '
          '**${eval.mismatchedPixels}** above ΔE 2 '
          '(${eval.mismatchedPixelPct.toStringAsFixed(2)} %), mean ΔE '
          '${eval.pixels.totals.meanDeltaE.toStringAsFixed(2)}, max ΔE '
          '${eval.pixels.totals.maxDeltaE.toStringAsFixed(2)}, MAE '
          '${eval.pixels.totals.mae.toStringAsFixed(2)}. '
          'Ink (non-background) mismatch: '
          '**${eval.pixels.totals.inkMismatchPct.toStringAsFixed(2)} %** '
          '(${eval.pixels.totals.inkMismatched}/${eval.pixels.totals.inkPixels} px; '
          'Chromium ink ${eval.pixels.totals.chromeInkPixels} px, '
          'NativaX ink ${eval.pixels.totals.nativaInkPixels} px).',
        )
        ..writeln();

      final env = page.checks;
      if (env.isNotEmpty) {
        buffer
          ..writeln('| Environment | OK | Hard | Detail |')
          ..writeln('|---|:---:|:---:|---|');
        for (final check in env) {
          buffer.writeln(
            '| ${check.name} | ${check.ok ? 'yes' : 'no'} | '
            '${check.hard ? 'yes' : 'no'} | ${check.detail.replaceAll('|', '\\|')} |',
          );
        }
        buffer.writeln();
      }

      if (eval.geometry.rootCauses.isNotEmpty) {
        buffer
          ..writeln('Worst position/layout root causes:')
          ..writeln()
          ..writeln(
            '| Element | Chromium box | NativaX box | Δpos | Δsize | IoU |',
          )
          ..writeln('|---|---|---|---:|---:|---:|');
        for (final d in eval.geometry.rootCauses.take(10)) {
          buffer.writeln(
            '| `${d.path}`${d.missing ? ' **missing**' : ''}'
            '${d.extra ? ' **extra**' : ''} | '
            '${_box(d.chromeRect)} | ${_box(d.nativaRect)} | '
            '${d.positionDelta.isFinite ? d.positionDelta.toStringAsFixed(1) : '—'} | '
            '${d.sizeDelta.isFinite ? d.sizeDelta.toStringAsFixed(1) : '—'} | '
            '${d.iou.toStringAsFixed(2)} |',
          );
        }
        buffer.writeln();
      }

      if (eval.colorFailures.isNotEmpty) {
        buffer
          ..writeln('Worst colour elements (mean and dominant-palette ΔE):')
          ..writeln()
          ..writeln(
            '| Element | Chromium mean | NativaX mean | Mean ΔE | '
            'Palette ΔE | Colour score |',
          )
          ..writeln('|---|---|---|---:|---:|---:|');
        for (final e in eval.colorFailures.take(10)) {
          buffer.writeln(
            '| `${e.delta.path}` | ${e.sample!.chromeMean} | '
            '${e.sample!.nativaMean} | ${e.sample!.meanDeltaE.toStringAsFixed(2)} | '
            '${e.sample!.paletteDeltaE.toStringAsFixed(2)} | '
            '${(e.sample!.score * 100).toStringAsFixed(1)} % |',
          );
        }
        buffer.writeln();
      }

      if (eval.designFailures.isNotEmpty) {
        buffer
          ..writeln('Computed-style differences (top 10):')
          ..writeln()
          ..writeln('| Element | Score | Mismatches (Chromium → NativaX) |')
          ..writeln('|---|---:|---|');
        for (final s in eval.designFailures.take(10)) {
          final details = s.mismatches
              .take(4)
              .map((m) => '${m.property} `${m.chrome}` → `${m.nativa}`')
              .join('; ');
          final more = s.mismatches.length > 4
              ? '; +${s.mismatches.length - 4} more'
              : '';
          buffer.writeln(
            '| `${s.element.path}` | ${(s.score * 100).toStringAsFixed(1)} % '
            '| $details$more |',
          );
        }
        buffer.writeln();
      }

      if (page.notes.isNotEmpty) {
        for (final note in page.notes) {
          buffer.writeln('- $note');
        }
        buffer.writeln();
      }
    }
    return buffer.toString();
  }

  /// Writes only results.json so the dashboard can follow a run page by page.
  void writeLiveResults(String directory) {
    final dir = Directory(directory)..createSync(recursive: true);
    final tmp = File('${dir.path}/.results.json.tmp');
    tmp.writeAsStringSync(jsonEncode(resultsJson()));
    tmp.renameSync('${dir.path}/results.json');
  }

  /// Machine-readable results table: one row per page, stable column order.
  /// This is the JSON counterpart of `summary.csv`.
  Map<String, Object?> resultsJson() => {
    'tool': 'nativa_visual',
    'version': '0.1.0',
    'generatedAt': DateTime.now().toIso8601String(),
    'reference': chromeVersion,
    'viewport': {'width': viewportWidth, 'height': viewportHeight},
    'scheme': scheme,
    'columns': [
      'page',
      'suite',
      'verdict',
      'overall',
      'position',
      'layout',
      'color',
      'design',
      'environment_ok',
      'environment_total',
      'matched',
      'missing',
      'extra',
      'order_violations',
      'pixels',
      'mismatched_pixels',
      'mismatched_pct',
      'ink_mismatch_pct',
      'ink_pixels',
      'mean_delta_e',
      'max_delta_e',
      'mae',
      'chrome_ms',
      'nativa_ms',
      'artifacts',
      'chrome_png',
      'nativax_png',
      'diff_png',
      'elements_json',
      'failure',
    ],
    'rows': [
      for (final page in pages)
        () {
          final e = page.evaluation;
          return {
            'page': page.page.id,
            'suite': page.page.suite,
            'verdict': page.verdict.label,
            'overall': e == null ? null : _score(e.overall),
            'position': e == null ? null : _score(e.position),
            'layout': e == null ? null : _score(e.layout),
            'color': e == null || e.color == null ? null : _score(e.color),
            'design': e == null || e.design == null ? null : _score(e.design),
            'environment_ok': page.checks.where((c) => c.ok).length,
            'environment_total': page.checks.length,
            'matched': e?.geometry.matched,
            'missing': e?.geometry.missing,
            'extra': e?.geometry.extra,
            'order_violations': e?.geometry.orderViolations,
            'pixels': e?.pixels.totals.pixels,
            'mismatched_pixels': e?.pixels.totals.mismatched,
            'mismatched_pct': e == null ? null : _round(e.mismatchedPixelPct),
            'ink_mismatch_pct': e == null
                ? null
                : _round(e.pixels.totals.inkMismatchPct),
            'ink_pixels': e?.pixels.totals.inkPixels,
            'mean_delta_e': e == null
                ? null
                : _round(e.pixels.totals.meanDeltaE),
            'max_delta_e': e == null ? null : _round(e.pixels.totals.maxDeltaE),
            'mae': e == null ? null : _round(e.pixels.totals.mae),
            'chrome_ms': page.chromeDuration?.inMilliseconds,
            'nativa_ms': page.nativaDuration?.inMilliseconds,
            'artifacts': page.artifactsDir,
            'chrome_png': '${page.artifactsDir}/chrome.png',
            'nativax_png': '${page.artifactsDir}/nativax.png',
            'diff_png': '${page.artifactsDir}/diff.png',
            'elements_json': '${page.artifactsDir}/elements.json',
            'failure': page.failure,
          };
        }(),
    ],
  };

  String summaryCsv() {
    final out = StringBuffer()
      ..writeln(
        'page,suite,verdict,overall,position,layout,color,design,'
        'matched,missing,extra,order_violations,pixels,mismatched_pixels,'
        'mismatched_pct,ink_mismatch_pct,ink_pixels,'
        'mean_delta_e,max_delta_e,mae,chrome_ms,nativa_ms',
      );
    for (final page in pages) {
      final e = page.evaluation;
      out.writeln(
        [
          _csv(page.page.id),
          _csv(page.page.suite),
          page.verdict.label,
          e == null ? '' : _pct(e.overall),
          e == null ? '' : _pct(e.position),
          e == null ? '' : _pct(e.layout),
          e == null || e.color == null ? '' : _pct(e.color),
          e == null || e.design == null ? '' : _pct(e.design),
          e?.geometry.matched ?? '',
          e?.geometry.missing ?? '',
          e?.geometry.extra ?? '',
          e?.geometry.orderViolations ?? '',
          e?.pixels.totals.pixels ?? '',
          e?.pixels.totals.mismatched ?? '',
          e == null ? '' : _num(e.mismatchedPixelPct),
          e == null ? '' : _num(e.pixels.totals.inkMismatchPct),
          e?.pixels.totals.inkPixels ?? '',
          e == null ? '' : _num(e.pixels.totals.meanDeltaE),
          e == null ? '' : _num(e.pixels.totals.maxDeltaE),
          e == null ? '' : _num(e.pixels.totals.mae),
          page.chromeDuration?.inMilliseconds ?? '',
          page.nativaDuration?.inMilliseconds ?? '',
        ].join(','),
      );
    }
    return out.toString();
  }

  void write(String directory) {
    final dir = Directory(directory)..createSync(recursive: true);
    File(
      '${dir.path}/report.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(toJson()));
    File('${dir.path}/report.md').writeAsStringSync(toMarkdown());
    File('${dir.path}/summary.csv').writeAsStringSync(summaryCsv());
    final results = File('${dir.path}/.results.json.tmp')
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(resultsJson()),
      );
    results.renameSync('${dir.path}/results.json');
  }
}

String _csv(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

String _num(double? value) {
  if (value == null) return '';
  if (!value.isFinite) return '';
  return _round(value).toString();
}

String _box(BoxRect? box) => box == null ? '—' : box.toString();

double? _score(double? value) => value == null ? null : _round(value * 100);

double _round(double value) {
  if (!value.isFinite) return 0;
  return (value * 1000).round() / 1000;
}

String _pct(double? value) =>
    value == null ? '—' : (value * 100).toStringAsFixed(2);

String _pctOrDash(double? value) =>
    value == null ? '—' : '${(value * 100).toStringAsFixed(2)} %';
