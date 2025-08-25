# Compare

## CPU

```bash
bundle exec ruby -r stackprof -e "StackProf.run(mode: :cpu, out: 'tmp/stackprof.dump'){ load 'benchmark/performance_optimized.rb' }"
```

### v2.1.0

```bash
Benchmarking route matching (optimized):
==================================================
                           user     system      total        real
Route matching:        0.078937   0.002323   0.081260 (  0.093271)

Benchmarking path generation (optimized):
==================================================
                           user     system      total        real
Path generation:       0.111863   0.002066   0.113929 (  0.122507)

Memory usage analysis:
==================================================
Memory before: 200 KB
Memory after: 200 KB
Memory increase: 0 KB

Cache performance:
==================================================
Cache hits: 121000
Cache misses: 11
Hit rate: 99.99%
Cache size: 11
```

### Current

```bash
Benchmarking route matching (optimized):
==================================================
Object counts before route matching:
  Current object counts:
    TOTAL: 77548
    T_STRING: 30680
    T_IMEMO: 20939
    T_ARRAY: 8046
    T_OBJECT: 4106
    T_HASH: 3563
    T_DATA: 3089
    FREE: 2810
    T_SYMBOL: 2451
    T_CLASS: 1136
                           user     system      total        real
Route matching:        0.137532   0.004863   0.142395 (  0.306211)

Object counts after route matching:
  Object count differences:
    FREE: -200
    T_STRING: +104
    T_IMEMO: +53
    T_ARRAY: +30
    T_MATCH: +8
    T_OBJECT: +2
    T_STRUCT: +2
    T_HASH: +1
    T_ICLASS: 0
    T_SYMBOL: 0

Benchmarking path generation (optimized):
==================================================
Object counts before path generation:
  Current object counts:
    TOTAL: 77548
    T_STRING: 30827
    T_IMEMO: 20995
    T_ARRAY: 8099
    T_OBJECT: 4108
    T_HASH: 3566
    T_DATA: 3089
    FREE: 2539
    T_SYMBOL: 2451
    T_CLASS: 1136
                           user     system      total        real
Path generation:       0.094619   0.004632   0.099251 (  0.139878)

Object counts after path generation:
  Object count differences:
    FREE: +8872
    TOTAL: +6545
    T_ARRAY: -3026
    T_STRING: +1248
    T_IMEMO: -958
    T_HASH: +587
    T_DATA: -128
    T_MATCH: -45
    T_OBJECT: -5
    T_FLOAT: 0

Memory usage analysis:
==================================================
Object counts before memory test:
  Current object counts:
    TOTAL: 84093
    T_STRING: 32123
    T_IMEMO: 20039
    FREE: 11336
    T_ARRAY: 5096
    T_HASH: 4155
    T_OBJECT: 4103
    T_DATA: 2961
    T_SYMBOL: 2451
    T_CLASS: 1136
Memory before: 164 KB
Memory after: 164 KB
Memory increase: 0 KB

Object counts after memory test:
  Object count differences:
    FREE: +9124
    T_STRING: -7628
    T_HASH: -1460
    T_ARRAY: -28
    T_IMEMO: +4
    T_OBJECT: -2
    T_STRUCT: -2
    T_ICLASS: 0
    T_SYMBOL: 0
    T_COMPLEX: 0

Cache performance:
==================================================
Cache hits: 121000
Cache misses: 11
Hit rate: 99.99090991728025
Cache size: 11
```

## Object

```bash
bundle exec ruby -r stackprof -e "StackProf.run(mode: :object, out: 'tmp/stackprof.object.dump') { load 'benchmark/performance_optimized.rb' }"
bundle exec stackprof tmp/stackprof.object.dump --text | head -n 60
```

### v2.1.0

