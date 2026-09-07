# Bridge-Native Timing — Healthy Envelope

**Regime:** bridge v1, `EXPLICIT_RESIDENCY_MODE`, context 8192, Q4_K_M, `max_active = 2`.
Hot set frozen for the whole run; no swapping, no policy tuning, no band changes mid-run.

**Instrument:** `tools/bridge_collect.gd`. Timings come from the bridge's own streaming path, so `ttft_ms` is real first-content latency.

No combined score. A single number would average away the structure the bands need.

> **Read `CENSORED` cells carefully.** The healthy-baseline filter excludes TTFT > 1500 ms, which is the current global `HARD_DEGRADED` tooth. In cells where healthy large-prompt prefill approaches that value, the filter removes the upper tail of the very distribution the bands are meant to be derived from. Those cells' `p95`/`p99` are **lower bounds, not estimates**.

```
healthy reference samples  48
excluded from baseline     0
```

## queue_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    ASYNC    1         2       0       0       0       0       0       0
lfm2.5    ASYNC    2         2       0       0       0       0       0       0
lfm2.5    SMALL    1         2       1       1       1       1       0       1
lfm2.5    SMALL    2         2       1       1       1       1       0       1
lfm2.5    MEDIUM   1         2       1       1       1       1       0       1
lfm2.5    MEDIUM   2         2       1       1       1       1       0       1
lfm2.5    LARGE    1         2       1       1       1       1       0       1
lfm2.5    LARGE    2         2       0       0       0       0       0       0
qwen3.5   ASYNC    1         2       0       0       0       0       0       0
qwen3.5   ASYNC    2         2       0       0       0       0       0       0
qwen3.5   SMALL    1         2       0       0       0       0       0       0
qwen3.5   SMALL    2         2       0       0       0       0       0       0
qwen3.5   MEDIUM   1         2       0       0       0       0       0       0
qwen3.5   MEDIUM   2         2       1       1       1       1       0       1
qwen3.5   LARGE    1         2       0       0       0       0       0       0
qwen3.5   LARGE    2         2       0       0       0       0       0       0
falcon    ASYNC    1         2       0       0       0       0       0       0
falcon    ASYNC    2         2       0       0       0       0       0       0
falcon    SMALL    1         2       0       0       0       0       0       0
falcon    SMALL    2         2       0       0       0       0       0       0
falcon    MEDIUM   1         2       1       1       1       1       0       1
falcon    MEDIUM   2         2       0       0       0       0       0       0
falcon    LARGE    1         2       0       0       0       0       0       0
falcon    LARGE    2         2       0       0       0       0       0       0
```

## connect_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    ASYNC    1         2       1       1       1       1       0       1
lfm2.5    ASYNC    2         2       1       1       1       1       1       1
lfm2.5    SMALL    1         2       1       1       1       1       0       1
lfm2.5    SMALL    2         2       0       0       0       0       0       0
lfm2.5    MEDIUM   1         2       1       1       1       1       0       1
lfm2.5    MEDIUM   2         2       1       1       1       1       0       1
lfm2.5    LARGE    1         2       1       1       1       1       1       1
lfm2.5    LARGE    2         2       0       0       0       0       0       0
qwen3.5   ASYNC    1         2       1       1       1       1       1       1
qwen3.5   ASYNC    2         2       0       0       0       0       0       0
qwen3.5   SMALL    1         2       1       1       1       1       0       1
qwen3.5   SMALL    2         2       0       0       0       0       0       0
qwen3.5   MEDIUM   1         2       1       1       1       1       1       1
qwen3.5   MEDIUM   2         2       1       1       1       1       0       1
qwen3.5   LARGE    1         2       1       1       1       1       1       1
qwen3.5   LARGE    2         2       1       1       1       1       1       1
falcon    ASYNC    1         2       1       1       1       1       0       1
falcon    ASYNC    2         2       1       1       1       1       1       1
falcon    SMALL    1         2       1       1       1       1       1       1
falcon    SMALL    2         2       0       0       0       0       0       0
falcon    MEDIUM   1         2       1       1       1       1       0       1
falcon    MEDIUM   2         2       0       0       0       0       0       0
falcon    LARGE    1         2       2       2       2       2       0       2
falcon    LARGE    2         2       1       1       1       1       0       1
```

