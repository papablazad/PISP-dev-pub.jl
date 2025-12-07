using PISP
using PISP.ISPTraceDownloader
using PISP.ISPFileDownloader
using PISP.PISPScrapperUtils
using XLSX
using DataFrames
using Dates
using Tables
using CSV
# ================================================ # 
# Download traces
# ================================================ # 

# ================================================ # 
# Download options
# ================================================ # 
# Download options for traces 
throttle_env   = get(ENV, "ISP_DOWNLOAD_THROTTLE", "")
traces_options = FileDownloadOptions(outdir            = normpath(@__DIR__, "..", "..", "data-download-v2/zip", "Traces"),
                        confirm_overwrite = true,
                        skip_existing     = false,
                        throttle_seconds  = isempty(throttle_env) ? nothing : parse(Float64, throttle_env));
# Download options for excel files
files_options = FileDownloadOptions(outdir = normpath(@__DIR__, "..", "..", "data-download-v2"),
                        confirm_overwrite = true,
                        skip_existing     = false);
# Download options for zip files
files_options_zip = FileDownloadOptions(outdir = normpath(@__DIR__, "..", "..", "data-download-v2/zip"),
                        confirm_overwrite = true,
                        skip_existing     = false);

# Download ISP files and collect paths
isp24_inputs_path       = download_isp24_inputs_workbook(options = files_options)
isp19_inputs_path       = download_isp19_inputs_workbook(options = files_options)
isp24_model_path        = download_isp24_model_archive(options   = files_options_zip)
isp24_outlook_path      = download_isp24_outlook(options         = files_options_zip)
# Download ISP traces
downloaded_traces       = download_isp24_traces(options = traces_options)

downloaded_files = [
    isp24_inputs_path,
    isp24_model_path,
    isp24_outlook_path,
    isp19_inputs_path,
]

@info("Downloaded $(length(downloaded_files)) ISP reference files to $(files_options.outdir)")
@info("Downloaded $(length(downloaded_traces)) ISP trace files to $(traces_options.outdir)")

# ================================================ # 
# Extract downloaded files
# ================================================ #
root            = normpath(@__DIR__, "..", "..", "data-download-v2"); # Folder of downloaded files
zip_root        = joinpath(root, "zip"); # Folder with zip files
trace_zip_root  = joinpath(zip_root, "Traces"); # Folder with trace zip files

# Location where files are going to be extracted
files_dest      = root;
traces_dest     = joinpath(root, "Traces");

@info "Extracting ISP files" src = zip_root dest = files_dest
file_dirs = extract_all_zips(zip_root, files_dest; overwrite = true, quiet = true)
@info "Finished extracting $(length(file_dirs)) ISP files" 

@info "Extracting trace files" src = trace_zip_root dest = traces_dest
trace_dirs = extract_all_zips(trace_zip_root, traces_dest; overwrite = true, quiet = true)
@info "Finished extracting $(length(trace_dirs)) trace files" 
# ================================================ # 
# Generate auxiliary files
# ================================================ #
# ================================================ #
# Generating CapacityOutlook_2024_ISP.xlsx
# ================================================ #
datapath               = normpath(@__DIR__, "..", "..", "data-download-v2")
outlook_core_path      = normpath(datapath, "Core")
outlook_auxiliary_path = normpath(datapath, "Auxiliary")
mkpath(outlook_auxiliary_path)
file_list       = readdir(outlook_core_path)
all_capacities  = DataFrame[]
for f in file_list
    if endswith(f, ".xlsx")
        file_path       = normpath(outlook_core_path, f)
        parts           = split(f, " - ")
        scenario_full   = length(parts) >= 2 ? strip(parts[2]) : ""
        capacity_df     = PISP.read_xlsx_with_header(file_path, "Capacity", "A3:AG5000")
        insertcols!(capacity_df, 2, :Scenario => fill(scenario_full, nrow(capacity_df)))
        capacity_df     = filter(row -> any(x -> x isa Number && !ismissing(x), row), capacity_df)
        push!(all_capacities, capacity_df)
    end
