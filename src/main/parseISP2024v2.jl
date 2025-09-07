using PISP
using DataFrames
using Dates

# Initialise DataFrames
tc = PISPtimeConfig();
ts = PISPtimeStatic();
tv = PISPtimeVarying();

# ======================================== #
# FILE PATHS    
# ======================================== #
datapath    = normpath(@__DIR__, "..", "..", "data");
ispdata24   = normpath(datapath, "2024 ISP Inputs and Assumptions workbook.xlsx");
ispdata19   = normpath(datapath, "2019InputandAssumptionsworkbookv13Dec19.xls");
profiledata = "/Users/papablaza/Library/CloudStorage/OneDrive-TheUniversityofMelbourne/Modelling/ISP24/Traces/";

# ============================================ #
# === Fill problem table with information  === #
# ============================================ #
start_date = DateTime(2025, 1, 1, 0, 0, 0)
step = Day(7) 
nblocks = 5
date_blocks = PISP.OrderedDict()
ref_year = 2025

for i in 1:nblocks
    dstart = start_date + (i-1) * step
    dend = dstart + Day(6) + Hour(23)

    if month(dend) >= 07 && month(dstart) <= 6
        dend = DateTime(year(dstart), month(dstart), 30, 23, 0, 0)
    end

    if i>1 && day(date_blocks[i-1][2]) == 30 && month(date_blocks[i-1][2]) == 6
        dstart = DateTime(year(dstart), month(dstart), 1, 0, 0, 0)
    end

    date_blocks[i] = (dstart, dend)
end

i = 1
for sc in keys(PISP.ID2SCE)
    global i
    pbname = "$(PISP.ID2SCE[sc])_$(i)"
    nd_yr = ref_year
    dstart = DateTime(nd_yr, month(date_blocks[i][1]), day(date_blocks[i][1]), 0, 0, 0)
    dend   = DateTime(nd_yr, month(date_blocks[i][2]), day(date_blocks[i][2]), 23, 0, 0)
    arr = [i, replace(pbname," "=> "_"), sc, 1, "UC", dstart, dend, 60]
    push!(tc.problem, arr)
    i = i + 1
end

# ============================================ #
# ============= Bus table parser ============= #
# ============================================ #
idx = 1
for b in keys(PISP.NEMBUSES)
    push!(ts.bus,(idx, b, PISP.NEMBUSNAME[b], true, PISP.NEMBUSES[b][1], PISP.NEMBUSES[b][2], PISP.STID[PISP.BUS2AREA[b]]))
    idx += 1
end

# ============================================ #
# ============= Line table parser ============ #
# ============================================ #
bust = ts.bus

# Read XLSX with line capacities
DATALINES = PISP.read_xlsx_with_header(ispdata24, "Network Capability", "B6:H21")
Results = DataFrame(name = String[], busA = String[], busB = String[], idbusA = Int64[], idbusB = Int64[], fwd_peak = Float64[], fwd_summer = Float64[], fwd_winter = Float64[], rev_peak = Float64[], rev_summer = Float64[], rev_winter = Float64[])
# Link names
NEMTX = ["CQ->NQ", "CQ->GG", "SQ->CQ", "QNI North", "Terranora", "QNI South","CNSW->SNW North","CNSW->SNW South", "VNI North","VNI South","Heywood","SESA->CSA","Murraylink", "Basslink"]
# Link is Interconnector?
INT = [false, false, false, true, true, false, false, false, false, true, true, false, true, true]
NEMTYPE = ["DC", "DC", "DC", "DC", "DC", "DC", "DC", "DC", "DC", "DC", "DC", "DC", "DC", "DC"]
#Build summary of capacities
for a in 2:nrow(DATALINES)
    aux = []
    nar = split(DATALINES[a,1]," "); 
    length(nar) == 1 ? nar = split(DATALINES[a,1],"-") : nar = nar
    if length(nar) > 2 deleteat!(nar, 2) end
    bn1 = string(nar[1]); bn2 = string(nar[2]);
    # NAME_LINK, BUS_FROM, BUS_TO, BUS_ID_FROM, BUS_ID_TO
    aux = [string(bn1, "->", bn2), bn1, bn2, bust[bust[!,:name] .== bn1,:id_bus][1], bust[bust[!,:name] .== bn2,:id_bus][1]]
    # Add columns 
    for b in 2:ncol(DATALINES)
        #FWD_PEAK, FWD_SUMMER, FWD_WINTER, REV_PEAK, REV_SUMMER, REV_WINTER
        data = parse(Int64, replace(split(string(DATALINES[a, b]),['.', ' ', '\n'])[1], "," => ""))
        append!(aux, data)
    end
    push!(Results, aux)
end

#Populate Line table
for a in 1:nrow(Results)
    #ID, NAME, ALIAS, TECH, CAPACITY, BUS_ID_FROM, BUS_ID_TO, INVESTMENT, ACTIVE, R, X, TMIN, TMAX, VOLTAGE, SEGMENTS, LATITUDE, LONGITUDE, LENGTH, N, CONTINGENCY
    maxcap = maximum([Results[a, :fwd_winter], Results[a, :rev_winter]])
    vallin = (
            id_lin     = a,
            name        = Results[a, :name],
            alias       = NEMTX[a],
            tech        = NEMTYPE[a],
            capacity    = maxcap,
            id_bus_from = Results[a, :idbusA],
            id_bus_to   = Results[a, :idbusB],
            investment  = 0,
            active      = true,
            r           = 0.01,
            x           = 0.1,
            tmin        = Results[a, :rev_winter],
            tmax        = Results[a, :fwd_winter],
            voltage     = 220.0,
            segments    = 1,
            latitude    = "",
            longitude   = "",
            length      = 1.0,
            n           = 1,
            contingency = 0
        )
        push!(ts.line, vallin)
end

# Manual register of Project EnergyConnect 
npln        = nrow(ts.line) 
maxidlin    = isempty(ts.line) ? 0 : maximum(ts.line.id_lin)

# Build the new row
new_line = (
    id_lin      = maxidlin + 1,
    name        = "SNSW->CSA",
    alias       = "Project EnergyConnect",
    tech        = "DC",
    capacity    = 800,
    id_bus_from = 8,
    id_bus_to   = 11,
    investment  = 0,
    active      = 1,
    r           = 0.01,
    x           = 0.1,
    tmin        = 800,
    tmax        = 800,
    voltage     = 220.0,
    segments    = 1,
    latitude    = "",
    longitude   = "",
    length      = 1.0,
    n           = 1,
    contingency = 0
)
push!(ts.line, new_line)

function insert_line_schedule!(df::DataFrame, line_id, scenario, date, capacity)
    newrow = (
        id       = nrow(df) + 1,
        id_lin   = line_id,
        scenario = scenario,
        date     = date,
        value    = capacity
    )
    push!(df, newrow)
end

# Project EnergyConnect Stage 1: 150MW in 2024
for s in 1:3
    insert_line_schedule!(tv.line_tmax, 15, s, DateTime(2024, 7, 1), 150)
    insert_line_schedule!(tv.line_tmin, 15, s, DateTime(2024, 7, 1), 150)
end

# Stage 2
for s in 1:3
    insert_line_schedule!(tv.line_tmax, 15, s, DateTime(2026, 7, 1), 800)
    insert_line_schedule!(tv.line_tmin, 15, s, DateTime(2026, 7, 1), 800)
end