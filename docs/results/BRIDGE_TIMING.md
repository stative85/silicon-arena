# Bridge-Native Timing — Healthy Envelope

**Regime:** bridge v1, `EXPLICIT_RESIDENCY_MODE`, context 8192, Q4_K_M, `max_active = 2`.
Hot set frozen for the whole run; no swapping, no policy tuning, no band changes mid-run.

**Instrument:** `tools/bridge_collect.gd`. Timings come from the bridge's own streaming path, so `ttft_ms` is real first-content latency.

No combined score. A single number would average away the structure the bands need.

> **Policy thresholds get NO vote in this fit.** The frozen `ks = 1.8 / kh = 20 / n = 3` rule is not used to filter these samples: a policy cannot help select the surface it will later be applied to. Only transport failures and runtime events exclude a call here. Pathological stalls are identified afterwards, relative to each cell's own distribution, and reported separately.

```
healthy reference samples  1440
excluded from baseline     0
```

## queue_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    ASYNC    1        60       0       0       0       1       0       1
lfm2.5    ASYNC    2        60       0       0       0       1       0       1
lfm2.5    SMALL    1        60       0       0       0       1       0       1
lfm2.5    SMALL    2        60       0       0       0       1       0       1
lfm2.5    MEDIUM   1        60       0       0       0       1       0       1
lfm2.5    MEDIUM   2        60       0       0       0       0       0       1
lfm2.5    LARGE    1        60       0       0       1       1       0       1
lfm2.5    LARGE    2        60       0       0       0       1       0       1
qwen3.5   ASYNC    1        60       0       0       0       1       0       1
qwen3.5   ASYNC    2        60       0       0       1       1       0       1
qwen3.5   SMALL    1        60       0       0       1       1       0       1
qwen3.5   SMALL    2        60       0       0       0       0       0       1
qwen3.5   MEDIUM   1        60       0       0       0       1       0       1
qwen3.5   MEDIUM   2        60       0       0       0       0       0       0
qwen3.5   LARGE    1        60       0       0       1       1       0       1
qwen3.5   LARGE    2        60       0       0       1       1       0       1
falcon    ASYNC    1        60       0       0       0       0       0       0
falcon    ASYNC    2        60       0       0       0       0       0       1
falcon    SMALL    1        60       0       0       0       0       0       1
falcon    SMALL    2        60       0       0       1       1       0       1
falcon    MEDIUM   1        60       0       0       0       1       0       1
falcon    MEDIUM   2        60       0       0       0       1       0       1
falcon    LARGE    1        60       0       0       1       1       0       1
falcon    LARGE    2        60       0       0       0       1       0       1
```

## connect_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    ASYNC    1        60       1       1       1       1       0       1
lfm2.5    ASYNC    2        60       1       1       1       1       0       1
lfm2.5    SMALL    1        60       0       1       1       1       0       2
lfm2.5    SMALL    2        60       1       1       1       1       0       1
lfm2.5    MEDIUM   1        60       1       1       1       1       0       2
lfm2.5    MEDIUM   2        60       1       1       1       1       0       1
lfm2.5    LARGE    1        60       1       1       1       1       0       2
lfm2.5    LARGE    2        60       1       1       1       1       0       2
qwen3.5   ASYNC    1        60       1       1       1       1       0       1
qwen3.5   ASYNC    2        60       0       1       1       1       0       1
qwen3.5   SMALL    1        60       1       1       1       1       0       1
qwen3.5   SMALL    2        60       1       1       1       1       0       2
qwen3.5   MEDIUM   1        60       1       1       1       1       0       1
qwen3.5   MEDIUM   2        60       1       1       1       2       0       2
qwen3.5   LARGE    1        60       1       1       1       2       0       2
qwen3.5   LARGE    2        60       1       1       1       1       0       2
falcon    ASYNC    1        60       0       1       1       1       0       1
falcon    ASYNC    2        60       0       1       1       1       0       1
falcon    SMALL    1        60       1       1       1       1       0       1
falcon    SMALL    2        60       0       1       1       1       0       1
falcon    MEDIUM   1        60       1       1       1       1       0       2
falcon    MEDIUM   2        60       0       1       1       1       0       1
falcon    LARGE    1        60       1       1       1       1       0       2
falcon    LARGE    2        60       1       1       1       1       0       2
```

