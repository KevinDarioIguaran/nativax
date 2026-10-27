# NativaX audit — self-check

Run `self-check-20261026T121437-s3`, 60 scenarios. SUT = independent Chromium run.

| Fault | Injected | Detected | Localized / localizable |
|---|---:|---:|---:|
| F1_button_width — first button is 6 px wider | 10 | 0 | 0/0 |
| F2_text_color — first text has a wrong computed color | 16 | 0 | 0/0 |
| F3_click_dropped — click events are not recorded after actions | 1 | 0 | 0/0 |
| F4_heading_missing — first heading is absent from the DOM | 3 | 0 | 0/0 |
| F5_input_value — input value is not updated after typing | 0 | 0 | 0/0 |
| F6_grid_crash — any grid container throws during layout | 4 | 0 | 0/0 |
| F7_checkbox_toggle — checkbox does not toggle on click | 0 | 0 | 0/0 |
| F8_padding_left — first row loses 4 px of left padding | 0 | 0 | 0/0 |

- Detection rate: **0.0**
- Localization rate (of detected): **None**
- Clean scenarios with findings (false-positive scenario rate): **0/26** (0.0)
- Unexpected primary findings: **0**
- Issues reported: 0 · minimized: 0
