import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'model.dart';
import 'proc_sampler.dart';

class SampledProcessResult {
  const SampledProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
    required this.samples,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final List<ProcSample> samples;
}

/// Runs a process in its own process group, sampling its process tree while it
/// runs. The callback receives the pid as soon as the process starts.
Future<SampledProcessResult> runWithSampling(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required Map<String, String> environment,
  required ProcTreeSampler Function(int pid) samplerFactory,
  Duration timeout = const Duration(minutes: 5),
}) async {
  final useGroup = Platform.isLinux;
  final process = await Process.start(
    useGroup ? 'setsid' : executable,
    useGroup ? [executable, ...arguments] : arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: true,
  );
  final sampler = samplerFactory(process.pid);
  await sampler.start();
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
        await Process.run('kill', ['-KILL', '-${process.pid}']);
      }
      return -2;
    },
  );
  await Future.wait([outDone, errDone]);
  await sampler.stop();
  return SampledProcessResult(
    exitCode: exit,
    stdout: utf8.decode(stdout.takeBytes(), allowMalformed: true),
    stderr: utf8.decode(stderr.takeBytes(), allowMalformed: true),
    timedOut: timedOut,
    samples: sampler.samples,
  );
}
