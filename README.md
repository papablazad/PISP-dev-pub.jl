# PISP.jl: Julia parser for the Integrated System Plan

[![Build Status](https://github.com/papablazad/PISP.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/papablazad/PISP.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/papablazad/PISP.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/papablazad/PISP.jl)


## Core function
```julia
using PISP

# Set some parameters (see all parameters below)
reference_trace = 4006 
poe = 10 # Probability of exceedance (POE) for demand
target_years = [2030, 2031]

PISP.build_ISP24_datasets(
    downloadpath = joinpath(@__DIR__, "..", "data", "pisp-downloads"),
    poe          = poe,
    reftrace     = reference_trace,
    years        = target_years,
    output_root  = joinpath(@__DIR__, "..", "data", "pisp-datasets"),
    write_csv    = true,
    write_arrow  = false)

```

## Optional parameters for PISP.build_ISP24_datasets()
There are multiple parameters that can be adjusted when generating the dataset from the public ISP24 datafiles:
| Parameter           | Default       | Description                                                                                                                        |
| ------------------- | ------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
|downloadpath|"../../data-download"| Path where all files from AEMO's website will be downloaded and extracted
|download_from_AEMO|true| Whether to download files from AEMO's website
|poe|10| Probability of exceedance (POE) for demand: 10% or 50%
|reftrace|2011| Reference weather year trace: select among 2011 - 2023 or 4006 (trace for the ODP)
|years|[2025]| Calendar years for which to build the time-varying schedules: select among 2025 - 2050
|output_name|"out"| Output folder name
|output_root|nothing| Output folder root
|write_csv|true| Whether to write CSV files
|write_arrow|true|Whether to write Arrow files 
|scenarios|[1,2,3]|Scenarios to include in the output: 1 for "Progressive Change", 2 for "Step Change", 3 for "Green Energy Exports"
