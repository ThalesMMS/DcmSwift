# Window/Level Benchmark

Benchmark comparing naive per-pixel loops against Accelerate vDSP implementations on 1,048,576 random 16-bit pixels.

| Operation | Naive | vDSP |
|-----------|-------|------|
| Window/Level | 31.760 ms | 28.746 ms |
| LUT Mapping | 17.334 ms | 15.827 ms |

Times collected by running `swift References/WindowLevelBenchmark.swift`.