end
combined_capacity_df = isempty(all_capacities) ? DataFrame() : vcat(all_capacities...; cols = :union);
combined_xlsx_path   = normpath(outlook_auxiliary_path, "CapacityOutlook_2024_ISP.xlsx");
XLSX.writetable(combined_xlsx_path, Tables.columntable(combined_capacity_df); sheetname="CapacityOutlook_2024_ISP", overwrite=true);
# ================================================ #
# Generating the capacity for the CDP 14 scenario
# outlookAEMO = normpath(datapath, "CapacityOutlook/CapacityOutlook_2024_ISP_melted_CDP14.xlsx")
# ================================================ #
# Build melted CapacityOutlook_2024_ISP DataFrame and save CDP14 version
df_outlook = copy(combined_capacity_df)

# Rename yearly columns (e.g., "2025-26") to a July 1 date string (e.g., "2025-07-01")
col_names = names(df_outlook)
for col in col_names[6:end]
    col_str = String(col)
    if occursin("-", col_str)
        first_year = strip(split(col_str, '-')[1])
        new_date = Dates.Date(parse(Int, first_year), 7, 1)
        rename!(df_outlook, col => Symbol(Dates.format(new_date, DateFormat("yyyy-mm-dd"))))
    end
end

value_vars      = names(df_outlook)[6:end]
df_melted       = stack(df_outlook, value_vars; variable_name = :date, value_name = :value)
df_melted.date  = Dates.Date.(string.(df_melted.date), Dates.DateFormat("yyyy-mm-dd"))
sort!(df_melted, [:Scenario, :Subregion, :Technology, :date])
df_melted = filter(:CDP => ==("CDP14"), df_melted)
sort!(df_melted, [:Scenario, :Subregion, :Technology, :date])
mkpath(outlook_auxiliary_path)
output_melted_path = normpath(outlook_auxiliary_path, "CapacityOutlook2024_Condensed.xlsx")
XLSX.writetable(output_melted_path, Tables.columntable(df_melted); sheetname="CapacityOutlook", overwrite=true)

# ================================================ #
# Storage energy and capacity outlook
# vpp_cap     = normpath(datapath, "CapacityOutlook/Storage/StorageOutlook_Capacity.xlsx")
# vpp_ene     = normpath(datapath, "CapacityOutlook/Storage/StorageOutlook_Energy.xlsx")
# ================================================ #
# modify code here
storage_energy_dfs   = DataFrame[]
storage_capacity_dfs = DataFrame[]
for f in file_list
    if endswith(f, ".xlsx")
        file_path     = normpath(outlook_core_path, f)
        parts         = split(f, " - ")
        scenario_full = length(parts) >= 2 ? strip(parts[2]) : ""

        energy_df = PISP.read_xlsx_with_header(file_path, "Storage Energy", "A3:AG5000")
        insertcols!(energy_df, 2, :Scenario => fill(scenario_full, nrow(energy_df)))
        energy_df = filter(row -> any(x -> x isa Number && !ismissing(x), row), energy_df)
        push!(storage_energy_dfs, energy_df)

        capacity_df = PISP.read_xlsx_with_header(file_path, "Storage Capacity", "A3:AG5000")
        insertcols!(capacity_df, 2, :Scenario => fill(scenario_full, nrow(capacity_df)))
        capacity_df = filter(row -> any(x -> x isa Number && !ismissing(x), row), capacity_df)
        push!(storage_capacity_dfs, capacity_df)
    end
end

combined_energy_df   = isempty(storage_energy_dfs) ? DataFrame() : vcat(storage_energy_dfs...; cols = :union)
combined_capacity_df = isempty(storage_capacity_dfs) ? DataFrame() : vcat(storage_capacity_dfs...; cols = :union)

storage_energy_path   = normpath(outlook_auxiliary_path, "StorageEnergyOutlook_2024_ISP.xlsx")
storage_capacity_path = normpath(outlook_auxiliary_path, "StorageCapacityOutlook_2024_ISP.xlsx")
scenario_labels = collect(keys(PISP.SCE))

energy_sheets = Pair{String,Any}[]
capacity_sheets = Pair{String,Any}[]
for sc in scenario_labels
    sc_rows_energy = filter(:Scenario => ==(sc), combined_energy_df)
    sc_rows_capacity = filter(:Scenario => ==(sc), combined_capacity_df)

    push!(energy_sheets, sc => Tables.columntable(sc_rows_energy))
    push!(capacity_sheets, sc => Tables.columntable(sc_rows_capacity))
