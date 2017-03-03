print_timer(; kwargs...) = show(STDOUT, DEFAULT_TIMER; kwargs...)
print_timer(io::IO; kwargs...) = show(io, DEFAULT_TIMER; kwargs...)
print_timer(io::IO, to::TimerOutput; kwargs...) = show(io, to; kwargs...)
print_timer(to::TimerOutput; kwargs...) = show(STDOUT, to; kwargs...)

Base.show(to::TimerOutput; kwargs...) = show(STDOUT, to; kwargs...)
function Base.show(io::IO, to::TimerOutput; allocations::Bool = true, sortby::Symbol = :time, linechars::Symbol = :unicode, compact::Bool = false)
    sortby  in (:time, :ncalls, :allocations) || throw(ArgumentError("sortby should be :time, :allocations or :ncalls, got $sortby"))
    linechars in (:unicode, :ascii)           || throw(ArgumentError("linechars should be :unicode or :ascii, got $linechars"))

    t₀, b₀ = to.start_data.time, to.start_data.allocs
    t₁, b₁ = time_ns(), gc_bytes()
    Δt, Δb = t₁ - t₀, b₁ - b₀
    ∑t, ∑b = to.flattened ? to.totmeasured : totmeasured(to)

    max_name = longest_name(to)
    available_width = displaysize(io)[2]
    requested_width = max_name
    if compact
        if allocations
            requested_width += 46
        else
            requested_width += 27
        end
    else
        if allocations
            requested_width += 61
        else
            requested_width += 34
        end
    end


    #requested_width = 34 + (allocations ? 27 : 0) + max_name
    name_length = max(9, max_name - max(0, requested_width - available_width))

    print_header(io, Δt, Δb, ∑t, ∑b, name_length, true, allocations, linechars, compact)
    for timer in sort!(collect(values(to.inner_timers)); rev = true, by = x -> sortf(x, sortby))
        _print_timer(io, timer, ∑t, ∑b, 0, name_length, allocations, sortby, compact)
    end
    print_header(io, Δt, Δb, ∑t, ∑b, name_length, false, allocations, linechars, compact)
end

function sortf(x, sortby)
    sortby == :time        && return x.accumulated_data.time
    sortby == :ncalls      && return x.accumulated_data.ncalls
    sortby == :allocations && return x.accumulated_data.allocs
    error("internal error")
end

function print_header(io, Δt, Δb, ∑t, ∑b, name_length, header, allocations, linechars, compact)
    global BOX_MODE, ALLOCATIONS_ENABLED

    midrule       = linechars == :unicode ? "─" : "-"
    topbottomrule = linechars == :unicode ? "─" : "-"
    sec_ncalls = string(" ", rpad("Section", name_length, " "), " ncalls  ")
    time_headers = "  time   %tot " * (compact ? "" : " %timed ")
    alloc_headers = allocations ? ("  alloc   %tot " * (compact ? "" : " %alloc ")) : ""
    total_table_width = sum(strwidth.((sec_ncalls, time_headers, alloc_headers))) + 3

    # Just hardcoded shit to make things look nice
    compact && (total_table_width += 2)
    !allocations && (total_table_width -= 3)
    !allocations && compact && (total_table_width -= 1)

    function center(str, len)
        x = (len - strwidth(str)) ÷ 2
        return string(" "^x, str, " "^(len - strwidth(str) - x))
    end

    if header
        time_alloc_pading = " "^(strwidth(sec_ncalls))

        if compact
            time_header       = "     Time     "
        else
            time_header       = "         Time         "
        end

        time_underline = midrule^strwidth(time_header)

        if compact
            allocation_header       = " Allocations "
        else
            allocation_header = "      Allocations      "
        end



        alloc_underline = midrule^strwidth(allocation_header)
        #tot_meas_str = string(" ", rpad("Tot / % measured:", strwidth(sec_ncalls) - 1, " "))
        if compact
            tot_meas_str = center("Total measured:", strwidth(sec_ncalls))
        else
            tot_meas_str = center("Tot / % measured:", strwidth(sec_ncalls))
        end


        str_time =  center(string(prettytime(∑t)    , compact ? "" : string(" / ", prettypercent(∑t, Δt))), strwidth(time_header))
        str_alloc = center(string(prettymemory(∑b)  , compact ? "" : string(" / ", prettypercent(∑b, Δb))), strwidth(allocation_header))

        header_str = string(" time   %tot  %timed")
        tot_midstr = string(sec_ncalls, "  ", header_str)
        print(io, " ", Crayon(bold = true)(topbottomrule^total_table_width), "\n")
        if ! (allocations == false && compact == true)
            print(io, " ", time_alloc_pading, time_header)
            allocations && print(io, "   ", allocation_header)
            print(io, "\n")
            print(io, " ", time_alloc_pading, time_underline)
            allocations && print(io, "   ", alloc_underline)
            print(io, "\n")
            print(io, " ", tot_meas_str, str_time)
            allocations && print(io, "   ", str_alloc)
            print(io, "\n\n")
        end
        print(io, " ", sec_ncalls, time_headers)
        allocations && print(io, "   ", alloc_headers)
        print(io, "\n")
        print(io, " ", midrule^total_table_width, "\n")
    else
        print(io, " ", Crayon(bold = true)(topbottomrule^total_table_width))
    end
end

function _print_timer(io::IO, to::TimerOutput, ∑t::Integer, ∑b::Integer, indent::Integer, name_length, allocations, sortby, compact)
    accum_data = to.accumulated_data
    t = accum_data.time
    b = accum_data.allocs
    name = to.name
    if length(name) >= name_length - indent
        name = string(name[1:name_length-3-indent], "...")
    end
    print(io, "  ")
    nc = accum_data.ncalls
    print(io, " "^indent, rpad(name, name_length + 2-indent))
    print(io, " "^(5 - ndigits(nc)), nc)

    print(io, "   ", lpad(prettytime(t),        6, " "))
    print(io, "  ",  lpad(prettypercent(t, ∑t), 5, " "))
    !compact && print(io, "  ",  lpad(prettypercent(t, ∑t), 5, " "))

    if allocations
    print(io, "     ", lpad(prettymemory(b),      7, " "))
    print(io, "  ",    lpad(prettypercent(b, ∑b), 5, " "))
    !compact && print(io, "  ",    lpad(prettypercent(b, ∑b), 5, " "))
    end
    print(io, "\n")

    for timer in sort!(collect(values(to.inner_timers)), rev = true, by = x -> sortf(x, sortby))
        _print_timer(io, timer, ∑t, ∑b, indent + 2, name_length, allocations, sortby, compact)
    end
end