## ttft_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    ASYNC    1        60      83      92      97      99      72     117
lfm2.5    ASYNC    2        60     100     171     183     191      72     226
lfm2.5    SMALL    1        60      81      99     149     159      62     164
lfm2.5    SMALL    2        60      90     153     166     172      65     175
lfm2.5    MEDIUM   1        60     120     177     192     209     109     311
lfm2.5    MEDIUM   2        60     154     248     276     285     109     332
lfm2.5    LARGE    1        60     417     453     459     466     375     476
lfm2.5    LARGE    2        60     652     697     706     718     429     752
qwen3.5   ASYNC    1        60     185     196     202     219     148     235
qwen3.5   ASYNC    2        60     216     252     268     275     180     279
qwen3.5   SMALL    1        60     134     149     158     159     104     182
qwen3.5   SMALL    2        60     159     191     199     217     121     219
qwen3.5   MEDIUM   1        60     257     278     285     300     227     313
qwen3.5   MEDIUM   2        60     328     356     367     389     235     411
qwen3.5   LARGE    1        60     887     923     925     932     861     944
qwen3.5   LARGE    2        60    1577    1713    1749    1779    1241    1810
falcon    ASYNC    1        60     272     328     339     374     229     432
falcon    ASYNC    2        60     288     316     346     392     218     430
falcon    SMALL    1        60     191     231     267     296     170     369
falcon    SMALL    2        60     250     295     303     309     201     370
falcon    MEDIUM   1        60     413     439     443     468     307     711
falcon    MEDIUM   2        60     485     571     617     630     386     652
falcon    LARGE    1        60    1315    1367    1373    1401    1253    1501
falcon    LARGE    2        60    2058    2169    2184    2201    1547    2255
```

## generation_after_first_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    ASYNC    1        60      48      51      54      59      44      60
lfm2.5    ASYNC    2        60      47      50      53      59      44      62
lfm2.5    SMALL    1        60     217     335     345     400     167     450
lfm2.5    SMALL    2        60     197     291     318     345     143     370
lfm2.5    MEDIUM   1        60     228     265     273     282     184     305
lfm2.5    MEDIUM   2        60     222     254     261     279     191     318
lfm2.5    LARGE    1        60     329     372     387     399     285     422
lfm2.5    LARGE    2        60     389     429     435     442     308     494
qwen3.5   ASYNC    1        60      72      78      79      79      56      80
qwen3.5   ASYNC    2        60      68      74      74      75      62      77
qwen3.5   SMALL    1        60     484     534     550     557     280     611
qwen3.5   SMALL    2        60     536     695     728     760     374     761
qwen3.5   MEDIUM   1        60     542     571     580     592     457     634
qwen3.5   MEDIUM   2        60     661     747     756     768     509     813
qwen3.5   LARGE    1        60     542     574     580     584     421     600
qwen3.5   LARGE    2        60     590     792     795     820     440     820
falcon    ASYNC    1        60      73      80      81      82      64      82
falcon    ASYNC    2        60      71      74      74      75      62      76
falcon    SMALL    1        60     517     536     541     563     410     609
falcon    SMALL    2        60     498     573     581     630     372     652
falcon    MEDIUM   1        60     489     514     529     537     342     544
falcon    MEDIUM   2        60     525     628     646     659     424     695
falcon    LARGE    1        60     505     525     531     535     431     543
falcon    LARGE    2        60     534     601     623     639     466     645
```

## total_ms

