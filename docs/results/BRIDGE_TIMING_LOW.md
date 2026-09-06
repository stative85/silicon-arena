# Bridge-Native Timing — Healthy Envelope

**Regime:** bridge v1, `EXPLICIT_RESIDENCY_MODE`, context 8192, Q4_K_M, `max_active = 2`.
Hot set frozen for the whole run; no swapping, no policy tuning, no band changes mid-run.

**Instrument:** `tools/bridge_collect.gd`. Timings come from the bridge's own streaming path, so `ttft_ms` is real first-content latency.

No combined score. A single number would average away the structure the bands need.

> **Read `CENSORED` cells carefully.** The healthy-baseline filter excludes TTFT > 1500 ms, which is the current global `HARD_DEGRADED` tooth. In cells where healthy large-prompt prefill approaches that value, the filter removes the upper tail of the very distribution the bands are meant to be derived from. Those cells' `p95`/`p99` are **lower bounds, not estimates**.

```
healthy reference samples  1080
excluded from baseline     0
```

## queue_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    T16      1        60       0       0       0       1       0       1
lfm2.5    T16      2        60       0       0       0       0       0       0
lfm2.5    T24      1        60       0       0       1       1       0       1
lfm2.5    T24      2        60       0       0       1       1       0       1
lfm2.5    T40      1        60       0       0       0       1       0       1
lfm2.5    T40      2        60       0       0       0       1       0       1
h2o       T16      1        60       0       0       1       1       0       1
h2o       T16      2        60       0       0       1       1       0       1
h2o       T24      1        60       0       0       0       1       0       1
h2o       T24      2        60       0       0       0       1       0       1
h2o       T40      1        60       0       0       0       1       0       1
h2o       T40      2        60       0       0       1       1       0       1
falcon    T16      1        60       0       0       0       1       0       1
falcon    T16      2        60       0       0       1       1       0       1
falcon    T24      1        60       0       0       1       1       0       1
falcon    T24      2        60       0       0       1       1       0       1
falcon    T40      1        60       0       0       0       0       0       0
falcon    T40      2        60       0       0       1       1       0       1
```

## connect_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    T16      1        60       1       1       1       1       0       2
lfm2.5    T16      2        60       1       1       1       1       0       1
lfm2.5    T24      1        60       1       1       1       1       0       1
lfm2.5    T24      2        60       1       1       1       1       0       1
lfm2.5    T40      1        60       1       1       1       1       0       1
lfm2.5    T40      2        60       1       1       1       1       0       1
h2o       T16      1        60       1       1       1       1       0       1
h2o       T16      2        60       0       1       1       1       0       1
h2o       T24      1        60       1       1       1       1       0       1
h2o       T24      2        60       1       1       1       1       0       1
h2o       T40      1        60       1       1       1       1       0       2
h2o       T40      2        60       0       1       1       1       0       1
falcon    T16      1        60       0       1       1       1       0       2
falcon    T16      2        60       0       1       1       1       0       1
falcon    T24      1        60       1       1       1       1       0       2
falcon    T24      2        60       1       1       1       1       0       1
falcon    T40      1        60       1       1       1       1       0       1
falcon    T40      2        60       0       1       1       1       0       1
```