## ttft_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    ASYNC    1         2     125     125     125     125      88     125
lfm2.5    ASYNC    2         2     122     122     122     122     107     122
lfm2.5    SMALL    1         2      88      88      88      88      83      88
lfm2.5    SMALL    2         2      83      83      83      83      68      83
lfm2.5    MEDIUM   1         2     120     120     120     120      99     120
lfm2.5    MEDIUM   2         2     154     154     154     154     125     154
lfm2.5    LARGE    1         2     409     409     409     409     374     409
lfm2.5    LARGE    2         2     667     667     667     667     616     667
qwen3.5   ASYNC    1         2     244     244     244     244     171     244
qwen3.5   ASYNC    2         2     235     235     235     235     212     235
qwen3.5   SMALL    1         2     137     137     137     137     121     137
qwen3.5   SMALL    2         2     195     195     195     195     157     195
qwen3.5   MEDIUM   1         2     230     230     230     230     210     230
qwen3.5   MEDIUM   2         2     310     310     310     310     283     310
qwen3.5   LARGE    1         2     815     815     815     815     776     815
qwen3.5   LARGE    2         2    1548    1548    1548    1548    1159    1548
falcon    ASYNC    1         2     451     451     451     451     274     451
falcon    ASYNC    2         2     444     444     444     444     272     444
falcon    SMALL    1         2     227     227     227     227     171     227
falcon    SMALL    2         2     286     286     286     286     215     286
falcon    MEDIUM   1         2     406     406     406     406     294     406
falcon    MEDIUM   2         2     462     462     462     462     370     462
falcon    LARGE    1         2    1277    1277    1277    1277    1165    1277
falcon    LARGE    2         2    1909    1909    1909    1909    1488    1909
```

## generation_after_first_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    ASYNC    1         2      56      56      56      56      51      56
lfm2.5    ASYNC    2         2      50      50      50      50      42      50
lfm2.5    SMALL    1         2     220     220     220     220     194     220
lfm2.5    SMALL    2         2     341     341     341     341     246     341
lfm2.5    MEDIUM   1         2     228     228     228     228     188     228
lfm2.5    MEDIUM   2         2     253     253     253     253     233     253
lfm2.5    LARGE    1         2     371     371     371     371     304     371
lfm2.5    LARGE    2         2     411     411     411     411     317     411
qwen3.5   ASYNC    1         2      64      64      64      64      58      64
qwen3.5   ASYNC    2         2      60      60      60      60      57      60
qwen3.5   SMALL    1         2     506     506     506     506     456     506
qwen3.5   SMALL    2         2     687     687     687     687     525     687
qwen3.5   MEDIUM   1         2     550     550     550     550     534     550
qwen3.5   MEDIUM   2         2     742     742     742     742     554     742
qwen3.5   LARGE    1         2     563     563     563     563     542     563
qwen3.5   LARGE    2         2     766     766     766     766     567     766
falcon    ASYNC    1         2      65      65      65      65      57      65
falcon    ASYNC    2         2      63      63      63      63      61      63
falcon    SMALL    1         2     496     496     496     496     460     496
falcon    SMALL    2         2     567     567     567     567     490     567
falcon    MEDIUM   1         2     524     524     524     524     506     524
falcon    MEDIUM   2         2     668     668     668     668     502     668
falcon    LARGE    1         2     497     497     497     497     492     497
falcon    LARGE    2         2     618     618     618     618     481     618
```

## total_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    ASYNC    1         2     176     176     176     176     144     176
lfm2.5    ASYNC    2         2     172     172     172     172     149     172
lfm2.5    SMALL    1         2     308     308     308     308     277     308
lfm2.5    SMALL    2         2     409     409     409     409     329     409
lfm2.5    MEDIUM   1         2     327     327     327     327     308     327
lfm2.5    MEDIUM   2         2     407     407     407     407     358     407
lfm2.5    LARGE    1         2     745     745     745     745     713     745
lfm2.5    LARGE    2         2    1078    1078    1078    1078     933    1078
qwen3.5   ASYNC    1         2     308     308     308     308     229     308
qwen3.5   ASYNC    2         2     292     292     292     292     272     292
qwen3.5   SMALL    1         2     643     643     643     643     577     643
qwen3.5   SMALL    2         2     844     844     844     844     720     844
qwen3.5   MEDIUM   1         2     780     780     780     780     744     780
qwen3.5   MEDIUM   2         2    1025    1025    1025    1025     864    1025
qwen3.5   LARGE    1         2    1378    1378    1378    1378    1318    1378
qwen3.5   LARGE    2         2    2314    2314    2314    2314    1726    2314
falcon    ASYNC    1         2     508     508     508     508     339     508
falcon    ASYNC    2         2     507     507     507     507     333     507
falcon    SMALL    1         2     687     687     687     687     667     687
falcon    SMALL    2         2     782     782     782     782     776     782
falcon    MEDIUM   1         2     912     912     912     912     818     912
falcon    MEDIUM   2         2    1130    1130    1130    1130     872    1130
falcon    LARGE    1         2    1774    1774    1774    1774    1657    1774
falcon    LARGE    2         2    2527    2527    2527    2527    1969    2527
```

## Serial correlation of TTFT

Are slow calls isolated spikes, or persistent regimes? The observed longest run of consecutive slow calls (above the cell's own p75) is compared with 200 shuffles of the same values.

`p` is the fraction of shuffles matching or beating the observed run. A low `p` means the slowness clusters more than chance allows.

```
MODEL     BUCKET   load      n   slow>ms      run  shuffled       p
```

**0 of 0 cells show clustering beyond chance (p < 0.05).**

## Exclusions

Excluded records are kept in the raw dataset with a reason. They are runtime evidence, not healthy reference samples.

```
none
```

## Bands are NOT derived here

This document freezes distributions only. The per-model `SUSPECT` band is chosen after inspecting these numbers, not before — and the global `HARD_DEGRADED` tooth (TTFT > 1500 ms) stays as it is, because the external benchmark showed a wide gap between healthy hundreds-of-milliseconds behaviour and pathological multi-second TTFT.