```bash
Benchmarking route matching (optimized):
==================================================
                           user     system      total        real
Route matching:        0.291850   0.006697   0.298547 (  0.345572)

Benchmarking path generation (optimized):
==================================================
                           user     system      total        real
Path generation:       0.720427   0.013306   0.733733 (  0.813689)

Memory usage analysis:
==================================================
Memory before: 200 KB
Memory after: 200 KB
Memory increase: 0 KB

Cache performance:
==================================================
Cache hits: 121000
Cache misses: 11
Hit rate: 99.99%
Cache size: 11

Performance test completed!
==================================
  Mode: object(1)
  Samples: 433607 (0.00% miss rate)
  GC: 0 (0.00%)
==================================
     TOTAL    (pct)     SAMPLES    (pct)     FRAME
    121011  (27.9%)      121011  (27.9%)     RubyRoutes::RouteSet#build_cache_key
     42145   (9.7%)       42142   (9.7%)     Kernel#dup
     42003   (9.7%)       42001   (9.7%)     Enumerable#select
    270047  (62.3%)       40002   (9.2%)     block (3 levels) in <top (required)>
     21783   (5.0%)       21300   (4.9%)     Array#map
     21260   (4.9%)       21258   (4.9%)     Enumerable#each_entry
     42129   (9.7%)       21129   (4.9%)     Hash#transform_keys
     21062   (4.9%)       21059   (4.9%)     Array#join
     63001  (14.5%)       21001   (4.8%)     RubyRoutes::Route#build_cache_key_fast
     21000   (4.8%)       21000   (4.8%)     Hash#keys
     21000   (4.8%)       21000   (4.8%)     Symbol#to_s
    242045  (55.8%)       11001   (2.5%)     RubyRoutes::RouteSet#generate_path
     15124   (3.5%)        4345   (1.0%)     Kernel.require
      3604   (0.8%)        3604   (0.8%)     String#%
     12879   (3.0%)        3349   (0.8%)     Kernel#require_relative
      2566   (0.6%)        2566   (0.6%)     String#split
     25000   (5.8%)        2000   (0.5%)     block in <top (required)>
     11023   (2.5%)        1418   (0.3%)     Class#new
      1280   (0.3%)        1280   (0.3%)     Integer#chr
      5124   (1.2%)        1028   (0.2%)     block in <module:URI>
      1349   (0.3%)         687   (0.2%)     RubyRoutes::RadixTree#split_path_raw
      9922   (2.3%)         415   (0.1%)     RubyRoutes::Router#resources
       409   (0.1%)         409   (0.1%)     String#upcase
      1105   (0.3%)         400   (0.1%)     RubyRoutes::Router#apply_scope
      6021   (1.4%)         395   (0.1%)     RubyRoutes::Route#initialize
       329   (0.1%)         329   (0.1%)     String#[]
       271   (0.1%)         271   (0.1%)     block in <module:Constant>
       262   (0.1%)         262   (0.1%)     RubyRoutes::Route::SmallLru#initialize
    433604 (100.0%)         262   (0.1%)     Kernel#load
       456   (0.1%)         260   (0.1%)     RubyRoutes::Route#normalize_path
```

### Current

