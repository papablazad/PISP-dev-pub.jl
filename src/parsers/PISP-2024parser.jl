function problem_table(tc)
    start_date = DateTime(2025, 1, 1, 0, 0, 0)
    step_ = Day(7) 
    nblocks = 5
    date_blocks = PISP.OrderedDict()
    ref_year = 2025

    for i in 1:nblocks
        dstart = start_date + (i-1) * step_
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
        pbname = "$(PISP.ID2SCE[sc])_$(i)"
        nd_yr = ref_year
        dstart = DateTime(nd_yr, month(date_blocks[i][1]), day(date_blocks[i][1]), 0, 0, 0)
        dend   = DateTime(nd_yr, month(date_blocks[i][2]), day(date_blocks[i][2]), 23, 0, 0)
        arr = [i, replace(pbname," "=> "_"), sc, 1, "UC", dstart, dend, 60]
        push!(tc.problem, arr)
        i = i + 1
    end
end

function bus_table(ts)
    idx = 1
    for b in keys(PISP.NEMBUSES)
        push!(ts.bus,(idx, b, PISP.NEMBUSNAME[b], true, PISP.NEMBUSES[b][1], PISP.NEMBUSES[b][2], PISP.STID[PISP.BUS2AREA[b]]))
        idx += 1
    end
end

function line_table(ts, tv, ispdata24)
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
    return Results
end

function line_sched_table(tc, tv, TXdata)
    wmonths = [4,5,6,7,8,9]     # Winter months
    smonths = [10,11,12,1,2,3]  # Summer months
    probs   = tc.problem        # Call problem table 

    txd_max = maximum(tv.line_tmax.id) + 1
    txd_min = maximum(tv.line_tmin.id) + 1

    for txid in 1:nrow(TXdata)
        for p in 1:nrow(probs)
            scid = probs[p,:scenario][1]    # Scenario ID
            dstart = probs[p,:dstart]       # Start date of a week
            dend = probs[p,:dend]           # End date of a week
            ys = Dates.year(dstart)         # Start year of a week
            ds = Dates.day(dstart)          # Start day of a week
            de = Dates.day(dend)            # End day of a week
            ms = Dates.month(dstart)        # Start month of a week
            me = Dates.month(dend)          # End month of a week

            if ms in wmonths                # If starting month is in winter months
                push!(tv.line_tmax, (id=txd_max, id_lin=txid, scenario=scid, date=DateTime(dstart), value=TXdata[txid,8]))
                push!(tv.line_tmin, (id=txd_min, id_lin=txid, scenario=scid, date=DateTime(dstart), value=TXdata[txid,11]))
            else
                push!(tv.line_tmax, (id=txd_max, id_lin=txid, scenario=scid, date=DateTime(dstart), value=TXdata[txid,7]))
                push!(tv.line_tmin, (id=txd_min, id_lin=txid, scenario=scid, date=DateTime(dstart), value=TXdata[txid,10]))
            end
            txd_max += 1
            txd_min += 1

            if (ms in wmonths && me in smonths) || (ms in smonths && me in wmonths)
                @warn "Problem start month is in winter and end month is in summer, check written data."
                if me in wmonths
                    push!(tv.line_tmax, (id=txd, id_lin=txid, scenario=scid, date=DateTime(ys,me,1), value=TXdata[txid,8]))
                    push!(tv.line_tmin, (id=txd, id_lin=txid, scenario=scid, date=DateTime(ys,me,1), value=TXdata[txid,11]))
                else
                    push!(tv.line_tmax, (id=txd, id_lin=txid, scenario=scid, date=DateTime(ys,me,1), value=TXdata[txid,7]))
                    push!(tv.line_tmin, (id=txd, id_lin=txid, scenario=scid, date=DateTime(ys,me,1), value=TXdata[txid,10]))
                end
                txd_max += 1
                txd_min += 1
            end
        end
    end
end

function line_invoptions(ts, ispdata24)
    bust = ts.bus
    maxidlin = isempty(ts.line) ? 0 : maximum(ts.line.id_lin)
    DATALININV = PISP.read_xlsx_with_header(ispdata24, "Flow Path Augmentation options", "B11:N94")
    skip = ["Option Name",""]
    df = DataFrame(Option = String[], Direction = String[], Forward = Float64[], Reverse = Float64[], Cost = Float64[], LeadYears = Float64[])

    Results = DataFrame(name = String[], busA = String[], busB = String[], idbusA = Int64[], idbusB = Int64[],fwd = Float64[], rev = Float64[], invcost = Float64[], lead = Float64[])
    bn1 = ""; bn2 = "";
    # Loop over every possible candidate line
    for a in 1:nrow(DATALININV)
        #Just select the options that are not MISSING or not are in SKIP (i.e, only real options)
        if ismissing(DATALININV[a, 4]) || DATALININV[a, 4] in skip continue end
        # Bus FROM -> TO of candidates.
        if !ismissing(DATALININV[a, 6]) 
            bn1 = split(string(DATALININV[a, 6]),[' '])[1]
            bn2 = split(string(DATALININV[a, 6]),[' '])[3]
        end
        
        # Modified the input data sheet for Augmentation options, project energyconnect goes from SNSW to SA
        aux = [split(string(DATALININV[a,4]),['(','\n'])[1],
            bn1,                                                                     # BUS_FROM_NAME
                bn2,                                                                 # BUS_TO_NAME
                bust[bust[!, :name] .== bn1,:id_bus][1],                                 # BUS_FROM_ID
                bust[bust[!, :name] .== bn2,:id_bus][1],                                 # BUS_TO_ID
                PISP.flow2num(split(string(DATALININV[a, 7]),    ['(','\n'])[1]),    # FWD POWER
                PISP.flow2num(split(string(DATALININV[a, 8]),    ['(','\n'])[1]),    # REV POWER
                PISP.inv2num(split(string(DATALININV[a, 9]),     ['(','\n'])),       # INDICATIVE_COST_ESTIMATE
                PISP.lead2year(split(string(DATALININV[a, 13]),  ['(','\n'])[1])]    # LEAD TIME
        push!(Results, aux)
    end

    #MODIFY INVESTMENT OPTIONS COST (The issue was resolved in function inv2num)
    factive(x) = x in ["SQ-CQ Option 3", "NNSW–SQ Option 3"] ?  0 : 1 # Non-network options deactivated, no investment cost info
    idx = 0
    for a in 1:nrow(Results)
        maxidlin+=1
        idx+=1
        # Element to add to table LINE
        linename = string(strip(Results[a,1]))
        invname = "NL_$(Results[a,4])$(Results[a,5])_INV$(idx)"

        vline = [maxidlin, linename, invname, "DC", max(Results[a,6],Results[a,7]), Results[a,4], Results[a,5], factive(Results[a,1]), factive(Results[a,1]), 0.01, 0.1, Results[a,7], Results[a,6], 220, 1, "", "", 1, 1, 0]

        push!(ts.line, vline)
    end
end