using DataFrames
using Dates
using OrderedCollections
using XLSX
using PISP
using CSV

include(joinpath(dirname(@__DIR__), "utils", "dataframes", "PISPutils-df-evs-2024.jl"))

"""
    ev_der_sched(tc, ts, tv, iasr2024_path, evworkbook_path)

Build EV DER schedules from the 2023 IASR EV workbook and the 2024 ISP
subregional allocation workbook, ensure matching EV DER entries exist in
`ts.der`, and append the resulting schedule rows to `tv.der_pred`.

# Arguments
- `tc`: Time-configuration container with the populated `problem` table.
- `ts`: Time-static container with populated `bus`, `dem`, and `der` tables.
- `tv`: Time-varying container whose `der_pred` table is mutated in place.
- `iasr2024_path::AbstractString`: Path to the 2024 ISP inputs and assumptions workbook.
- `evworkbook_path::AbstractString`: Path to the 2023 IASR EV workbook.

# Returns
- `DataFrame`: The EV DER schedule rows appended to `tv.der_pred`.
"""
function ev_der_sched(tc, ts, tv, iasr2024_path::AbstractString, evworkbook_path::AbstractString)
    bev_phev_profile_weekend_df = ev_build_bev_phev_profile_dataframe(
        evworkbook_path,
        EV_2024_BEV_PHEV_PROFILE_WEEKEND_SHEET;
        day_type = "Weekend",
    )
    bev_phev_profile_weekday_df = ev_build_bev_phev_profile_dataframe(
        evworkbook_path,
        EV_2024_BEV_PHEV_PROFILE_WEEKDAY_SHEET;
        day_type = "Weekday",
    )
    profiles = vcat(bev_phev_profile_weekend_df, bev_phev_profile_weekday_df)

    vehicle_numbers_wide_dfs = OrderedDict(
        sheet_name => ev_build_vehicle_numbers_dataframe(evworkbook_path, sheet_name)
        for sheet_name in ev_get_vehicle_numbers_sheet_names(evworkbook_path)
    )
    vehicle_numbers_dfs = OrderedDict(
        sheet_name => ev_melt_vehicle_numbers_dataframe(vehicle_numbers_wide_dfs[sheet_name], number_column)
        for (sheet_name, number_column) in EV_2024_VEHICLE_NUMBER_VALUE_COLUMN_BY_SHEET
    )

    bev_numbers_df = vehicle_numbers_dfs["BEV_Numbers"]
    phev_numbers_df = vehicle_numbers_dfs["PHEV_Numbers"]
    ev_numbers_join_keys = [:scenario, :state, :vehicle_type, :category, :year]
    ev_numbers = reduce(
        (left_df, right_df) -> outerjoin(left_df, right_df; on = ev_numbers_join_keys),
        [bev_numbers_df, phev_numbers_df],
    )

    bev_phev_charge_type_df = ev_build_bev_phev_charge_type_dataframe(
        evworkbook_path,
        EV_2024_BEV_PHEV_CHARGE_TYPE_SHEET,
    )
    subregional_demand_allocation_df = ev_melt_subregional_demand_allocation_dataframe(
        ev_build_subregional_demand_allocation_dataframe(iasr2024_path),
    )
    ev_assign_subregional_bus_ids!(subregional_demand_allocation_df, ts)

    ev_data_years = Set(ev_collect_data_dates(tc.problem))
    scenario_ids = sort(collect(unique(tc.problem.scenario)))

    shares = filter(row -> row.year in ev_data_years && row.scenario in scenario_ids, bev_phev_charge_type_df)
    numbers = filter(row -> row.year in ev_data_years && row.scenario in scenario_ids, ev_numbers)
    subregional = filter(row -> row.year in ev_data_years && row.scenario in scenario_ids, subregional_demand_allocation_df)

    _profiles = leftjoin(profiles, numbers, on = ["state", "vehicle_type"])
    _profiles.category = [ev_map_vehicle_type_to_category(string(vehicle_type)) for vehicle_type in _profiles.vehicle_type]
    _profiles = leftjoin(
        _profiles,
        shares[:, [:state, :category, :charging, :share, :scenario, :year]],
        on = [:state, :category, :charging_profile => :charging, :scenario, :year],
    )

    all_times = collect(minimum(tc.problem.dstart):Hour(1):maximum(tc.problem.dend))
    stacked_chunks = DataFrame[]

    for sc in scenario_ids
        for date_fy in sort(collect(ev_data_years))
            filtered_profiles = filter(row -> row.year == date_fy && row.scenario == sc, _profiles)
            filtered_subregional = filter(row -> row.year == date_fy && row.scenario == sc, subregional)

            if isempty(filtered_profiles) || isempty(filtered_subregional)
                continue
            end

            filtered_profiles = copy(filtered_profiles)
            filtered_profiles.total_number =
                coalesce.(filtered_profiles.number_bev, 0) .+ coalesce.(filtered_profiles.number_phev, 0)
            filtered_profiles.total_number_share =
                filtered_profiles.total_number .* coalesce.(filtered_profiles.share, 0.0)

            profile_start_index = findfirst(==("00_00"), names(filtered_profiles))
            profile_end_index = findfirst(==("23_30"), names(filtered_profiles))

            if !isnothing(profile_start_index) && !isnothing(profile_end_index) && profile_start_index <= profile_end_index
                leading_columns = names(filtered_profiles)[1:(profile_start_index - 1)]
                profile_columns = names(filtered_profiles)[profile_start_index:profile_end_index]
                trailing_columns = names(filtered_profiles)[(profile_end_index + 1):end]
                select!(filtered_profiles, vcat(leading_columns, trailing_columns, profile_columns))
            end

            profile_column_names = ev_get_profile_column_names(filtered_profiles)
            isempty(profile_column_names) && continue

            idxs_weekday = findall(filtered_profiles.day_type .== "Weekday")
            idxs_weekend = findall(filtered_profiles.day_type .== "Weekend")
            total_profiles_weekday = filtered_profiles[idxs_weekday, profile_column_names] .* filtered_profiles.total_number_share[idxs_weekday]
            total_profiles_weekday.state = filtered_profiles.state[idxs_weekday]
            total_profiles_weekend = filtered_profiles[idxs_weekend, profile_column_names] .* filtered_profiles.total_number_share[idxs_weekend]
            total_profiles_weekend.state = filtered_profiles.state[idxs_weekend]

            for col in profile_column_names
                if col[end-1:end] == "00"
                    total_profiles_weekday[!, col] =
                        (total_profiles_weekday[!, col] .+ total_profiles_weekday[!, string(col[1:end-2], "30")]) ./ 2
                    total_profiles_weekend[!, col] =
                        (total_profiles_weekend[!, col] .+ total_profiles_weekend[!, string(col[1:end-2], "30")]) ./ 2
                end
            end

            total_profiles_weekday = total_profiles_weekday[:, Not(profile_column_names[2:2:end])]
            total_profiles_weekend = total_profiles_weekend[:, Not(profile_column_names[2:2:end])]

            fy_times = [t for t in all_times if ev_format_profile_year(t) == date_fy]
            isempty(fy_times) && continue

            weekday_mask = dayofweek.(fy_times) .<= 5
            final_profiles = DataFrame(date = fy_times)

            for region in sort(unique(filtered_subregional.id_bus))
                final_profiles[!, string(region)] = zeros(length(fy_times))
            end

            for state in unique(filtered_profiles.state)
                weekday_profile =
                    sum(Matrix(total_profiles_weekday[total_profiles_weekday.state .== state, Not(:state)]), dims = 1)[:] ./ 1e3
                weekend_profile =
                    sum(Matrix(total_profiles_weekend[total_profiles_weekend.state .== state, Not(:state)]), dims = 1)[:] ./ 1e3

                state_subregional = filtered_subregional[filtered_subregional.state .== state, :]
                isempty(state_subregional) && continue
                sort!(state_subregional, :id_bus)

                state_bus_columns = string.(state_subregional.id_bus)
                state_shares = state_subregional.share

                for (i, t) in pairs(fy_times)
                    if weekday_mask[i]
                        final_profiles[i, state_bus_columns] .= weekday_profile[hour(t) + 1] .* state_shares
                    else
                        final_profiles[i, state_bus_columns] .= weekend_profile[hour(t) + 1] .* state_shares
                    end
                end
            end

            stacked_profiles = stack(final_profiles, Not(:date), variable_name = :id_bus, value_name = :value)
            stacked_profiles.id_bus = parse.(Int64, stacked_profiles.id_bus)
            stacked_profiles.scenario .= sc
            stacked_profiles.value .= round.(stacked_profiles.value, digits = 3)
            push!(stacked_chunks, stacked_profiles[:, [:id_bus, :scenario, :date, :value]])
        end
    end

    if isempty(stacked_chunks)
        return DataFrame(id = Int[], id_der = Int[], scenario = Int[], date = DateTime[], value = Float64[])
    end

    all_stacked = reduce(vcat, stacked_chunks)
    # ev_der_tables!(ts)
    der_id_by_bus = ev_der_id_by_bus(ts)

    missing_ev_profile_bus_ids = unique(filter(id_bus -> !haskey(der_id_by_bus, id_bus), all_stacked.id_bus))
    isempty(missing_ev_profile_bus_ids) || error(
        "Missing `id_der` mapping for EV profile bus ids: $(join(string.(missing_ev_profile_bus_ids), ", ")).",
    )

    all_stacked.id_der = [der_id_by_bus[id_bus] for id_bus in all_stacked.id_bus]
    all_stacked.id = zeros(Int, nrow(all_stacked))
    select!(all_stacked, [:id, :id_der, :scenario, :date, :value])
    sort!(all_stacked, [:id_der, :scenario, :date])

    first_pred_id = isempty(tv.der_pred) ? 1 : maximum(tv.der_pred.id) + 1
    all_stacked.id = first_pred_id:(first_pred_id + nrow(all_stacked) - 1)
    append!(tv.der_pred, all_stacked)

    return all_stacked