```
MODEL     BUCKET   load      n  median     p90     p95     p99     min     max
lfm2.5    ASYNC    1        60     132     138     147     148     118     162
lfm2.5    ASYNC    2        60     147     218     228     235     118     272
lfm2.5    SMALL    1        60     310     415     469     487     249     528
lfm2.5    SMALL    2        60     291     399     423     435     246     484
lfm2.5    MEDIUM   1        60     356     408     438     459     301     555
lfm2.5    MEDIUM   2        60     382     489     501     504     306     536
lfm2.5    LARGE    1        60     748     802     810     827     680     833
lfm2.5    LARGE    2        60    1007    1101    1132    1170     803    1194
qwen3.5   ASYNC    1        60     255     271     280     296     218     309
qwen3.5   ASYNC    2        60     286     326     338     343     242     343
qwen3.5   SMALL    1        60     619     669     679     688     409     745
qwen3.5   SMALL    2        60     709     841     892     908     547     927
qwen3.5   MEDIUM   1        60     801     836     843     874     730     880
qwen3.5   MEDIUM   2        60     957    1073    1091    1119     837    1167
qwen3.5   LARGE    1        60    1430    1464    1484    1516    1290    1532
qwen3.5   LARGE    2        60    2249    2485    2520    2577    1730    2605
falcon    ASYNC    1        60     348     402     413     440     299     511
falcon    ASYNC    2        60     358     387     410     465     283     495
falcon    SMALL    1        60     715     756     764     827     589     828
falcon    SMALL    2        60     755     842     874     898     579     931
falcon    MEDIUM   1        60     895     926     927     955     649    1220
falcon    MEDIUM   2        60    1009    1184    1191    1217     833    1230
falcon    LARGE    1        60    1814    1879    1893    1914    1735    2014
falcon    LARGE    2        60    2648    2756    2759    2772    2053    2792
```

## Serial correlation of TTFT

Are slow calls isolated spikes, or persistent regimes? The observed longest run of consecutive slow calls (above the cell's own p75) is compared with 200 shuffles of the same values.

`p` is the fraction of shuffles matching or beating the observed run. A low `p` means the slowness clusters more than chance allows.

```
MODEL     BUCKET   load      n   slow>ms      run  shuffled       p
lfm2.5    ASYNC    1        60        86        3      2.34   0.345
lfm2.5    ASYNC    2        60       145        3      2.63   0.530
lfm2.5    SMALL    1        60        92        2      2.63   0.980
lfm2.5    SMALL    2        60       104        2      2.62   0.980
lfm2.5    MEDIUM   1        60       137        3      2.73   0.545
lfm2.5    MEDIUM   2        60       176        3      2.58   0.440
lfm2.5    LARGE    1        60       428        6      2.32   0.000
lfm2.5    LARGE    2        60       682        1      2.46   1.000
qwen3.5   ASYNC    1        60       191        2      2.68   0.995
qwen3.5   ASYNC    2        60       235        3      2.59   0.475
qwen3.5   SMALL    1        60       140        2      2.46   0.980
qwen3.5   SMALL    2        60       176        3      2.67   0.475
qwen3.5   MEDIUM   1        60       268        3      2.65   0.500
qwen3.5   MEDIUM   2        60       341        2      2.64   0.995
qwen3.5   LARGE    1        60       900        5      2.71   0.040
qwen3.5   LARGE    2        60      1690        1      2.67   1.000
falcon    ASYNC    1        60       294        2      2.67   0.985
falcon    ASYNC    2        60       299        2      2.61   1.000
falcon    SMALL    1        60       209        3      2.69   0.550
falcon    SMALL    2        60       282        4      2.65   0.125
falcon    MEDIUM   1        60       426        4      2.70   0.155
falcon    MEDIUM   2        60       533        1      2.54   1.000
falcon    LARGE    1        60      1337        4      2.75   0.180
falcon    LARGE    2        60      2138        1      2.63   1.000
```

**2 of 24 cells show clustering beyond chance (p < 0.05).**

## Exclusions

Excluded records are kept in the raw dataset with a reason. They are runtime evidence, not healthy reference samples.

```
none
```

## Bands are NOT derived here

This document freezes distributions only. The per-model `SUSPECT` band is chosen after inspecting these numbers, not before — and the global `HARD_DEGRADED` tooth (TTFT > 1500 ms) stays as it is, because the external benchmark showed a wide gap between healthy hundreds-of-milliseconds behaviour and pathological multi-second TTFT.
