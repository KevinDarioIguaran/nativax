/// Public surface of the NativaX visual judge.
library;

export 'src/chrome.dart'
    show ChromeOutcome, VisualException, calibrateChromeFrame, renderWithChrome;
export 'src/color.dart'
    show
        Lab,
        Rgb,
        canonicalCssColor,
        deltaE,
        deltaE76,
        deltaEScore,
        parseCssColor,
        rgbToLab;
export 'src/environment.dart'
    show CaptureWindow, GitRevision, isoWithOffset, readGitRevision;
export 'src/fixtures.dart'
    show
        FixtureSuite,
        discoverPages,
        discoverSuitePages,
        ensureSuite,
        knownSuites,
        pageFromPath,
        suiteById,
        suiteRoot;
export 'src/geometry.dart' show GeometryComparison, compareGeometry;
export 'src/model.dart'
    show BoxRect, ElementSnapshot, PageSource, ProbeSnapshot;
export 'src/nativa.dart' show NativaOutcome, renderWithNativa;
export 'src/pixels.dart'
    show
        ColorComparison,
        PaletteColor,
        PixelComparison,
        RegionSample,
        compareColors,
        comparePixels,
        dominantColors,
        pixelCsv,
        sampleRegion;
export 'src/png.dart' show RasterImage, decodePng, encodePng;
export 'src/regions.dart'
    show
        DeltaMap,
        DiffRegion,
        RegionElement,
        RegionReport,
        deltaMap,
        defaultMaskThreshold,
        defaultMinRegionArea,
        findRegions,
        overlayImage;
export 'src/report.dart' show PageReport, RunReport;
export 'src/runner.dart'
    show
        JudgeOptions,
        PageJudgeResult,
        judgePage,
        pageArtifactsDirectory,
        reusePage,
        selfCheck;
export 'src/score.dart'
    show EnvCheck, Evaluation, Verdict, VerdictLabel, evaluate;
export 'src/styles.dart' show StyleComparison, compareStyles, normalizeStyles;