end

ev_workbook_path   = "/Users/papablaza/git/ARPST-CSIRO-STAGE-5/PISP-dev-pub.jl/data/PISP-downloads/2023-iasr-ev-workbook.xlsx"
iasr_workbook_path = "/Users/papablaza/git/ARPST-CSIRO-STAGE-5/PISP-dev-pub.jl/data/PISP-downloads/2024-isp-inputs-and-assumptions-workbook.xlsx"
# =============================== #
# Data from other PISP elements
years        = [2030,2031,2032]
scenarios    = [1,2,3]
reftrace     = 2011
poe          = 10
downloadpath = normpath("/Users/papablaza/git/ARPST-CSIRO-STAGE-5/PISP-dev-pub.jl/data/PISP-downloads")
data_paths   = PISP.default_data_paths(filepath=downloadpath)

tc, ts, tv = nothing, nothing, nothing # Just handling this as a placeholder here to avoid warnings about unused variables, the actual structures are created and populated in the loop below
for year in years
    tc, ts, tv = PISP.initialise_time_structures()
    PISP.fill_problem_table_year(tc, year, sce=scenarios)
    static_params = PISP.populate_time_static!(ts, tv, data_paths; refyear = reftrace, poe = poe)
    @info "Populating time-varying data from ISP 2024 - POE $(poe) - reference weather trace $(reftrace) - planning year $(year) ..."
    PISP.populate_time_varying!(tc, ts, tv, data_paths, static_params; refyear = reftrace, poe = poe)
    ev_der_sched(tc, ts, tv, iasr23_ev_workbook, ev_workbook_path)
end

# =============================== #


