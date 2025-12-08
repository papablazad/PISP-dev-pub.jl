function default_data_paths(;filepath=@__DIR__)
    return (
        ispdata19   = normpath(filepath, "2019-input-and-assumptions-workbook-v1-3-dec-19.xlsx"),
        ispdata24   = normpath(filepath, "2024-isp-inputs-and-assumptions-workbook.xlsx"),
        ispmodel    = normpath(filepath, "2024 ISP Model"),
        profiledata = normpath(filepath, "Traces/"),
        outlookdata = normpath(filepath, "Core"),
        outlookAEMO = normpath(filepath, "Auxiliary/CapacityOutlook2024_Condensed.xlsx"),
        vpp_cap     = normpath(filepath, "Auxiliary/StorageCapacityOutlook_2024_ISP.xlsx"),
        vpp_ene     = normpath(filepath, "Auxiliary/StorageEnergyOutlook_2024_ISP.xlsx"),
    )
end

using PISP
using Dates

function fill_problem_table_year(tc::PISPtimeConfig, year::Int)
    # unchanged
end

function build_ISP24_datasets(; 
    downloadpath::AbstractString = normpath(@__DIR__, "../../", "data-download-v2"),
    poe::Integer = 10,
    reftrace::Integer = 2011,
    years::AbstractVector{<:Integer} = [2025],
    output_name::AbstractString = "out", # Output folder name
    output_root::Union{Nothing,AbstractString} = nothing,
    download_files::Bool = true,
)
    if any(y -> y < 2025 || y > 2050, years)
        throw(ArgumentError("Years must be between 2025 and 2050 (got $(years))."))
    end

    data_paths = PISP.default_data_paths(filepath=downloadpath)

    # Download/extract/build inputs once
    PISP.build_pipeline(download_files = download_files, data_root = downloadpath, poe = poe)

    base_name = "$(output_name)-ref$(reftrace)-poe$(poe)"

    for year in years
        tc, ts, tv = PISP.initialise_time_structures()
        fill_problem_table_year(tc, year)

        static_params = PISP.populate_time_static!(tc, ts, tv, data_paths; refyear = reftrace, poe = poe)
        PISP.populate_time_varying!(tc, ts, tv, data_paths, static_params; refyear = reftrace, poe = poe)

        PISP.write_time_data(ts, tv;
            csv_static_path    = "$(base_name)/csv",
            csv_varying_path   = "$(base_name)/csv/schedule-$(year)",
            arrow_static_path  = "$(base_name)/arrow",
            arrow_varying_path = "$(base_name)/arrow/schedule-$(year)",
            write_static       = true,
            write_varying      = true,
            output_root        = output_root,
        )
    end
end