end

if isempty(energy_sheets)
    XLSX.writetable(storage_energy_path, Tables.columntable(combined_energy_df); sheetname="StorageEnergyOutlook_2024_ISP", overwrite=true)
else
    XLSX.writetable(storage_energy_path, energy_sheets; overwrite=true)
end

if isempty(capacity_sheets)
    XLSX.writetable(storage_capacity_path, Tables.columntable(combined_capacity_df); sheetname="StorageCapacityOutlook_2024_ISP", overwrite=true)
else
    XLSX.writetable(storage_capacity_path, capacity_sheets; overwrite=true)
end

# =============================================== #
# dsp_data    = normpath(datapath, "CapacityOutlook/2024ISP_DSP.xlsx") #This should be directly taken from the ISP data
# =============================================== #
# Generate Excel files with the REZ Generation Capacity as auxiliary files
function read_rez_capacity(path::AbstractString)
    # Align with other readers: grab the bounded range with headers
    return PISP.read_xlsx_with_header(path, "REZ Generation Capacity", "A3:AG5000")
end
rez_files = [
    "2024 ISP - Green Energy Exports - Core.xlsx",
    "2024 ISP - Progressive Change - Core.xlsx",
    "2024 ISP - Step Change - Core.xlsx",
]

for fname in rez_files
    src   = normpath(outlook_core_path, fname)
    df    = read_rez_capacity(src)
    dest  = normpath(outlook_auxiliary_path, replace(fname, ".xlsx" => "_REZCAP.xlsx"))
    XLSX.writetable(dest, Tables.columntable(df); sheetname = "REZ Generation Capacity", overwrite = true)
end
# =============================================== #
# Generate trace 4006 
# =============================================== #
# Reference weather years for generating the trace of the 2024 ISP Optimal Development Path (4006)
# Sourced from: https://aemo.com.au/-/media/files/major-publications/isp/2024/supporting-materials/2024-isp-plexos-model-instructions.pdf?la=en
const DATE_RANGES_REFYEARS = [
    (Date("2024-07-01"), Date("2025-06-30"), 2019),
    (Date("2025-07-01"), Date("2026-06-30"), 2020),
    (Date("2026-07-01"), Date("2027-06-30"), 2021),
    (Date("2027-07-01"), Date("2028-06-30"), 2022),
    (Date("2028-07-01"), Date("2029-06-30"), 2023),
    (Date("2029-07-01"), Date("2030-06-30"), 2015),
    (Date("2030-07-01"), Date("2031-06-30"), 2011),
    (Date("2031-07-01"), Date("2032-06-30"), 2012),
    (Date("2032-07-01"), Date("2033-06-30"), 2013),
    (Date("2033-07-01"), Date("2034-06-30"), 2014),
    (Date("2034-07-01"), Date("2035-06-30"), 2015),
    (Date("2035-07-01"), Date("2036-06-30"), 2016),
    (Date("2036-07-01"), Date("2037-06-30"), 2017),
    (Date("2037-07-01"), Date("2038-06-30"), 2018),
    (Date("2038-07-01"), Date("2039-06-30"), 2019),
    (Date("2039-07-01"), Date("2040-06-30"), 2020),
    (Date("2040-07-01"), Date("2041-06-30"), 2021),
    (Date("2041-07-01"), Date("2042-06-30"), 2022),
    (Date("2042-07-01"), Date("2043-06-30"), 2023),
    (Date("2043-07-01"), Date("2044-06-30"), 2015),
    (Date("2044-07-01"), Date("2045-06-30"), 2011),
    (Date("2045-07-01"), Date("2046-06-30"), 2012),
    (Date("2046-07-01"), Date("2047-06-30"), 2013),
    (Date("2047-07-01"), Date("2048-06-30"), 2014),
    (Date("2048-07-01"), Date("2049-06-30"), 2015),
    (Date("2049-07-01"), Date("2050-06-30"), 2016),
    (Date("2050-07-01"), Date("2051-06-30"), 2017),
    (Date("2051-07-01"), Date("2052-06-30"), 2018),
]

