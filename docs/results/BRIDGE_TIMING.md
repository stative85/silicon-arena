# Bridge-Native Timing — Healthy Envelope

**Regime:** bridge v1, `EXPLICIT_RESIDENCY_MODE`, context 8192, Q4_K_M, `max_active = 2`.
Hot set frozen for the whole run; no swapping, no policy tuning, no band changes mid-run.

**Instrument:** `tools/bridge_collect.gd`. Timings come from the bridge's own streaming path, so `ttft_ms` is real first-content latency.

No combined score. A single number would average away the structure the bands need.

> **Read `CENSORED` cells carefully.** The healthy-baseline filter excludes TTFT > 1500 ms, which is the current global `HARD_DEGRADED` tooth. In cells where healthy large-prompt prefill approaches that value, the filter removes the upper tail of the very distribution the bands are meant to be derived from. Those cells' `p95`/`p99` are **lower bounds, not estimates**.

```
healthy reference samples  992
excluded from baseline     88
```

## queue_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    SMALL    1        60       0       0       0       1       0       1
lfm2.5    SMALL    2        60       0       0       1       1       0       1
lfm2.5    MEDIUM   1        60       0       0       0       0       0       1
lfm2.5    MEDIUM   2        60       0       0       0       1       0       1
lfm2.5    LARGE    1        60       0       0       0       0       0       1
lfm2.5    LARGE    2        60       0       0       1       1       0       1
h2o       SMALL    1        60       0       0       1       1       0       1
h2o       SMALL    2        60       0       0       1       1       0       1
h2o       MEDIUM   1        60       0       0       0       1       0       1
h2o       MEDIUM   2        60       0       0       0       0       0       1
h2o       LARGE    1        60       0       0       0       1       0       1
h2o       LARGE    2        30       0       0       1       1       0       1 CENSORED 30 (50%)
falcon    SMALL    1        60       0       0       0       1       0       1
falcon    SMALL    2        60       0       0       0       1       0       1
falcon    MEDIUM   1        60       0       0       0       1       0       1
falcon    MEDIUM   2        60       0       0       0       1       0       1
falcon    LARGE    1        60       0       0       1       1       0       1
falcon    LARGE    2         2       0       0       0       0       0       0 CENSORED 58 (97%)
```

## connect_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    SMALL    1        60       1       1       1       1       0       1
lfm2.5    SMALL    2        60       1       1       1       1       0       1
lfm2.5    MEDIUM   1        60       1       1       1       1       0       1
lfm2.5    MEDIUM   2        60       0       1       1       1       0       2
lfm2.5    LARGE    1        60       1       1       1       1       0       1
lfm2.5    LARGE    2        60       1       1       1       1       0       1
h2o       SMALL    1        60       1       1       1       1       0       2
h2o       SMALL    2        60       1       1       1       1       0       2
h2o       MEDIUM   1        60       0       1       1       1       0       1
h2o       MEDIUM   2        60       0       1       1       1       0       1
h2o       LARGE    1        60       1       1       1       2       0       2
h2o       LARGE    2        30       1       1       1       1       0       1 CENSORED 30 (50%)
falcon    SMALL    1        60       1       1       1       1       0       1
falcon    SMALL    2        60       0       1       1       1       0       1
falcon    MEDIUM   1        60       1       1       1       1       0       3
falcon    MEDIUM   2        60       0       1       1       1       0       1
falcon    LARGE    1        60       1       1       1       1       0       1
falcon    LARGE    2         2       1       1       1       1       0       1 CENSORED 58 (97%)
```

## ttft_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    SMALL    1        60      77      87      88      95      56     119
lfm2.5    SMALL    2        60      99     169     174     190      66     220
lfm2.5    MEDIUM   1        60     106     122     126     133      83     134
lfm2.5    MEDIUM   2        60     172     234     242     249      89     260
lfm2.5    LARGE    1        60     419     438     441     457     399     460
lfm2.5    LARGE    2        60     605     679     721     739     528     772
h2o       SMALL    1        60      90     100     108     120      66     238
h2o       SMALL    2        60     100     138     149     230      70     311
h2o       MEDIUM   1        60     152     159     179     185     138     186
h2o       MEDIUM   2        60     225     260     292     298     158     308
h2o       LARGE    1        60     946    1026    1048    1076     750    1122
h2o       LARGE    2        30    1199    1242    1246    1258    1128    1258 CENSORED 30 (50%)
falcon    SMALL    1        60     187     203     210     218     124     388
falcon    SMALL    2        60     280     362     370     395     188     453
falcon    MEDIUM   1        60     367     447     493     635     248    1177
falcon    MEDIUM   2        60     487     599     611     627     327     630
falcon    LARGE    1        60    1335    1414    1434    1476    1230    1481
falcon    LARGE    2         2    1452    1452    1452    1452    1441    1452 CENSORED 58 (97%)
```

## generation_after_first_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    SMALL    1        60     274     421     447     469     171     481
lfm2.5    SMALL    2        60     203     360     371     401     158     433
lfm2.5    MEDIUM   1        60     214     278     294     298     178     328
lfm2.5    MEDIUM   2        60     231     276     290     319     179     342
lfm2.5    LARGE    1        60     315     370     377     395     260     420
lfm2.5    LARGE    2        60     386     425     451     468     290     473
h2o       SMALL    1        60     479     519     530     532     448     534
h2o       SMALL    2        60     490     537     546     549     443     563
h2o       MEDIUM   1        60     442     448     449     455     428     456
h2o       MEDIUM   2        60     517     542     565     587     442     602
h2o       LARGE    1        60     479     505     509     534     441     543
h2o       LARGE    2        30     492     517     519     546     448     546 CENSORED 30 (50%)
falcon    SMALL    1        60     483     529     531     534     385     534
falcon    SMALL    2        60     494     547     569     628     381     651
falcon    MEDIUM   1        60     485     514     522     530     359     536
falcon    MEDIUM   2        60     488     534     549     563     352     618
falcon    LARGE    1        60     501     537     551     584     417     594
falcon    LARGE    2         2     490     490     490     490     428     490 CENSORED 58 (97%)
```

