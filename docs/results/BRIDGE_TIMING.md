# Bridge-Native Timing — Healthy Envelope

**This file holds COLLECTION 2**, which carries exact per-model
`prompt_tokens`. Collection 1 (prompt size approximated from bucket) is
preserved as `bridge_timing_run1.json`; the findings written from it are in
`BRIDGE_TIMING_FINDINGS.md` and are labelled as such. Both raw datasets are
kept — neither supersedes the other, they differ in what telemetry existed.

**Regime:** bridge v1, `EXPLICIT_RESIDENCY_MODE`, context 8192, Q4_K_M, `max_active = 2`.
Hot set frozen for the whole run; no swapping, no policy tuning, no band changes mid-run.

**Instrument:** `tools/bridge_collect.gd`. Timings come from the bridge's own streaming path, so `ttft_ms` is real first-content latency.

No combined score. A single number would average away the structure the bands need.

> **Read `CENSORED` cells carefully.** The healthy-baseline filter excludes TTFT > 1500 ms, which is the current global `HARD_DEGRADED` tooth. In cells where healthy large-prompt prefill approaches that value, the filter removes the upper tail of the very distribution the bands are meant to be derived from. Those cells' `p95`/`p99` are **lower bounds, not estimates**.

```
healthy reference samples  990
excluded from baseline     90
```

## queue_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    SMALL    1        60       0       0       0       0       0       1
lfm2.5    SMALL    2        60       0       0       1       1       0       1
lfm2.5    MEDIUM   1        60       0       0       0       0       0       1
lfm2.5    MEDIUM   2        60       0       1       1       1       0       1
lfm2.5    LARGE    1        60       0       0       0       1       0       1
lfm2.5    LARGE    2        60       0       0       1       1       0       1
h2o       SMALL    1        60       0       0       0       0       0       1
h2o       SMALL    2        60       0       0       1       1       0       1
h2o       MEDIUM   1        60       0       0       0       0       0       1
h2o       MEDIUM   2        60       0       0       0       1       0       1
h2o       LARGE    1        60       0       0       0       0       0       0
h2o       LARGE    2        30       0       0       0       1       0       1 CENSORED 30 (50%)
falcon    SMALL    1        60       0       1       1       1       0       1
falcon    SMALL    2        60       0       0       0       1       0       1
falcon    MEDIUM   1        60       0       0       0       1       0       1
falcon    MEDIUM   2        60       0       0       0       0       0       1
falcon    LARGE    1        60       0       0       0       1       0       1
```

## connect_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    SMALL    1        60       1       1       1       1       0       1
lfm2.5    SMALL    2        60       1       1       1       1       0       2
lfm2.5    MEDIUM   1        60       1       1       1       1       0       1
lfm2.5    MEDIUM   2        60       1       1       1       1       0       1
lfm2.5    LARGE    1        60       1       1       1       1       0       1
lfm2.5    LARGE    2        60       1       1       1       1       0       2
h2o       SMALL    1        60       1       1       1       1       0       1
h2o       SMALL    2        60       1       1       1       1       0       2
h2o       MEDIUM   1        60       1       1       1       1       0       1
h2o       MEDIUM   2        60       0       1       1       1       0       1
h2o       LARGE    1        60       1       1       1       1       0       1
h2o       LARGE    2        30       1       1       1       1       0       1 CENSORED 30 (50%)
falcon    SMALL    1        60       1       1       1       1       0       1
falcon    SMALL    2        60       0       1       1       1       0       1
falcon    MEDIUM   1        60       0       1       1       1       0       1
falcon    MEDIUM   2        60       0       1       1       1       0       1
falcon    LARGE    1        60       1       1       1       1       0       2
```

## ttft_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    SMALL    1        60      93     109     109     111      76     137
lfm2.5    SMALL    2        60      94     122     130     138      59     140
lfm2.5    MEDIUM   1        60     138     141     142     142     123     143
lfm2.5    MEDIUM   2        60     167     203     205     215     106     218
lfm2.5    LARGE    1        60     423     439     440     449     390     452
lfm2.5    LARGE    2        60     684     782     793     802     519     822
h2o       SMALL    1        60      92      94      96     123      75     343
h2o       SMALL    2        60      97     122     130     134      69     292
h2o       MEDIUM   1        60     188     218     220     232     170     236
h2o       MEDIUM   2        60     226     264     267     268     165     276
h2o       LARGE    1        60     951     981     990    1011     750    1015
h2o       LARGE    2        30    1203    1252    1257    1266    1148    1266 CENSORED 30 (50%)
falcon    SMALL    1        60     202     219     219     220     154     341
falcon    SMALL    2        60     288     332     350     359     216     383
falcon    MEDIUM   1        60     440     504     642     740     337     890
falcon    MEDIUM   2        60     495     602     610     623     358     641
falcon    LARGE    1        60    1296    1348    1361    1388    1110    1396
```

## generation_after_first_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    SMALL    1        60     284     449     486     503     174     504
lfm2.5    SMALL    2        60     222     362     377     382     149     413
lfm2.5    MEDIUM   1        60     267     297     300     311     203     360
lfm2.5    MEDIUM   2        60     235     272     282     297     193     314
lfm2.5    LARGE    1        60     346     407     411     424     299     436
lfm2.5    LARGE    2        60     392     448     487     497     302     505
h2o       SMALL    1        60     528     544     546     551     501     553
h2o       SMALL    2        60     494     520     530     544     458     556
h2o       MEDIUM   1        60     501     503     504     505     487     505
h2o       MEDIUM   2        60     516     554     565     580     470     583
h2o       LARGE    1        60     517     521     531     533     449     536
h2o       LARGE    2        30     486     527     531     531     455     531 CENSORED 30 (50%)
falcon    SMALL    1        60     527     536     546     548     437     548
falcon    SMALL    2        60     498     538     571     583     424     591
falcon    MEDIUM   1        60     518     550     553     563     391     565
falcon    MEDIUM   2        60     510     550     569     589     338     600
falcon    LARGE    1        60     517     549     552     565     389     568
```

