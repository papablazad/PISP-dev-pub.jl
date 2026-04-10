using PISP

downloadpath = normpath("/Volumes/Seagate/CSIRO AR-PST Stage 5/PISP-downloads") # Path where all files from AEMO's website will be downloaded and extracted
download_from_AEMO = true            # Whether to download files from AEMO's website
poe          = 10                    # Probability of exceedance (POE) for demand: 10% or 50%
reftrace     = 4006                  # Reference weather year trace: select among 2011 - 2023 or 4006 (trace for the ODP)
years        = [2025]          # Calendar years for which to build the time-varying schedules: select among 2025 - 2050
output_name  = "out-inflows"                 # Output folder name   
output_root  = normpath("/Volumes/Seagate/CSIRO AR-PST Stage 5/PISP-outputs")   # Root output path where the output folder will be created
write_csv    = true                  # Whether to write CSV files
write_arrow  = false                 # Whether to write Arrow files
scenarios    = [1,2,3]                # Scenarios to include in the output: 1 for "Progressive Change", 2 for "Step Change", 3 for "Green Energy Exports"

if any(y -> y < 2025 || y > 2050, years)
    throw(ArgumentError("Years must be between 2025 and 2050 (got $(years))."))
end

data_paths = PISP.default_data_paths(filepath=downloadpath)

# Download/extract/build inputs once
# PISP.build_pipeline(data_root = downloadpath, poe = poe, download_files = download_from_AEMO, overwrite_extracts = false)

base_name = "$(output_name)-ref$(reftrace)-poe$(poe)"

# for year in years
year = years[1]
tc, ts, tv = PISP.initialise_time_structures()
PISP.fill_problem_table_year(tc, year, sce=scenarios)
static_params = PISP.populate_time_static!(ts, tv, data_paths; refyear = reftrace, poe = poe)
@info "Populating time-varying data from ISP 2024 - POE $(poe) - reference weather trace $(reftrace) - planning year $(year) ..."
PISP.populate_time_varying!(tc, ts, tv, data_paths, static_params; refyear = reftrace, poe = poe)

PISP.write_time_data(ts, tv;
    csv_static_path    = "$(base_name)/csv",
    csv_varying_path   = "$(base_name)/csv/schedule-$(year)",
    arrow_static_path  = "$(base_name)/arrow",
    arrow_varying_path = "$(base_name)/arrow/schedule-$(year)",
    write_static       = true,
    write_varying      = true,
    output_root        = output_root,
    write_csv          = write_csv,
    write_arrow        = write_arrow,
)
# end