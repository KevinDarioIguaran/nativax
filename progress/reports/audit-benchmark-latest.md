# NativaX audit — benchmark

Run `benchmark-20261025T203331-s7`, 10 scenarios. SUT = independent Chromium run + injected faults.

| Fault | Injected | Detected | Localized / localizable |
|---|---:|---:|---:|
| F1_button_width — first button is 6 px wider | 2 | 2 | 2/2 |
| F2_text_color — first text has a wrong computed color | 0 | 0 | 0/0 |
| F3_click_dropped — click events are not recorded after actions | 1 | 1 | 0/0 |
| F4_heading_missing — first heading is absent from the DOM | 1 | 1 | 1/1 |
| F5_input_value — input value is not updated after typing | 0 | 0 | 0/0 |
| F6_grid_crash — any grid container throws during layout | 0 | 0 | 0/0 |
| F7_checkbox_toggle — checkbox does not toggle on click | 0 | 0 | 0/0 |
| F8_padding_left — first row loses 4 px of left padding | 0 | 0 | 0/0 |

- Detection rate: **1.0**
- Localization rate (of detected): **1.0**
- Clean scenarios with findings (false-positive scenario rate): **0/6** (0.0)
- Unexpected primary findings: **0**
- Issues reported: 3 · minimized: 0