function process_traces(path::AbstractString)
    df = CSV.read(path, DataFrame)
    df.date = Date.(df.Year, df.Month, df.Day)
    return df
end

function generate_refyear4006_traces(
    tech::AbstractString;
    traces_root::AbstractString = traces_dest,
    years = 2011:2023,
    verbose::Bool = false,
)
    tech_dir = isdir(joinpath(traces_root, tech)) ? joinpath(traces_root, tech) : traces_root
    file_names = readdir(joinpath(tech_dir, "$(tech)_2011"))
    cleaned_file_names = replace.(file_names, "_RefYear2011.csv" => "")
    output_dir = joinpath(tech_dir, "$(tech)_4006")
    mkpath(output_dir)

    output_paths = String[]
    for cleaned_file_name in cleaned_file_names
        verbose && @info cleaned_file_name
        tech_traces = Dict(year => process_traces(joinpath(tech_dir, "$(tech)_$(year)", "$(cleaned_file_name)_RefYear$(year).csv")) for year in years)
        filtered_frames = DataFrame[]
        for (start_date, end_date, ref_year) in DATE_RANGES_REFYEARS
            df = tech_traces[ref_year]
            mask = (df.date .>= start_date) .& (df.date .<= end_date)
            push!(filtered_frames, df[mask, :])
        end
        df_out = vcat(filtered_frames...; cols = :union)
        if "date" in names(df_out)
            select!(df_out, Not("date"))
        end
        output_path = joinpath(output_dir, "$(cleaned_file_name)_RefYear4006.csv")
        CSV.write(output_path, df_out)
        push!(output_paths, output_path)
    end

    return output_paths
end
# =============================================== #
# Generate trace 4006 solar
# =============================================== #
directory_solar = traces_dest
solar_4006_paths = generate_refyear4006_traces("solar"; traces_root = directory_solar)
# =============================================== #
# Generate trace 4006 wind
# =============================================== #
directory_wind = traces_dest
wind_4006_paths = generate_refyear4006_traces("wind"; traces_root = directory_wind)

# =============================================== #
# Generate trace 4006 demand and distributed pv
# =============================================== #
function generate_refyear4006_demand_traces(
    tech::AbstractString;
    traces_root::AbstractString = traces_dest,
    region::AbstractString = "",
    scenario::AbstractString = "",
    years = 2011:2023,
    poe::Real = 10,
    verbose::Bool = false,
)
    poe_int  = Int(poe)
    tech_dir = isdir(joinpath(traces_root, tech)) ? joinpath(traces_root, tech) : traces_root
    base_dir = joinpath(tech_dir, "$(tech)_$(region)_$(scenario)")
    base_name(y) = "$(region)_RefYear_$(y)_$(PISP.DEMSCE[scenario])_POE$(poe_int)"

    output_dir = joinpath(tech_dir, "$(tech)_$(region)_$(scenario)")
    mkpath(output_dir)

    dem_types    = ("OPSO_MODELLING_PVLITE", "PV_TOT")
    output_paths = String[]

    for dt in dem_types
        tech_traces = Dict{Int,DataFrame}(y => process_traces(joinpath(base_dir, "$(base_name(y))_$(dt).csv")) for y in years)
        filtered_frames = DataFrame[]
        for (start_date, end_date, ref_year) in DATE_RANGES_REFYEARS
            df   = tech_traces[ref_year]
            mask = (df.date .>= start_date) .& (df.date .<= end_date)
            push!(filtered_frames, @view df[mask, :])
        end
        df_out = vcat(filtered_frames...; cols = :union)
        select!(df_out, Not("date"))
        output_path = joinpath(output_dir, "$(region)_RefYear_4006_$(PISP.DEMSCE[scenario])_POE$(poe_int)_$(dt).csv")
        CSV.write(output_path, df_out)
        push!(output_paths, output_path)
    end

    return output_paths
end

directory_demand = traces_dest
for region in keys(PISP.NEMBUSNAME)
    for scenario in keys(PISP.DEMSCE)
        demand_4006_paths = generate_refyear4006_demand_traces("demand"; traces_root = directory_demand, region=region, scenario=scenario, poe=10.0)
    end
end