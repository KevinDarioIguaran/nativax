# NativaX audit — benchmark

Run `benchmark-20261026T124118-s3`, 120 scenarios. SUT = independent Chromium run + injected faults.

| Fault | Injected | Detected | Localized / localizable |
|---|---:|---:|---:|
| F1_button_width — first button is 6 px wider | 13 | 13 | 13/13 |
| F2_text_color — first text has a wrong computed color | 24 | 24 | 24/24 |
| F3_click_dropped — click events are not recorded after actions | 4 | 4 | 0/0 |
| F4_heading_missing — first heading is absent from the DOM | 9 | 9 | 9/9 |
| F5_input_value — input value is not updated after typing | 0 | 0 | 0/0 |
| F6_grid_crash — any grid container throws during layout | 7 | 7 | 0/0 |
| F7_checkbox_toggle — checkbox does not toggle on click | 0 | 0 | 0/0 |
| F8_padding_left — first row loses 4 px of left padding | 10 | 10 | 10/10 |

- Detection rate: **1.0**
- Localization rate (of detected): **1.0**
- Clean scenarios with findings (false-positive scenario rate): **0/53** (0.0)
- Unexpected primary findings: **0**
- Issues reported: 7 · minimized: 3
