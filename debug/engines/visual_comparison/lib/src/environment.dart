import 'dart:io';

/// ISO-8601 local time with an explicit UTC offset, for example
/// `2026-10-26T14:03:07.120-05:00`. `DateTime.toIso8601String()` omits the
/// offset for local times, which makes captures from different machines
/// ambiguous.
String isoWithOffset(DateTime time) {
  final local = time.toLocal();
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  String two(int v) => v.toString().padLeft(2, '0');
  final base = local.toIso8601String();
  // Drop any microsecond digits beyond milliseconds for a stable width.
  final dot = base.indexOf('.');
  final trimmed = dot < 0
      ? '$base.000'
      : base.substring(0, (dot + 4).clamp(0, base.length));
  return '$trimmed$sign${two(minutes ~/ 60)}:${two(minutes % 60)}';
}

/// Start/end of one engine capture.
class CaptureWindow {
  const CaptureWindow(this.startedAt, this.finishedAt);
  final DateTime startedAt;
  final DateTime finishedAt;

  Map<String, Object> toJson() => {
    'startedAt': isoWithOffset(startedAt),
    'finishedAt': isoWithOffset(finishedAt),
    'durationMs': finishedAt.difference(startedAt).inMilliseconds,
  };
}

class GitRevision {
  const GitRevision(this.revision, this.dirty);
  final String? revision;

  /// Tracked files differ from [revision]; null when git was unavailable.
  final bool? dirty;

  static const unknown = GitRevision(null, null);

  Map<String, Object?> toJson() => {'revision': revision, 'dirty': dirty};
}

/// Reads `HEAD` and whether tracked files are modified. Never throws.
Future<GitRevision> readGitRevision(String repoRoot) async {
  try {
    final head = await Process.run('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: repoRoot);
    if (head.exitCode != 0) return GitRevision.unknown;
    final status = await Process.run('git', [
      'status',
      '--porcelain',
      '--untracked-files=no',
    ], workingDirectory: repoRoot);
    return GitRevision(
      '${head.stdout}'.trim(),
      status.exitCode == 0 ? '${status.stdout}'.trim().isNotEmpty : null,
    );
  } catch (_) {
    return GitRevision.unknown;
  }
}

/// How fonts are resolved in both engines; recorded verbatim because text
/// metrics depend on it.
const String fontsNote =
    'System fonts only; network fonts are blocked. Chromium resolves generic '
    'families through fontconfig; the NativaX harness maps sans-serif to Noto '
    'Sans to match fontconfig on the reference machine. Different systems can '
    'alias differently and shift text metrics.';

/// Builds `environment.json` for one page.
Map<String, Object?> pageEnvironment({
  required String page,
  required String mode,
  required int viewportWidth,
  required int viewportHeight,
  required double? referenceDpr,
  required double? actualDpr,
  required String scheme,
  required Map<String, Object?> reference,
  required Map<String, Object?> actual,
  required GitRevision git,
  DateTime? generatedAt,
}) => {
  'schema': 'nativa_visual.environment/1',
  'page': page,
  'mode': mode,
  'generatedAt': isoWithOffset(generatedAt ?? DateTime.now()),
  'viewport': {'width': viewportWidth, 'height': viewportHeight},
  'devicePixelRatio': {'reference': referenceDpr, 'actual': actualDpr},
  'scheme': scheme,
  'reference': reference,
  'actual': actual,
  'fonts': fontsNote,
  'animations': 'animations and transitions frozen by an injected stylesheet',
  'network': 'blocked in both engines (http/https never fetched)',
  'git': git.toJson(),
  'host': {
    'os': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'dart': Platform.version.split(' ').first,
  },
};
