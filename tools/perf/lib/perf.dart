/// Public surface of the NativaX performance suite.
library;

export 'src/app_idle.dart' show AppIdleResult, measureAppIdle;
export 'src/cdp.dart' show CdpChrome, CdpException;
export 'src/chrome_engine.dart' show runChromeScenario;
export 'src/evaluate.dart' show evaluateScenario;
export 'src/externals.dart';
export 'src/model.dart';
export 'src/nativa_engine.dart' show runNativaScenario, stageScenarioPage;
export 'src/proc_sampler.dart' show ProcTreeSampler, readGpuBusyPercent;
export 'src/report.dart' show writePerfReports;
export 'src/runner.dart' show PerfOptions, runPerf;
export 'src/scenarios.dart';
