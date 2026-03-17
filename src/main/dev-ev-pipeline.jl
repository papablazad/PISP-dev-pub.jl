using DataFrames
using Dates
using OrderedCollections
using XLSX
using PISP

ev_workbook_path = "/Users/papablaza/git/ARPST-CSIRO-STAGE-5/PISP-dev-pub.jl/data/PISP-downloads/2023-iasr-ev-workbook.xlsx"

const BEV_PHEV_PROFILE_WEEKEND_SHEET = "BEV_PHEV_Profile_kW (Weekend)"
const BEV_PHEV_PROFILE_WEEKDAY_SHEET = "BEV_PHEV_Profile_kW (Weekday)"

include(joinpath(dirname(@__DIR__), "parameters", "general2024ISP.jl"))

const STATE_CODE_BY_NAME = Dict(state_name => state_code for (state_code, state_name) in PISP.NEMAREAS)

is_blank_cell(value) = ismissing(value) || (value isa AbstractString && isempty(strip(value)))

function is_blank_row(row)
    return all(is_blank_cell, row)
end

function is_state_header_row(row)
    if is_blank_cell(row[1]) || !all(is_blank_cell, row[2:end])
        return false
    end

    return haskey(STATE_CODE_BY_NAME, strip(String(row[1])))
end

function is_time_header_row(row)
    first_cell_is_blank = is_blank_cell(row[1])
    later_cells = row[2:end]
    has_time_cells = any(value -> !is_blank_cell(value), later_cells)
    all_time_cells = all(value -> is_blank_cell(value) || value isa Time, later_cells)
    return first_cell_is_blank && has_time_cells && all_time_cells
end

function split_profile_label(label::AbstractString)
    pieces = split(strip(label), ","; limit = 2)
    vehicle_class = strip(first(pieces))
    charging_profile = length(pieces) == 2 ? strip(pieces[2]) : ""
    return vehicle_class, charging_profile
end

function time_column_name(value::Time)
    return Symbol(Dates.format(value, "HH_MM"))
end

function map_state_name_to_code(state_name::AbstractString)
    state_code = get(STATE_CODE_BY_NAME, state_name, nothing)
    state_code === nothing && error("State `$state_name` was not found in NEMAREAS.")
    return state_code
end

function build_bev_phev_profile_dataframe(workbook_path::AbstractString, sheet_name::AbstractString; day_type::AbstractString)
    raw_sheet = XLSX.readdata(workbook_path, sheet_name, "B:AY")
    non_empty_rows = [collect(raw_sheet[row_index, :]) for row_index in axes(raw_sheet, 1) if !is_blank_row(raw_sheet[row_index, :])]

    current_state = nothing
    profile_time_indices = Int[]
    profile_time_columns = Symbol[]

    column_order = Symbol[:vehicle_class, :charging_profile, :state, :day_type]
    columns = Dict{Symbol, Vector}(
        :vehicle_class => String[],
        :charging_profile => String[],
        :state => String[],
        :day_type => String[],
    )

    for row in non_empty_rows
        if is_state_header_row(row)
            current_state = map_state_name_to_code(String(strip(row[1])))
            continue
        end

        if is_time_header_row(row)
            profile_time_indices = findall(value -> !is_blank_cell(value), row[2:end])
            profile_time_columns = [time_column_name(row[index + 1]) for index in profile_time_indices]

            if isempty(profile_time_indices)
                error("No half-hour columns were found in sheet `$sheet_name`.")
            end

            for time_column in profile_time_columns
                if !haskey(columns, time_column)
                    columns[time_column] = Vector{Union{Missing, Float64}}()
                    push!(column_order, time_column)
                end
            end

            continue
        end

        if current_state === nothing || isempty(profile_time_indices) || is_blank_cell(row[1])
            continue
        end

        label = strip(String(row[1]))
        vehicle_class, charging_profile = split_profile_label(label)

        push!(columns[:vehicle_class], vehicle_class)
        push!(columns[:charging_profile], charging_profile)
        push!(columns[:state], current_state)
        push!(columns[:day_type], day_type)

        for (relative_index, time_column) in zip(profile_time_indices, profile_time_columns)
            value = row[relative_index + 1]
            push!(columns[time_column], ismissing(value) ? missing : Float64(value))
        end
    end

    return DataFrame([column => columns[column] for column in column_order])
end

bev_phev_profile_weekend_df = build_bev_phev_profile_dataframe(
    ev_workbook_path,
    BEV_PHEV_PROFILE_WEEKEND_SHEET;
    day_type = "Weekend",
)

bev_phev_profile_weekday_df = build_bev_phev_profile_dataframe(
    ev_workbook_path,
    BEV_PHEV_PROFILE_WEEKDAY_SHEET;
    day_type = "Weekday",
)

# Read and process `Numbers` (x4)

# Read and process `BEV_PHEV_Charge_Type (%)`