## ttft_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    T16      1        60      93      94      94      95      77      95
lfm2.5    T16      2        60      95     110     126     126      77     170
lfm2.5    T24      1        60      93      95      95     108      76     110
lfm2.5    T24      2        60     108     124     125     125      78     126
lfm2.5    T40      1        60      93      95      95      95      76      96
lfm2.5    T40      2        60      94     111     111     126      66     126
h2o       T16      1        60      92      95     108     108      76     109
h2o       T16      2        60      95     125     140     140      76     152
h2o       T24      1        60      94      96     109     109      77     109
h2o       T24      2        60     109     125     127     139      77     141
h2o       T40      1        60      92      94      95     108      75     110
h2o       T40      2        60      94     124     126     127      77     127
falcon    T16      1        60     187     190     202     203     154     204
falcon    T16      2        60     233     249     250     264     202     265
falcon    T24      1        60     201     219     220     221     159     221
falcon    T24      2        60     235     251     252     252     203     264
falcon    T40      1        60     188     204     204     206     155     220
falcon    T40      2        60     234     250     251     251     202     252
```

## generation_after_first_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    T16      1        60     189     204     205     206     186     207
lfm2.5    T16      2        60     205     222     234     235     187     236
lfm2.5    T24      1        60     189     204     204     206     186     207
lfm2.5    T24      2        60     190     204     205     207     186     219
lfm2.5    T40      1        60     189     204     205     206     185     206
lfm2.5    T40      2        60     203     218     219     221     185     222
h2o       T16      1        60     204     219     220     221     186     222
h2o       T16      2        60     220     250     254     268     187     269
h2o       T24      1        60     204     218     219     220     187     221
h2o       T24      2        60     204     235     251     251     186     252
h2o       T40      1        60     203     206     219     221     186     221
h2o       T40      2        60     205     222     235     238     186     239
falcon    T16      1        60     203     265     267     267     172     268
falcon    T16      2        60     236     266     268     269     187     269
falcon    T24      1        60     207     223     235     251     186     251
falcon    T24      2        60     204     234     235     237     185     237
falcon    T40      1        60     191     205     206     207     186     207
falcon    T40      2        60     190     205     205     207     186     208
```

## total_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    T16      1        60     282     285     294     297     265     297
lfm2.5    T16      2        60     313     331     343     344     266     391
lfm2.5    T24      1        60     282     297     298     301     265     302
lfm2.5    T24      2        60     298     315     327     331     266     332
lfm2.5    T40      1        60     282     297     298     299     262     299
lfm2.5    T40      2        60     297     314     315     328     266     329
h2o       T16      1        60     296     310     313     315     268     328
h2o       T16      2        60     329     373     374     378     270     393
h2o       T24      1        60     295     313     313     314     264     314
h2o       T24      2        60     316     359     360     375     266     375
h2o       T40      1        60     283     299     299     312     263     316
h2o       T40      2        60     301     344     348     362     279     364
falcon    T16      1        60     391     438     440     447     345     450
falcon    T16      2        60     469     488     500     502     394     503
falcon    T24      1        60     408     425     437     439     361     456
falcon    T24      2        60     438     473     483     485     403     486
falcon    T40      1        60     390     403     407     409     360     409
falcon    T40      2        60     424     441     454     455     391     456
```

## Serial correlation of TTFT

Are slow calls isolated spikes, or persistent regimes? The observed longest run of consecutive slow calls (above the cell's own p75) is compared with 200 shuffles of the same values.

`p` is the fraction of shuffles matching or beating the observed run. A low `p` means the slowness clusters more than chance allows.

```
MODEL     BUCKET   load      n   slow>ms      run  shuffled       p
lfm2.5    T16      1        60        93        4      2.32   0.040
lfm2.5    T16      2        60       109        1      2.22   1.000
lfm2.5    T24      1        60        94        2      1.74   0.650
lfm2.5    T24      2        60       110        1      2.23   1.000
lfm2.5    T40      1        60        94        3      2.29   0.320
lfm2.5    T40      2        60       108        2      2.46   0.955
h2o       T16      1        60        93        2      2.61   0.995
h2o       T16      2        60       124        1      2.59   1.000
h2o       T24      1        60        94        1      2.21   1.000
h2o       T24      2        60       125        1      1.47   1.000
h2o       T40      1        60        93        3      2.69   0.525
h2o       T40      2        60       123        1      1.99   1.000
falcon    T16      1        60       188        2      2.13   0.885
falcon    T16      2        60       235        4      2.72   0.145
falcon    T24      1        60       204        3      2.17   0.220
falcon    T24      2        60       249        1      2.61   1.000
falcon    T40      1        60       201        3      2.69   0.535
falcon    T40      2        60       246        1      2.54   1.000
```

**1 of 18 cells show clustering beyond chance (p < 0.05).**

## Exclusions

Excluded records are kept in the raw dataset with a reason. They are runtime evidence, not healthy reference samples.

```
none
```

## Bands are NOT derived here

This document freezes distributions only. The per-model `SUSPECT` band is chosen after inspecting these numbers, not before — and the global `HARD_DEGRADED` tooth (TTFT > 1500 ms) stays as it is, because the external benchmark showed a wide gap between healthy hundreds-of-milliseconds behaviour and pathological multi-second TTFT.