## total_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    SMALL    1        60     352     496     522     538     245     538
lfm2.5    SMALL    2        60     312     470     496     542     231     547
lfm2.5    MEDIUM   1        60     327     399     403     414     268     462
lfm2.5    MEDIUM   2        60     388     488     518     540     275     586
lfm2.5    LARGE    1        60     733     796     800     815     669     837
lfm2.5    LARGE    2        60     981    1085    1103    1135     880    1137
h2o       SMALL    1        60     572     612     624     627     533     717
h2o       SMALL    2        60     604     654     662     673     533     775
h2o       MEDIUM   1        60     593     600     628     634     585     635
h2o       MEDIUM   2        60     723     780     800     812     660     825
h2o       LARGE    1        60    1422    1495    1526    1594    1227    1620
h2o       LARGE    2        30    1696    1757    1760    1792    1576    1792 CENSORED 30 (50%)
falcon    SMALL    1        60     675     720     724     736     558     919
falcon    SMALL    2        60     799     869     909     919     644     948
falcon    MEDIUM   1        60     840     954    1026    1127     696    1677
falcon    MEDIUM   2        60     978    1098    1121    1131     703    1160
falcon    LARGE    1        60    1831    1934    1962    1994    1702    1998
falcon    LARGE    2         2    1942    1942    1942    1942    1869    1942 CENSORED 58 (97%)
```

## Serial correlation of TTFT

Are slow calls isolated spikes, or persistent regimes? The observed longest run of consecutive slow calls (above the cell's own p75) is compared with 200 shuffles of the same values.

`p` is the fraction of shuffles matching or beating the observed run. A low `p` means the slowness clusters more than chance allows.

```
MODEL     BUCKET   load      n   slow>ms      run  shuffled       p
lfm2.5    SMALL    1        60        84        2      2.73   0.990
lfm2.5    SMALL    2        60       122        2      2.59   0.995
lfm2.5    MEDIUM   1        60       117        3      2.41   0.360
lfm2.5    MEDIUM   2        60       187        2      2.63   0.990
lfm2.5    LARGE    1        60       427        3      2.11   0.220
lfm2.5    LARGE    2        60       629        3      2.62   0.470
h2o       SMALL    1        60        94        3      2.49   0.410
h2o       SMALL    2        60       121        2      2.52   0.980
h2o       MEDIUM   1        60       158        5      2.04   0.000
h2o       MEDIUM   2        60       248        2      2.58   0.990
h2o       LARGE    1        60       982        6      2.50   0.005
h2o       LARGE    2        30      1230        3      1.98   0.160
falcon    SMALL    1        60       200        3      2.64   0.515
falcon    SMALL    2        60       319        3      2.65   0.520
falcon    MEDIUM   1        60       418        4      2.63   0.145
falcon    MEDIUM   2        60       555        1      2.69   1.000
falcon    LARGE    1        60      1364        3      2.76   0.575
```

**2 of 17 cells show clustering beyond chance (p < 0.05).**

## Exclusions

Excluded records are kept in the raw dataset with a reason. They are runtime evidence, not healthy reference samples.

```
MODEL     BUCKET   load  reason                     ttft_ms
falcon    LARGE    2     hard_degraded_ttft         1537
h2o       LARGE    2     hard_degraded_ttft         1662
falcon    LARGE    2     hard_degraded_ttft         2333
falcon    LARGE    2     hard_degraded_ttft         1584
h2o       LARGE    2     hard_degraded_ttft         1619
falcon    LARGE    2     hard_degraded_ttft         2204
falcon    LARGE    2     hard_degraded_ttft         1593
h2o       LARGE    2     hard_degraded_ttft         1610
falcon    LARGE    2     hard_degraded_ttft         2210
falcon    LARGE    2     hard_degraded_ttft         1571
h2o       LARGE    2     hard_degraded_ttft         1675
falcon    LARGE    2     hard_degraded_ttft         2182
falcon    LARGE    2     hard_degraded_ttft         1567
h2o       LARGE    2     hard_degraded_ttft         1594
falcon    LARGE    2     hard_degraded_ttft         2200
h2o       LARGE    2     hard_degraded_ttft         1556
falcon    LARGE    2     hard_degraded_ttft         2166
falcon    LARGE    2     hard_degraded_ttft         1540
h2o       LARGE    2     hard_degraded_ttft         1597
falcon    LARGE    2     hard_degraded_ttft         1974
falcon    LARGE    2     hard_degraded_ttft         1542
h2o       LARGE    2     hard_degraded_ttft         1629
falcon    LARGE    2     hard_degraded_ttft         1933
falcon    LARGE    2     hard_degraded_ttft         1584
h2o       LARGE    2     hard_degraded_ttft         1575
falcon    LARGE    2     hard_degraded_ttft         1940
falcon    LARGE    2     hard_degraded_ttft         1556
h2o       LARGE    2     hard_degraded_ttft         1590
falcon    LARGE    2     hard_degraded_ttft         1970
falcon    LARGE    2     hard_degraded_ttft         1588
h2o       LARGE    2     hard_degraded_ttft         1590
falcon    LARGE    2     hard_degraded_ttft         1943
falcon    LARGE    2     hard_degraded_ttft         1555
h2o       LARGE    2     hard_degraded_ttft         1530
falcon    LARGE    2     hard_degraded_ttft         2017
falcon    LARGE    2     hard_degraded_ttft         1573
h2o       LARGE    2     hard_degraded_ttft         1618
falcon    LARGE    2     hard_degraded_ttft         1939
falcon    LARGE    2     hard_degraded_ttft         1543
h2o       LARGE    2     hard_degraded_ttft         1589
falcon    LARGE    2     hard_degraded_ttft         1959
falcon    LARGE    2     hard_degraded_ttft         1627
h2o       LARGE    2     hard_degraded_ttft         1607
falcon    LARGE    2     hard_degraded_ttft         2013
falcon    LARGE    2     hard_degraded_ttft         1610
h2o       LARGE    2     hard_degraded_ttft         1629
falcon    LARGE    2     hard_degraded_ttft         2069
falcon    LARGE    2     hard_degraded_ttft         1573
h2o       LARGE    2     hard_degraded_ttft         1637
falcon    LARGE    2     hard_degraded_ttft         1999
falcon    LARGE    2     hard_degraded_ttft         1621
h2o       LARGE    2     hard_degraded_ttft         1648
falcon    LARGE    2     hard_degraded_ttft         2038
falcon    LARGE    2     hard_degraded_ttft         1585
h2o       LARGE    2     hard_degraded_ttft         1640
falcon    LARGE    2     hard_degraded_ttft         1985
falcon    LARGE    2     hard_degraded_ttft         1597
h2o       LARGE    2     hard_degraded_ttft         1665
falcon    LARGE    2     hard_degraded_ttft         2072
falcon    LARGE    2     hard_degraded_ttft         1553
h2o       LARGE    2     hard_degraded_ttft         1626
falcon    LARGE    2     hard_degraded_ttft         2053
falcon    LARGE    2     hard_degraded_ttft         1579
h2o       LARGE    2     hard_degraded_ttft         1640
falcon    LARGE    2     hard_degraded_ttft         2011
h2o       LARGE    2     hard_degraded_ttft         1552
falcon    LARGE    2     hard_degraded_ttft         2179
falcon    LARGE    2     hard_degraded_ttft         1523
h2o       LARGE    2     hard_degraded_ttft         1550
falcon    LARGE    2     hard_degraded_ttft         2018
falcon    LARGE    2     hard_degraded_ttft         1615
h2o       LARGE    2     hard_degraded_ttft         1658
falcon    LARGE    2     hard_degraded_ttft         1996
falcon    LARGE    2     hard_degraded_ttft         1590
h2o       LARGE    2     hard_degraded_ttft         1662
falcon    LARGE    2     hard_degraded_ttft         1984
falcon    LARGE    2     hard_degraded_ttft         1574
h2o       LARGE    2     hard_degraded_ttft         1677
falcon    LARGE    2     hard_degraded_ttft         2022
falcon    LARGE    2     hard_degraded_ttft         1625
h2o       LARGE    2     hard_degraded_ttft         1659
falcon    LARGE    2     hard_degraded_ttft         2037
falcon    LARGE    2     hard_degraded_ttft         1567
h2o       LARGE    2     hard_degraded_ttft         1636
falcon    LARGE    2     hard_degraded_ttft         2002
falcon    LARGE    2     hard_degraded_ttft         1577
h2o       LARGE    2     hard_degraded_ttft         1665
falcon    LARGE    2     hard_degraded_ttft         2004
```

## Bands are NOT derived here

This document freezes distributions only. The per-model `SUSPECT` band is chosen after inspecting these numbers, not before — and the global `HARD_DEGRADED` tooth (TTFT > 1500 ms) stays as it is, because the external benchmark showed a wide gap between healthy hundreds-of-milliseconds behaviour and pathological multi-second TTFT.