## total_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    SMALL    1        60     376     530     566     597     252     598
lfm2.5    SMALL    2        60     313     452     457     478     246     501
lfm2.5    MEDIUM   1        60     394     437     439     440     328     501
lfm2.5    MEDIUM   2        60     404     457     484     495     318     501
lfm2.5    LARGE    1        60     772     830     845     858     716     860
lfm2.5    LARGE    2        60    1067    1176    1216    1250     910    1280
h2o       SMALL    1        60     612     639     644     656     578     846
h2o       SMALL    2        60     594     639     653     659     538     762
h2o       MEDIUM   1        60     690     717     721     735     669     737
h2o       MEDIUM   2        60     740     769     783     796     663     798
h2o       LARGE    1        60    1461    1500    1509    1526    1242    1535
h2o       LARGE    2        30    1686    1761    1767    1797    1604    1797 CENSORED 30 (50%)
falcon    SMALL    1        60     720     738     748     752     626     869
falcon    SMALL    2        60     788     855     878     891     657     899
falcon    MEDIUM   1        60     957    1018    1131    1192     847    1422
falcon    MEDIUM   2        60     981    1131    1146    1147     732    1162
falcon    LARGE    1        60    1819    1891    1900    1923    1579    1944
```

## Serial correlation of TTFT

Are slow calls isolated spikes, or persistent regimes? The observed longest run of consecutive slow calls (above the cell's own p75) is compared with 200 shuffles of the same values.

`p` is the fraction of shuffles matching or beating the observed run. A low `p` means the slowness clusters more than chance allows.

```
MODEL     BUCKET   load      n   slow>ms      run  shuffled       p
lfm2.5    SMALL    1        60        94        3      2.13   0.200
lfm2.5    SMALL    2        60       105        3      2.61   0.495
lfm2.5    MEDIUM   1        60       140        2      2.10   0.890
lfm2.5    MEDIUM   2        60       190        1      2.68   1.000
lfm2.5    LARGE    1        60       436        2      2.57   0.985
lfm2.5    LARGE    2        60       744        1      2.58   1.000
h2o       SMALL    1        60        93        3      2.44   0.380
h2o       SMALL    2        60       111        1      2.70   1.000
h2o       MEDIUM   1        60       202        3      2.68   0.535
h2o       MEDIUM   2        60       251        1      2.43   1.000
h2o       LARGE    1        60       964        3      2.71   0.525
h2o       LARGE    2        30      1231        4      2.08   0.045
falcon    SMALL    1        60       217        3      2.36   0.335
falcon    SMALL    2        60       321        1      2.59   1.000
falcon    MEDIUM   1        60       469        5      2.67   0.035
falcon    MEDIUM   2        60       582        1      2.69   1.000
falcon    LARGE    1        60      1335        3      2.65   0.525
```

**2 of 17 cells show clustering beyond chance (p < 0.05).**

## Exclusions

Excluded records are kept in the raw dataset with a reason. They are runtime evidence, not healthy reference samples.

```
MODEL     BUCKET   load  reason                     ttft_ms
falcon    LARGE    2     hard_degraded_ttft         1572
h2o       LARGE    2     hard_degraded_ttft         1611
falcon    LARGE    2     hard_degraded_ttft         2300
falcon    LARGE    2     hard_degraded_ttft         1610
h2o       LARGE    2     hard_degraded_ttft         1657
falcon    LARGE    2     hard_degraded_ttft         2232
falcon    LARGE    2     hard_degraded_ttft         1570
h2o       LARGE    2     hard_degraded_ttft         1630
falcon    LARGE    2     hard_degraded_ttft         2251
falcon    LARGE    2     hard_degraded_ttft         1642
h2o       LARGE    2     hard_degraded_ttft         1621
falcon    LARGE    2     hard_degraded_ttft         2245
falcon    LARGE    2     hard_degraded_ttft         1580
h2o       LARGE    2     hard_degraded_ttft         1621
falcon    LARGE    2     hard_degraded_ttft         2256
falcon    LARGE    2     hard_degraded_ttft         1568
h2o       LARGE    2     hard_degraded_ttft         1580
falcon    LARGE    2     hard_degraded_ttft         2242
falcon    LARGE    2     hard_degraded_ttft         1549
h2o       LARGE    2     hard_degraded_ttft         1602
falcon    LARGE    2     hard_degraded_ttft         2266
falcon    LARGE    2     hard_degraded_ttft         1571
h2o       LARGE    2     hard_degraded_ttft         1655
falcon    LARGE    2     hard_degraded_ttft         2259
falcon    LARGE    2     hard_degraded_ttft         1583
h2o       LARGE    2     hard_degraded_ttft         1628
falcon    LARGE    2     hard_degraded_ttft         2249
falcon    LARGE    2     hard_degraded_ttft         1599
h2o       LARGE    2     hard_degraded_ttft         1573
falcon    LARGE    2     hard_degraded_ttft         2195
falcon    LARGE    2     hard_degraded_ttft         1589
h2o       LARGE    2     hard_degraded_ttft         1604
falcon    LARGE    2     hard_degraded_ttft         2245
falcon    LARGE    2     hard_degraded_ttft         1578
h2o       LARGE    2     hard_degraded_ttft         1577
falcon    LARGE    2     hard_degraded_ttft         2246
falcon    LARGE    2     hard_degraded_ttft         1538
h2o       LARGE    2     hard_degraded_ttft         1625
falcon    LARGE    2     hard_degraded_ttft         2211
falcon    LARGE    2     hard_degraded_ttft         1581
h2o       LARGE    2     hard_degraded_ttft         1659
falcon    LARGE    2     hard_degraded_ttft         2233
falcon    LARGE    2     hard_degraded_ttft         1612
h2o       LARGE    2     hard_degraded_ttft         1590
falcon    LARGE    2     hard_degraded_ttft         2249
falcon    LARGE    2     hard_degraded_ttft         1630
h2o       LARGE    2     hard_degraded_ttft         1630
falcon    LARGE    2     hard_degraded_ttft         2282
falcon    LARGE    2     hard_degraded_ttft         1615
h2o       LARGE    2     hard_degraded_ttft         1676
falcon    LARGE    2     hard_degraded_ttft         2296
falcon    LARGE    2     hard_degraded_ttft         1598
h2o       LARGE    2     hard_degraded_ttft         1686
falcon    LARGE    2     hard_degraded_ttft         2277
falcon    LARGE    2     hard_degraded_ttft         1616
h2o       LARGE    2     hard_degraded_ttft         1678
falcon    LARGE    2     hard_degraded_ttft         2307
falcon    LARGE    2     hard_degraded_ttft         1598
h2o       LARGE    2     hard_degraded_ttft         1676
falcon    LARGE    2     hard_degraded_ttft         2268
falcon    LARGE    2     hard_degraded_ttft         1642
h2o       LARGE    2     hard_degraded_ttft         1678
falcon    LARGE    2     hard_degraded_ttft         2320
falcon    LARGE    2     hard_degraded_ttft         1620
h2o       LARGE    2     hard_degraded_ttft         1659
falcon    LARGE    2     hard_degraded_ttft         2258
falcon    LARGE    2     hard_degraded_ttft         1633
h2o       LARGE    2     hard_degraded_ttft         1694
falcon    LARGE    2     hard_degraded_ttft         2281
falcon    LARGE    2     hard_degraded_ttft         1627
h2o       LARGE    2     hard_degraded_ttft         1673
falcon    LARGE    2     hard_degraded_ttft         2292
falcon    LARGE    2     hard_degraded_ttft         1627
h2o       LARGE    2     hard_degraded_ttft         1688
falcon    LARGE    2     hard_degraded_ttft         2302
falcon    LARGE    2     hard_degraded_ttft         1606
h2o       LARGE    2     hard_degraded_ttft         1714
falcon    LARGE    2     hard_degraded_ttft         2304
falcon    LARGE    2     hard_degraded_ttft         1586
h2o       LARGE    2     hard_degraded_ttft         1600
falcon    LARGE    2     hard_degraded_ttft         2199
falcon    LARGE    2     hard_degraded_ttft         1530
h2o       LARGE    2     hard_degraded_ttft         1607
falcon    LARGE    2     hard_degraded_ttft         2198
falcon    LARGE    2     hard_degraded_ttft         1561
h2o       LARGE    2     hard_degraded_ttft         1572
falcon    LARGE    2     hard_degraded_ttft         2213
falcon    LARGE    2     hard_degraded_ttft         1565
h2o       LARGE    2     hard_degraded_ttft         1630
falcon    LARGE    2     hard_degraded_ttft         2247
```

## Bands are NOT derived here

This document freezes distributions only. The per-model `SUSPECT` band is chosen after inspecting these numbers, not before — and the global `HARD_DEGRADED` tooth (TTFT > 1500 ms) stays as it is, because the external benchmark showed a wide gap between healthy hundreds-of-milliseconds behaviour and pathological multi-second TTFT.
