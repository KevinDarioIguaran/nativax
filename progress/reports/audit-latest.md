# NativaX — auditoría de interfaces JSON

**Run:** `20261025T192219-s2-re200104` · commit `7061330` (árbol con cambios) · 2026-10-25T20:01:04 → 2026-10-25T20:07:49

Pantallas JSON compiladas a HTML y ejecutadas en NativaX y en Chromium (referencia). Chromium es referencia, no verdad absoluta: los conflictos de oráculo no cuentan como defectos.

## Resumen

| Métrica | Valor |
|---|---:|
| Generados | 1415 |
| Rechazados por el esquema | 40 |
| …de ellos negativos deliberados | 40 |
| Ejecutados | 400 |
| Verificados (ambos motores) | 400 |
| Sin defectos | 0 |
| Con defectos | 400 |
| No concluyentes | 0 |
| Defectos únicos | 145 |
| Nuevos | 2 |
| Regresiones | 0 |
| Reproducidos al re-ejecutar | 145 |
| Minimizados | 8 |
| Hallazgos brutos | 16433 |
| Duplicados agrupados | 6086 |
| Conflictos de oráculo | 0 |
| Tiempo total | 405.2 s |
| Defectos únicos por minuto | 21.47 |
| RSS máx. del arnés NativaX | 334 MB |

## Cobertura

| Dimensión | Generada | Ejecutada | Verificada | Universo |
|---|---:|---:|---:|---:|
| componentes | 18 | 18 | 18 | 20 |
| propiedades | 44 | 44 | 44 | 49 |
| componente×propiedad | 655 | 655 | 655 | 980 |
| valores | 254 | 254 | 254 | 316 |
| pares de propiedades | 899 | 899 | 899 | 1176 |
| anidamiento padre>hijo | 137 | 137 | 137 | — |
| acciones | 5 | 5 | 5 | 7 |
| transiciones | 4 | 4 | 4 | 49 |
| profundidad | 11 | 11 | 11 | 11 |
| filas pairwise | 46 | 46 | 46 | 46 |

## Estrategias (mismo presupuesto por ronda)

| Familia | Ejecutados | ms medio | Defectos nuevos (primera vez) | Defectos/escenario |
|---|---:|---:|---:|---:|
| adversarial | 19 | 365 | 0 | 0.000 |
| basic | 72 | 385 | 9 | 0.125 |
| combinatorial | 78 | 379 | 11 | 0.141 |
| interaction | 56 | 444 | 7 | 0.125 |
| invalid | 19 | 326 | 0 | 0.000 |
| mutation | 24 | 416 | 1 | 0.042 |
| random | 132 | 547 | 117 | 0.886 |
| regression | 0 | 0 | 0 | 0.000 |

## Defectos

