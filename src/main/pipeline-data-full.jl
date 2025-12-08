using PISP
    PISP.build_full_pipeline( downloadpath = normpath(@__DIR__, "../../", "data-download-v2"), # Path where all files from AEMO's website will be downloaded and extracted
                            poe          = 10,                    # Probability of exceedance (POE) for demand: 10% or 50%
                            reftrace     = 2022,                  # Reference weather year trace: select among 2011 - 2023 or 4006 (trace for the ODP)
                            years        = [2025, 2026, 2027],    # Years for which to build the time-varying schedules: select among 2025 - 2050
                            output_name  = "out",                 # Output folder name   
                            output_root  = @__DIR__)