```bash
Benchmarking route matching (optimized):
==================================================
Object counts before route matching:
  Current object counts:
    TOTAL: 77551
    T_STRING: 30699
    T_IMEMO: 20960
    T_ARRAY: 8046
    T_OBJECT: 4106
    T_HASH: 3563
    T_DATA: 3090
    FREE: 2767
    T_SYMBOL: 2451
    T_CLASS: 1136
                           user     system      total        real
Route matching:        0.102703   0.001473   0.104176 (  0.112378)

Object counts after route matching:
  Object count differences:
    FREE: -200
    T_STRING: +104
    T_IMEMO: +53
    T_ARRAY: +30
    T_MATCH: +8
    T_OBJECT: +2
    T_STRUCT: +2
    T_HASH: +1
    T_ICLASS: 0
    T_SYMBOL: 0

Benchmarking path generation (optimized):
==================================================
Object counts before path generation:
  Current object counts:
    TOTAL: 77551
    T_STRING: 30846
    T_IMEMO: 21016
    T_ARRAY: 8099
    T_OBJECT: 4108
    T_HASH: 3566
    T_DATA: 3090
    FREE: 2496
    T_SYMBOL: 2451
    T_CLASS: 1136
                           user     system      total        real
Path generation:       0.194222   0.002837   0.197059 (  0.211379)

Object counts after path generation:
  Object count differences:
    FREE: +7772
    TOTAL: +6545
    T_ARRAY: -3025
    T_STRING: +1921
    T_HASH: +888
    T_IMEMO: -833
    T_DATA: -128
    T_MATCH: -45
    T_OBJECT: -5
    T_FLOAT: 0

Memory usage analysis:
==================================================
Object counts before memory test:
  Current object counts:
    TOTAL: 84096
    T_STRING: 32815
    T_IMEMO: 20185
    FREE: 10193
    T_ARRAY: 5097
    T_HASH: 4456
    T_OBJECT: 4103
    T_DATA: 2962
    T_SYMBOL: 2451
    T_CLASS: 1136
Memory before: 164 KB
Memory after: 164 KB
Memory increase: 0 KB

Object counts after memory test:
  Object count differences:
    FREE: +10041
    T_STRING: -8244
    T_HASH: -1761
    T_ARRAY: -28
    T_IMEMO: +4
    T_OBJECT: -2
    T_STRUCT: -2
    T_ICLASS: 0
    T_SYMBOL: 0
    T_COMPLEX: 0

Cache performance:
==================================================
Cache hits: 121000
Cache misses: 11
Hit rate: 99.99090991728025
Cache size: 11

Performance test completed!
==================================
  Mode: object(1)
  Samples: 122330 (0.00% miss rate)
  GC: 0 (0.00%)
==================================
     TOTAL    (pct)     SAMPLES    (pct)     FRAME
     90053  (73.6%)       40002  (32.7%)     block (3 levels) in <top (required)>
     21006  (17.2%)       21006  (17.2%)     RubyRoutes::Route#build_merged_params
     21002  (17.2%)       21002  (17.2%)     String#dup
     53051  (43.4%)       11002   (9.0%)     RubyRoutes::RouteSet#generate_path
     13261  (10.8%)        3634   (3.0%)     Kernel#require_relative
      3604   (2.9%)        3604   (2.9%)     String#%
      2880   (2.4%)        2880   (2.4%)     String#split
      5000   (4.1%)        2000   (1.6%)     block in <top (required)>
     11306   (9.2%)        1745   (1.4%)     Kernel.require
      1280   (1.0%)        1280   (1.0%)     Integer#chr
      6854   (5.6%)        1170   (1.0%)     RubyRoutes::Route#initialize
     12674  (10.4%)        1169   (1.0%)     Class#new
      5124   (4.2%)        1028   (0.8%)     block in <module:URI>
      2674   (2.2%)         650   (0.5%)     RubyRoutes::RadixTree#insert_route
      1559   (1.3%)         552   (0.5%)     RubyRoutes::Utility::PathUtility#split_path
      1037   (0.8%)         429   (0.4%)     Array#map
     11486   (9.4%)         415   (0.3%)     RubyRoutes::Router#resources
      1105   (0.9%)         400   (0.3%)     RubyRoutes::Router#apply_scope
       391   (0.3%)         391   (0.3%)     RubyRoutes::Route::SmallLru#initialize
    122327 (100.0%)         333   (0.3%)     Kernel#load
       330   (0.3%)         330   (0.3%)     String#[]
       278   (0.2%)         278   (0.2%)     String#upcase
       271   (0.2%)         271   (0.2%)     block in <module:Constant>
       782   (0.6%)         260   (0.2%)     Set#initialize
       258   (0.2%)         258   (0.2%)     Enumerable#filter_map
       259   (0.2%)         258   (0.2%)     Enumerable#each_entry
       258   (0.2%)         258   (0.2%)     Array#reject
       257   (0.2%)         257   (0.2%)     RubyRoutes::Utility::PathUtility#normalize_path
       257   (0.2%)         257   (0.2%)     RubyRoutes::Utility::PathUtility#normalize_path
       249   (0.2%)         249   (0.2%)     Hash#merge
```