| Issue | Sev. | Tipo | Subsistema | Componente | Propiedad | Ocurr. | Min. | Repro | Novedad |
|---|---|---|---|---|---|---:|---|---|---|
| [NX-77A5FFB5](../../debug/artifacts/audit/latest/issues/NX-77A5FFB5.md) | critical | crash | layout | — | — | 1 | sí | sí | new |
| [NX-7874C149](../../debug/artifacts/audit/latest/issues/NX-7874C149.md) | critical | crash | layout | — | — | 1 | sí | sí | new |
| [NX-B0A90E84](../../debug/artifacts/audit/latest/issues/NX-B0A90E84.md) | high | assertion | accessibility_focus | — | focused | 8 | sí | sí | known |
| [NX-AE2D838B](../../debug/artifacts/audit/latest/issues/NX-AE2D838B.md) | high | missing | render | textarea | — | 4 | sí | sí | known |
| [NX-2B9D33EB](../../debug/artifacts/audit/latest/issues/NX-2B9D33EB.md) | high | missing | render | link | — | 4 | sí | sí | known |
| [NX-C307039D](../../debug/artifacts/audit/latest/issues/NX-C307039D.md) | high | missing | render | form | — | 3 | sí | sí | known |
| [NX-5E22DFE9](../../debug/artifacts/audit/latest/issues/NX-5E22DFE9.md) | high | missing | render | input | — | 3 | sí | sí | known |
| [NX-1879AE3C](../../debug/artifacts/audit/latest/issues/NX-1879AE3C.md) | high | missing | render | column | — | 3 | sí | sí | known |
| [NX-FA8FDE46](../../debug/artifacts/audit/latest/issues/NX-FA8FDE46.md) | high | missing | render | checkbox | — | 2 | no | sí | known |
| [NX-A23FCAF1](../../debug/artifacts/audit/latest/issues/NX-A23FCAF1.md) | high | missing | render | inline_text | — | 2 | no | sí | known |
| [NX-188EA1AC](../../debug/artifacts/audit/latest/issues/NX-188EA1AC.md) | high | missing | render | scroll | — | 2 | no | sí | known |
| [NX-AB2D36B2](../../debug/artifacts/audit/latest/issues/NX-AB2D36B2.md) | high | missing | render | spacer | — | 2 | no | sí | known |
| [NX-34B98A2A](../../debug/artifacts/audit/latest/issues/NX-34B98A2A.md) | high | missing | render | container | — | 2 | no | sí | known |
| [NX-3E5D304E](../../debug/artifacts/audit/latest/issues/NX-3E5D304E.md) | high | missing | render | grid | — | 2 | no | sí | known |
| [NX-A2B0EC29](../../debug/artifacts/audit/latest/issues/NX-A2B0EC29.md) | high | missing | render | select | — | 2 | no | sí | known |
| [NX-3B5C7EE0](../../debug/artifacts/audit/latest/issues/NX-3B5C7EE0.md) | high | geometry | layout | link | size | 1 | no | sí | known |
| [NX-5E6D5D97](../../debug/artifacts/audit/latest/issues/NX-5E6D5D97.md) | high | geometry | layout | link | size | 1 | no | sí | known |
| [NX-D87CFD95](../../debug/artifacts/audit/latest/issues/NX-D87CFD95.md) | high | geometry | layout | link | size | 1 | no | sí | known |
| [NX-A3C3F582](../../debug/artifacts/audit/latest/issues/NX-A3C3F582.md) | high | geometry | layout | link | size | 1 | no | sí | known |
| [NX-5ED2165F](../../debug/artifacts/audit/latest/issues/NX-5ED2165F.md) | high | geometry | layout | text | size | 1 | no | sí | known |
| [NX-3A2FA0B6](../../debug/artifacts/audit/latest/issues/NX-3A2FA0B6.md) | high | geometry | layout | heading | size | 1 | no | sí | known |
| [NX-2340B536](../../debug/artifacts/audit/latest/issues/NX-2340B536.md) | high | geometry | layout | inline_text | size | 1 | no | sí | known |
| [NX-466D20CD](../../debug/artifacts/audit/latest/issues/NX-466D20CD.md) | high | geometry | layout | link | size | 1 | no | sí | known |
| [NX-07B36427](../../debug/artifacts/audit/latest/issues/NX-07B36427.md) | high | missing | render | screen | — | 1 | no | sí | known |
| [NX-5E1DA327](../../debug/artifacts/audit/latest/issues/NX-5E1DA327.md) | high | missing | render | stack | — | 1 | no | sí | known |
| [NX-C2DC1437](../../debug/artifacts/audit/latest/issues/NX-C2DC1437.md) | high | missing | render | heading | — | 1 | no | sí | known |
| [NX-C371CA77](../../debug/artifacts/audit/latest/issues/NX-C371CA77.md) | high | missing | render | button | — | 1 | no | sí | known |
| [NX-AB16E986](../../debug/artifacts/audit/latest/issues/NX-AB16E986.md) | medium | style | css | button, checkbox, input | border-radius | 985 | no | sí | known |
| [NX-F75461DC](../../debug/artifacts/audit/latest/issues/NX-F75461DC.md) | medium | style | css | button, checkbox, input | box-sizing | 661 | no | sí | known |
| [NX-9116FBD0](../../debug/artifacts/audit/latest/issues/NX-9116FBD0.md) | medium | style | css | button, input | border-width | 614 | no | sí | known |
| [NX-5604C83D](../../debug/artifacts/audit/latest/issues/NX-5604C83D.md) | medium | style | css | checkbox, column, container | border-width | 526 | no | sí | known |
| [NX-9CC26021](../../debug/artifacts/audit/latest/issues/NX-9CC26021.md) | medium | style | css | checkbox, column, container | border-color | 510 | no | sí | known |
| [NX-52466E6C](../../debug/artifacts/audit/latest/issues/NX-52466E6C.md) | medium | style | css | button | border-color | 367 | no | sí | known |
| [NX-9B9AC4D3](../../debug/artifacts/audit/latest/issues/NX-9B9AC4D3.md) | medium | style | css | button | border-style | 367 | no | sí | known |
| [NX-7F106229](../../debug/artifacts/audit/latest/issues/NX-7F106229.md) | medium | style | css | input, select | overflow | 344 | no | sí | known |
| [NX-CC812F67](../../debug/artifacts/audit/latest/issues/NX-CC812F67.md) | medium | style | css | input | border-style | 247 | no | sí | known |
| [NX-3AFAD784](../../debug/artifacts/audit/latest/issues/NX-3AFAD784.md) | medium | style | css | textarea | padding | 130 | no | sí | known |
| [NX-6F350465](../../debug/artifacts/audit/latest/issues/NX-6F350465.md) | medium | style | css | scroll, textarea | overflow | 127 | no | sí | known |
| [NX-BF81EF97](../../debug/artifacts/audit/latest/issues/NX-BF81EF97.md) | medium | style | css | textarea | overflow | 116 | no | sí | known |
| [NX-AC39F82C](../../debug/artifacts/audit/latest/issues/NX-AC39F82C.md) | medium | style | css | select | align-items | 113 | no | sí | known |
| [NX-40EEC26F](../../debug/artifacts/audit/latest/issues/NX-40EEC26F.md) | medium | style | css | select | background-color | 108 | no | sí | known |
| [NX-7488F0AD](../../debug/artifacts/audit/latest/issues/NX-7488F0AD.md) | medium | style | css | select | white-space | 98 | no | sí | known |
| [NX-7F45BE7C](../../debug/artifacts/audit/latest/issues/NX-7F45BE7C.md) | medium | events | events | — | events | 73 | no | sí | known |
| [NX-810719CA](../../debug/artifacts/audit/latest/issues/NX-810719CA.md) | medium | focus | accessibility_focus | button | activeElement | 68 | no | sí | known |
| [NX-E3AC644C](../../debug/artifacts/audit/latest/issues/NX-E3AC644C.md) | medium | style | css | button, checkbox, column | aspect-ratio | 68 | no | sí | known |
| [NX-C15B2F22](../../debug/artifacts/audit/latest/issues/NX-C15B2F22.md) | medium | style | css | button, checkbox, column | transform | 41 | no | sí | known |
| [NX-745A9687](../../debug/artifacts/audit/latest/issues/NX-745A9687.md) | medium | style | css | input, scroll, select | overflow | 33 | no | sí | known |
| [NX-A9E583FF](../../debug/artifacts/audit/latest/issues/NX-A9E583FF.md) | medium | style | css | button, column, container | box-shadow | 29 | no | sí | known |
| [NX-50EF8BA1](../../debug/artifacts/audit/latest/issues/NX-50EF8BA1.md) | medium | style | css | button, checkbox, input | border-radius | 28 | no | sí | known |
| [NX-59B446D0](../../debug/artifacts/audit/latest/issues/NX-59B446D0.md) | medium | overflow | layout | button | overflow_x | 24 | no | sí | known |
| [NX-96FEFAA5](../../debug/artifacts/audit/latest/issues/NX-96FEFAA5.md) | medium | overflow | layout | button | overflow_y | 24 | no | sí | known |
| [NX-8FCCC27B](../../debug/artifacts/audit/latest/issues/NX-8FCCC27B.md) | medium | style | css | button, checkbox, column | padding | 21 | no | sí | known |
| [NX-83A0FC51](../../debug/artifacts/audit/latest/issues/NX-83A0FC51.md) | medium | style | css | button, checkbox, input | text-transform | 20 | no | sí | known |
| [NX-9DEF2DCD](../../debug/artifacts/audit/latest/issues/NX-9DEF2DCD.md) | medium | style | css | checkbox, input, select | text-align | 19 | no | sí | known |
| [NX-517A3E56](../../debug/artifacts/audit/latest/issues/NX-517A3E56.md) | medium | style | css | button, column, container | margin | 16 | no | sí | known |
| [NX-CE623F0C](../../debug/artifacts/audit/latest/issues/NX-CE623F0C.md) | medium | style | css | button, checkbox, input | letter-spacing | 16 | no | sí | known |
| [NX-E923490C](../../debug/artifacts/audit/latest/issues/NX-E923490C.md) | medium | style | css | checkbox, input, select | text-align | 15 | no | sí | known |
| [NX-F360C5F1](../../debug/artifacts/audit/latest/issues/NX-F360C5F1.md) | medium | style | css | button, checkbox, input | text-transform | 15 | no | sí | known |
| [NX-85B0B0F7](../../debug/artifacts/audit/latest/issues/NX-85B0B0F7.md) | medium | style | css | button, checkbox, input | font-weight | 14 | no | sí | known |
| [NX-36D6C2C9](../../debug/artifacts/audit/latest/issues/NX-36D6C2C9.md) | medium | style | css | button, checkbox, select | letter-spacing | 14 | no | sí | known |
| [NX-B01DD6CD](../../debug/artifacts/audit/latest/issues/NX-B01DD6CD.md) | medium | style | css | button, checkbox, column | transform | 14 | no | sí | known |
| [NX-8CAA2FC7](../../debug/artifacts/audit/latest/issues/NX-8CAA2FC7.md) | medium | style | css | button, checkbox, input | font-style | 14 | no | sí | known |
| [NX-3E39F915](../../debug/artifacts/audit/latest/issues/NX-3E39F915.md) | medium | overflow | layout | scroll | overflow_y | 10 | no | sí | known |
| [NX-6E6485F5](../../debug/artifacts/audit/latest/issues/NX-6E6485F5.md) | medium | style | css | column, container, form | font-size | 10 | no | sí | known |
| [NX-CFA0F1A9](../../debug/artifacts/audit/latest/issues/NX-CFA0F1A9.md) | medium | events | events | — | events | 10 | no | sí | known |
| [NX-4E8CD998](../../debug/artifacts/audit/latest/issues/NX-4E8CD998.md) | medium | style | css | checkbox, input, select | font-weight | 9 | no | sí | known |
| [NX-B66E3F23](../../debug/artifacts/audit/latest/issues/NX-B66E3F23.md) | medium | style | css | button, checkbox, input | letter-spacing | 9 | no | sí | known |
| [NX-488C23A0](../../debug/artifacts/audit/latest/issues/NX-488C23A0.md) | medium | focus | accessibility_focus | button | activeElement | 9 | no | sí | known |
| [NX-74BB8F00](../../debug/artifacts/audit/latest/issues/NX-74BB8F00.md) | medium | overflow | layout | column | overflow_x | 7 | no | sí | known |
| [NX-08FE0720](../../debug/artifacts/audit/latest/issues/NX-08FE0720.md) | medium | style | css | button, input, select | font-weight | 7 | no | sí | known |
| [NX-6F4F860C](../../debug/artifacts/audit/latest/issues/NX-6F4F860C.md) | medium | overflow | layout | heading | overflow_y | 7 | no | sí | known |
| [NX-06C3FDAC](../../debug/artifacts/audit/latest/issues/NX-06C3FDAC.md) | medium | overflow | layout | row | overflow_x | 7 | no | sí | known |
| [NX-29F991D1](../../debug/artifacts/audit/latest/issues/NX-29F991D1.md) | medium | style | css | checkbox | border-style | 6 | no | sí | known |
| [NX-7EF0C531](../../debug/artifacts/audit/latest/issues/NX-7EF0C531.md) | medium | style | css | checkbox, input, select | text-align | 6 | no | sí | known |
| [NX-3324D23B](../../debug/artifacts/audit/latest/issues/NX-3324D23B.md) | medium | style | css | checkbox, input, select | text-transform | 6 | no | sí | known |
| [NX-32FC20F1](../../debug/artifacts/audit/latest/issues/NX-32FC20F1.md) | medium | style | css | button, checkbox, select | border-radius | 6 | no | sí | known |
| [NX-F0562614](../../debug/artifacts/audit/latest/issues/NX-F0562614.md) | medium | overflow | layout | screen | overflow_x | 6 | no | sí | known |
| [NX-0F30E3F8](../../debug/artifacts/audit/latest/issues/NX-0F30E3F8.md) | medium | overflow | layout | row | overflow_y | 5 | no | sí | known |
| [NX-FD934FEB](../../debug/artifacts/audit/latest/issues/NX-FD934FEB.md) | medium | overflow | layout | row | overflow_x | 5 | no | sí | known |
| [NX-B7BF6DCC](../../debug/artifacts/audit/latest/issues/NX-B7BF6DCC.md) | medium | overflow | layout | row | overflow_y | 5 | no | sí | known |
| [NX-09C5CA00](../../debug/artifacts/audit/latest/issues/NX-09C5CA00.md) | medium | style | css | checkbox | padding | 5 | no | sí | known |
| [NX-02019E33](../../debug/artifacts/audit/latest/issues/NX-02019E33.md) | medium | style | css | container, heading, row | border-color | 5 | no | sí | known |
| [NX-5852D5E2](../../debug/artifacts/audit/latest/issues/NX-5852D5E2.md) | medium | style | css | input, select, textarea | text-align | 5 | no | sí | known |
| [NX-1EAA2FEA](../../debug/artifacts/audit/latest/issues/NX-1EAA2FEA.md) | medium | overflow | layout | spacer | overflow_x | 5 | no | sí | known |
| [NX-EC8F7352](../../debug/artifacts/audit/latest/issues/NX-EC8F7352.md) | medium | overflow | layout | spacer | overflow_y | 5 | no | sí | known |
| [NX-0DD22AC3](../../debug/artifacts/audit/latest/issues/NX-0DD22AC3.md) | medium | overflow | layout | inline_text | overflow_y | 5 | no | sí | known |
| [NX-157A3276](../../debug/artifacts/audit/latest/issues/NX-157A3276.md) | medium | style | css | textarea | overflow | 5 | no | sí | known |
| [NX-2B0F7321](../../debug/artifacts/audit/latest/issues/NX-2B0F7321.md) | medium | events | events | — | events | 5 | no | sí | known |
| [NX-42208C60](../../debug/artifacts/audit/latest/issues/NX-42208C60.md) | medium | focus | accessibility_focus | checkbox | activeElement | 5 | no | sí | known |
| [NX-07D4D5D7](../../debug/artifacts/audit/latest/issues/NX-07D4D5D7.md) | medium | style | css | checkbox | border-width | 4 | no | sí | known |
| [NX-F78A15E8](../../debug/artifacts/audit/latest/issues/NX-F78A15E8.md) | medium | style | css | checkbox | border-color | 4 | no | sí | known |
| [NX-2BFC4F9D](../../debug/artifacts/audit/latest/issues/NX-2BFC4F9D.md) | medium | overflow | layout | stack | overflow_x | 4 | no | sí | known |
| [NX-9DBB9A18](../../debug/artifacts/audit/latest/issues/NX-9DBB9A18.md) | medium | overflow | layout | stack | overflow_y | 4 | no | sí | known |
| [NX-56F88E9E](../../debug/artifacts/audit/latest/issues/NX-56F88E9E.md) | medium | overflow | layout | text | overflow_y | 4 | no | sí | known |
| [NX-794099DF](../../debug/artifacts/audit/latest/issues/NX-794099DF.md) | medium | style | css | checkbox, container, form | border-color | 4 | no | sí | known |
| [NX-30DB78A4](../../debug/artifacts/audit/latest/issues/NX-30DB78A4.md) | medium | overflow | layout | stack | overflow_y | 4 | no | sí | known |
| [NX-4398E23B](../../debug/artifacts/audit/latest/issues/NX-4398E23B.md) | medium | style | css | select | white-space | 4 | no | sí | known |
| [NX-BE23EAF9](../../debug/artifacts/audit/latest/issues/NX-BE23EAF9.md) | medium | overflow | layout | container | overflow_y | 3 | no | sí | known |
| [NX-C0BC1539](../../debug/artifacts/audit/latest/issues/NX-C0BC1539.md) | medium | overflow | layout | text | overflow_x | 3 | no | sí | known |
| [NX-9C28F191](../../debug/artifacts/audit/latest/issues/NX-9C28F191.md) | medium | overflow | layout | select | overflow_x | 3 | no | sí | known |
| [NX-02773A1B](../../debug/artifacts/audit/latest/issues/NX-02773A1B.md) | medium | overflow | layout | select | overflow_y | 3 | no | sí | known |
| [NX-CEA6470C](../../debug/artifacts/audit/latest/issues/NX-CEA6470C.md) | medium | style | css | select | letter-spacing | 3 | no | sí | known |
| [NX-DEAC8D68](../../debug/artifacts/audit/latest/issues/NX-DEAC8D68.md) | medium | overflow | layout | scroll | overflow_x | 3 | no | sí | known |
| [NX-41D54176](../../debug/artifacts/audit/latest/issues/NX-41D54176.md) | medium | style | css | link | border-color | 3 | no | sí | known |
| [NX-FF97F379](../../debug/artifacts/audit/latest/issues/NX-FF97F379.md) | medium | overflow | layout | stack | overflow_x | 3 | no | sí | known |
| [NX-930C04D9](../../debug/artifacts/audit/latest/issues/NX-930C04D9.md) | medium | style | css | heading | font-size | 3 | no | sí | known |
| [NX-16400A48](../../debug/artifacts/audit/latest/issues/NX-16400A48.md) | medium | style | css | heading | margin | 3 | no | sí | known |
| [NX-2AF2DE91](../../debug/artifacts/audit/latest/issues/NX-2AF2DE91.md) | medium | style | css | grid, inline_text, stack | border-color | 3 | no | sí | known |
| [NX-3C465C5D](../../debug/artifacts/audit/latest/issues/NX-3C465C5D.md) | medium | overflow | layout | text | overflow_x | 3 | no | sí | known |
| [NX-7B598BE0](../../debug/artifacts/audit/latest/issues/NX-7B598BE0.md) | medium | overflow | layout | text | overflow_y | 3 | no | sí | known |
| [NX-0EFAE6AD](../../debug/artifacts/audit/latest/issues/NX-0EFAE6AD.md) | medium | style | css | button, input | font-weight | 3 | no | sí | known |
| [NX-8EEE3A35](../../debug/artifacts/audit/latest/issues/NX-8EEE3A35.md) | medium | overflow | layout | column | overflow_y | 2 | no | sí | known |
| [NX-97FC8F13](../../debug/artifacts/audit/latest/issues/NX-97FC8F13.md) | medium | overflow | layout | screen | overflow_y | 2 | no | sí | known |
| [NX-EA9B026A](../../debug/artifacts/audit/latest/issues/NX-EA9B026A.md) | medium | overflow | layout | scroll | overflow_x | 2 | no | sí | known |
| [NX-2EE9A648](../../debug/artifacts/audit/latest/issues/NX-2EE9A648.md) | medium | overflow | layout | grid | overflow_y | 2 | no | sí | known |
| [NX-4BA619BB](../../debug/artifacts/audit/latest/issues/NX-4BA619BB.md) | medium | overflow | layout | form | overflow_x | 2 | no | sí | known |
| [NX-5ED43A3D](../../debug/artifacts/audit/latest/issues/NX-5ED43A3D.md) | medium | style | css | spacer, text | border-width | 2 | no | sí | known |
| [NX-CD00B1F6](../../debug/artifacts/audit/latest/issues/NX-CD00B1F6.md) | medium | style | css | spacer, text | border-color | 2 | no | sí | known |
| [NX-79EF62F7](../../debug/artifacts/audit/latest/issues/NX-79EF62F7.md) | medium | overflow | layout | grid | overflow_x | 2 | no | sí | known |
| [NX-75C7DE9B](../../debug/artifacts/audit/latest/issues/NX-75C7DE9B.md) | medium | overflow | layout | heading | overflow_x | 2 | no | sí | known |
| [NX-9065A7BF](../../debug/artifacts/audit/latest/issues/NX-9065A7BF.md) | medium | overflow | layout | heading | overflow_y | 2 | no | sí | known |
| [NX-CE37A99B](../../debug/artifacts/audit/latest/issues/NX-CE37A99B.md) | medium | overflow | layout | heading | overflow_x | 2 | no | sí | known |
| [NX-20F20410](../../debug/artifacts/audit/latest/issues/NX-20F20410.md) | medium | overflow | layout | grid | overflow_y | 2 | no | sí | known |
| [NX-07056748](../../debug/artifacts/audit/latest/issues/NX-07056748.md) | medium | style | css | text | margin | 2 | no | sí | known |
| [NX-DDAA0D36](../../debug/artifacts/audit/latest/issues/NX-DDAA0D36.md) | medium | overflow | layout | inline_text | overflow_x | 2 | no | sí | known |
| [NX-1FC41AEB](../../debug/artifacts/audit/latest/issues/NX-1FC41AEB.md) | medium | overflow | layout | inline_text | overflow_y | 2 | no | sí | known |
| [NX-166C35D1](../../debug/artifacts/audit/latest/issues/NX-166C35D1.md) | medium | style | css | textarea | font-size | 2 | no | sí | known |
| [NX-66D59AC6](../../debug/artifacts/audit/latest/issues/NX-66D59AC6.md) | medium | overflow | layout | grid | overflow_x | 1 | no | sí | known |
| [NX-2BE77279](../../debug/artifacts/audit/latest/issues/NX-2BE77279.md) | medium | overflow | layout | container | overflow_x | 1 | no | sí | known |
| [NX-1FA2C345](../../debug/artifacts/audit/latest/issues/NX-1FA2C345.md) | medium | style | css | link | border-color | 1 | no | sí | known |
| [NX-D167AD11](../../debug/artifacts/audit/latest/issues/NX-D167AD11.md) | medium | overflow | layout | container | overflow_y | 1 | no | sí | known |
| [NX-41197E34](../../debug/artifacts/audit/latest/issues/NX-41197E34.md) | medium | style | css | select | white-space | 1 | no | sí | known |
| [NX-68475168](../../debug/artifacts/audit/latest/issues/NX-68475168.md) | medium | style | css | checkbox | border-radius | 1 | no | sí | known |
| [NX-0704A51F](../../debug/artifacts/audit/latest/issues/NX-0704A51F.md) | medium | style | css | textarea | display | 1 | no | sí | known |
| [NX-3F9F39AD](../../debug/artifacts/audit/latest/issues/NX-3F9F39AD.md) | medium | style | css | checkbox | padding | 1 | no | sí | known |
| [NX-B3084079](../../debug/artifacts/audit/latest/issues/NX-B3084079.md) | medium | overflow | layout | link | overflow_x | 1 | no | sí | known |
| [NX-615BB2B0](../../debug/artifacts/audit/latest/issues/NX-615BB2B0.md) | medium | overflow | layout | inline_text | overflow_x | 1 | no | sí | known |
| [NX-25800FCE](../../debug/artifacts/audit/latest/issues/NX-25800FCE.md) | medium | style | css | textarea | font-size | 1 | no | sí | known |
| [NX-8ADF9CD1](../../debug/artifacts/audit/latest/issues/NX-8ADF9CD1.md) | medium | overflow | layout | scroll | overflow_y | 1 | no | sí | known |
| [NX-0A7A246A](../../debug/artifacts/audit/latest/issues/NX-0A7A246A.md) | medium | overflow | layout | link | overflow_x | 1 | no | sí | known |
| [NX-DD985C9E](../../debug/artifacts/audit/latest/issues/NX-DD985C9E.md) | medium | overflow | layout | link | overflow_y | 1 | no | sí | known |
| [NX-ADA7BB2F](../../debug/artifacts/audit/latest/issues/NX-ADA7BB2F.md) | medium | geometry | layout | text | position | 1 | no | sí | known |
| [NX-A9AE28EA](../../debug/artifacts/audit/latest/issues/NX-A9AE28EA.md) | medium | overflow | layout | container | overflow_x | 1 | no | sí | known |
| [NX-F447E6C1](../../debug/artifacts/audit/latest/issues/NX-F447E6C1.md) | medium | overflow | layout | textarea | overflow_x | 1 | no | sí | known |
| [NX-E24031EE](../../debug/artifacts/audit/latest/issues/NX-E24031EE.md) | medium | overflow | layout | textarea | overflow_y | 1 | no | sí | known |

## Limitaciones de esta ejecución

- Chromium es la referencia; donde difiere de la especificación, la auditoría lo reporta como defecto de NativaX.
- Clicks en la referencia son eventos sintéticos en el mismo punto (elementFromPoint); Tab usa un modelo de recorrido de foco; otras teclas no se reproducen en la referencia.
- Los colores se comparan por estilo computado; no hay comparación de píxeles en esta auditoría (eso lo mide el juez visual).
- Imágenes no ejecutables: el arnés no pasa imageResolver.
