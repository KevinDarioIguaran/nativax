# Bug detection (JSON interface audit) metrics and measured accuracy

Scope: `debug/engines/bug_detection` (`nxaudit`). It generates JSON
interfaces, runs them in NativaX and Chromium, and reports differences as
issues. The question measured here is whether it finds defects that exist,
points at the right element, and stays quiet when there is nothing to find.

## 1. Method

**Deliberate faults (`audit.py benchmark`).**

- The system under test is a **second, independent Chromium run**, with known
  faults injected into its observations (`nxaudit/faults.py`).
- Truth comes from the injection, never from the engine's own output.
- About 70 % of applicable scenarios get exactly one fault. The choice is
  deterministic, keyed by the scenario's content.
- The other scenarios are clean, so any primary finding on them is a false
  positive. That includes any nondeterminism between two Chromium runs.

| Fault | Injected defect | Expected finding |
|---|---|---|
| `F1_button_width` | first button is 6 px wider | geometry/size |
| `F2_text_color` | first text has a wrong computed color | style/color |
| `F3_click_dropped` | click events are not recorded after actions | events |
| `F4_heading_missing` | first heading is absent from the DOM | missing |
| `F5_input_value` | input value is not updated after typing | state/value |
| `F6_grid_crash` | any grid container throws during layout | crash |
| `F7_checkbox_toggle` | checkbox does not toggle on click | state/checked |
| `F8_padding_left` | first row loses 4 px of left padding | style/padding |

**Metrics:**

- **Detection:** a finding of the expected kind (and property) exists.
- **Localization:** that finding names the faulted element. Crashes and
  event faults have no element, so they are excluded.
- **False-positive scenario rate:** clean scenarios with any primary finding.
- **Self-check (`audit.py self-check`):** Chromium against Chromium with no
  faults. It must report 0 issues.

## 2. Results

Linux 6.12, Google Chrome 152, 2026-10-26. Each run uses `--budget 120`
scenarios; seeds 7, 1, 2 and 3.

| Seed | Injected | Detected | Localized / localizable | Clean scenarios | Clean with findings | Unexpected findings |
|---:|---:|---:|---:|---:|---:|---:|
| 7 | 75 | 75 | 69/69 | 45 | 0 | 0 |
| 1 | 71 | 71 | 64/64 | 49 | 0 | 0 |
| 2 | 74 | 74 | 62/62 | 46 | 0 | 0 |
| 3 | 67 | 67 | 56/56 | 53 | 0 | 0 |
| **Total** | **287** | **287 (100 %)** | **251/251 (100 %)** | **193** | **0 (0 %)** | **0** |

Self-check, 60 scenarios per seed (7, 1, 2, 3): **0 issues and 0 findings**
on all 4 runs (240 scenarios).

## 3. Bug found by this audit (fixed)

The first 4-seed run gave 284/285 detected and 1 unexpected finding (seed 1).

- **Symptom:** a scenario scored as `F6_grid_crash` showed a padding
  difference.
- **Cause:** the explorer caches observations by **content hash**, but the
  fault was chosen by **scenario id**. Two scenarios with equal content and
  different ids (a mutation that reproduced an earlier scenario) shared one
  observation. That observation was injected with the first scenario's
  fault and scored against the second scenario's fault.
- **Scope:** this affected only the benchmark's bookkeeping. Real runs have
  no injection, so the cache is correct there.
- **Fix:** `faults.choose()` now hashes the content. The regression test is
  `test_fault_choice_follows_content_not_id`. After the fix, all 4 seeds are
  100 % with 0 unexpected findings.

## 4. Limitations

- **`F5_input_value` was never injected and `F7_checkbox_toggle` only once.**
  At this budget the generator rarely produces typing actions with text or
  clicks on checkboxes, so their detection rate is not measured. A larger
  `--budget` or a targeted interaction family is needed.
- **Synthetic faults:** the faults are changes to observations, not real
  NativaX bugs. They test the oracles, the clustering and the localization,
  not whether the generator reaches the inputs that trigger real bugs. The
  real-run issues, such as the minimized textarea and grid crashes, are
  separate evidence.
- **Single browser:** one machine and one Chrome build.

## Reproduce

```bash
for s in 7 1 2 3; do
  python3 debug/engines/bug_detection/audit.py benchmark --budget 120 --seed $s
  python3 debug/engines/bug_detection/audit.py self-check --budget 60 --seed $s
done
# per run: debug/artifacts/audit/benchmark/runs/<run>/benchmark.{json,md}
```
