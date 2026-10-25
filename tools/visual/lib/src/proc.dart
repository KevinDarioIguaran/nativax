import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class ProcResult {
  const ProcResult(this.exitCode, this.stdout, this.stderr, this.timedOut);
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  bool get ok => exitCode == 0 && !timedOut;
}

/// Runs a process, capturing decoded stdout/stderr, and kills it on timeout.
Future<ProcResult> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  Duration timeout = const Duration(minutes: 5),
}) async {
  // `setsid` puts the child in its own process group so a timeout also kills
  // grandchildren (Flutter test leaves `flutter_tester` and the frontend
  // compiler behind, which otherwise pile up and deadlock later pages).
  final useGroup = Platform.isLinux;
  final Process process;
  try {
    process = await Process.start(
      useGroup ? 'setsid' : executable,
      useGroup ? [executable, ...arguments] : arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: true,
      runInShell: false,
    );
  } on ProcessException catch (error) {
    return ProcResult(-1, '', '${error.message}: $executable', false);
  }
  final stdout = BytesBuilder(copy: false);
  final stderr = BytesBuilder(copy: false);
  final outDone = process.stdout.listen(stdout.add).asFuture<void>();
  final errDone = process.stderr.listen(stderr.add).asFuture<void>();
  var timedOut = false;
  final exit = await process.exitCode.timeout(
    timeout,
    onTimeout: () async {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      if (useGroup) {
        // Kill the whole group: setsid made the child its leader.
        await Process.run('kill', ['-KILL', '-${process.pid}']);
      }
      return -2;
    },
  );
  await Future.wait([outDone, errDone]);
  return ProcResult(
    exit,
    utf8.decode(stdout.takeBytes(), allowMalformed: true),
    utf8.decode(stderr.takeBytes(), allowMalformed: true),
    timedOut,
  );
}

/// Minimal HTML entity decoder for the text Chromium writes inside the hidden
/// probe element.
String htmlUnescape(String input) {
  if (!input.contains('&')) return input;
  final buffer = StringBuffer();
  var index = 0;
  final pattern = RegExp(r'&(#x?[0-9a-fA-F]+|amp|lt|gt|quot|apos|#39);');
  for (final match in pattern.allMatches(input)) {
    buffer.write(input.substring(index, match.start));
    final entity = match.group(1)!;
    switch (entity) {
      case 'amp':
        buffer.write('&');
      case 'lt':
        buffer.write('<');
      case 'gt':
        buffer.write('>');
      case 'quot':
        buffer.write('"');
      case 'apos':
        buffer.write("'");
      default:
        if (entity.startsWith('#x') || entity.startsWith('#X')) {
          buffer.writeCharCode(int.parse(entity.substring(2), radix: 16));
        } else if (entity.startsWith('#')) {
          buffer.writeCharCode(int.parse(entity.substring(1)));
        } else {
          buffer.write(match.group(0));
        }
    }
    index = match.end;
  }
  buffer.write(input.substring(index));
  return buffer.toString();
}
