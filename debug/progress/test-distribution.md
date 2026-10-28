# Proposed 1000-test distribution — support status

| # | Category | Tests | Current support |
|---|----------|------:|-----------------|
| 1 | HTML y estructura | 80 | Supported (s01, s19) |
| 2 | Selectores y cascada CSS | 100 | Partial (variables/@media gaps) |
| 3 | Box model y geometría | 120 | Partial (calc() gap) |
| 4 | Tipografía y texto | 90 | Supported |
| 5 | Colores, fondos y decoración | 100 | Partial (gradients partial) |
| 6 | Flexbox | 70 | Blocked (gap.006/016) |
| 7 | CSS Grid | 70 | Blocked (gap.006) |
| 8 | Diseño responsive | 80 | Supported (responsive sweep) |
| 9 | Formularios y controles | 60 | Partial |
| 10 | Imágenes y medios | 40 | Partial (img paint wiring gap.010, video gap.031) |
| 11 | Transformaciones y animaciones | 60 | Partial (animation timing gap.021) |
| 12 | Pseudoelementos | 35 | Blocked (not implemented) |
| 13 | Posicionamiento y desbordamiento | 55 | Partial (absolute/fixed/float gaps) |
| 14 | SVG y gráficos vectoriales | 20 | Blocked (gap.011) |
| 15 | Comportamiento predeterminado y accesibilidad | 20 | Partial (a11y tree gap.027) |

Total: 1000.

Notes:
- Lab sections currently cover ~1700 cases across 19 sections.
- Blocked capabilities are documented in debug/lab/sections/s17_gaps.py.
- Graphics engine supports block/inline layout, text, images (decode), scroll (basic), transforms.
- Missing for full distribution: flexbox, grid, calc(), CSS variables, absolute/fixed/float, pseudoelements, SVG, a11y tree, video.
