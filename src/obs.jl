"""
    RinexObsHeader(; obs_types, kwargs...)

Header of a RINEX 3.05 observation file.

`obs_types` maps each satellite system character to the ordered list of
observation descriptors (RINEX table A2, e.g. `"C1C"`, `"L1C"`, `"D1C"`,
`"S1C"`) the file carries for that system. It is given as a vector of pairs
to keep the system order deterministic:

    obs_types = ['G' => ["C1C", "L1C", "D1C", "S1C"]]

`time_of_first_obs` may be left as `nothing`; it is then taken from the
first epoch passed to [`write_epoch!`](@ref).
"""
Base.@kwdef struct RinexObsHeader
    program::String = "RINEXParser.jl"
    run_by::String = ""
    marker_name::String = "UNKNOWN"
    marker_type::String = "GEODETIC"
    observer::String = ""
    agency::String = ""
    receiver_number::String = ""
    receiver_type::String = ""
    receiver_version::String = ""
    antenna_number::String = ""
    antenna_type::String = ""
    approx_position::Union{Nothing,NTuple{3,Float64}} = nothing
    antenna_delta_hen::NTuple{3,Float64} = (0.0, 0.0, 0.0)
    obs_types::Vector{Pair{Char,Vector{String}}}
    interval::Union{Nothing,Float64} = nothing
    time_of_first_obs::Union{Nothing,DateTime} = nothing
    leap_seconds::Union{Nothing,Int,NTuple{4,Int}} = nothing
end

"""
    ObsValue(value; lli = nothing, ssi = nothing)

A single observation: the measurement `value` plus the optional
loss-of-lock indicator `lli` (0-7) and signal-strength indicator `ssi`
(1-9). Units follow RINEX conventions: pseudorange in meters, carrier
phase in whole cycles, Doppler in Hz, signal strength in dB-Hz.
"""
struct ObsValue
    value::Float64
    lli::Union{Nothing,Int}
    ssi::Union{Nothing,Int}
end
ObsValue(value; lli = nothing, ssi = nothing) = ObsValue(value, lli, ssi)

"""
    SatObs(system, prn, observations)

Observations of one satellite in one epoch. `observations` must be aligned
with the header's `obs_types` list for `system`; use `nothing` for
observation types without a measurement.
"""
struct SatObs
    system::Char
    prn::Int
    observations::Vector{Union{Nothing,ObsValue}}
end
SatObs(system::Char, prn::Integer, observations::AbstractVector) =
    SatObs(system, Int(prn), Vector{Union{Nothing,ObsValue}}(observations))

"""
    ObsEpoch(time, satellites; fractional_second = 0.0, flag = 0, clock_offset = nothing)

One observation epoch. `time` is the epoch in the file's time system (GPS
time for a GPS file); `fractional_second` carries sub-millisecond precision
beyond `DateTime`. `clock_offset` is the optional receiver clock offset in
seconds written at the end of the epoch record.
"""
struct ObsEpoch
    time::DateTime
    fractional_second::Float64
    flag::Int
    clock_offset::Union{Nothing,Float64}
    satellites::Vector{SatObs}
end
ObsEpoch(time::DateTime, satellites::AbstractVector{SatObs};
    fractional_second = 0.0, flag = 0, clock_offset = nothing) =
    ObsEpoch(time, fractional_second, flag, clock_offset, collect(satellites))

"""
    RinexObsWriter(target, header::RinexObsHeader)

Streaming writer for a RINEX 3.05 observation file. `target` is a path or
an `IO`. The header is written lazily on the first [`write_epoch!`](@ref),
so `time_of_first_obs` can be filled in from the data. Close the writer
(or use the do-block form) to flush the file.

    RinexObsWriter("data.obs", header) do writer
        write_epoch!(writer, epoch)
    end
"""
mutable struct RinexObsWriter{T<:IO}
    io::T
    header::RinexObsHeader
    header_written::Bool
    owns_io::Bool
end
RinexObsWriter(io::IO, header::RinexObsHeader) = RinexObsWriter(io, header, false, false)
RinexObsWriter(path::AbstractString, header::RinexObsHeader) =
    RinexObsWriter(open(path, "w"), header, false, true)

function RinexObsWriter(f::Function, target, header::RinexObsHeader)
    writer = RinexObsWriter(target, header)
    try
        f(writer)
    finally
        close(writer)
    end
end

function Base.close(writer::RinexObsWriter)
    # An empty file still gets its header, so it is valid RINEX.
    writer.header_written || write_obs_header(writer, nothing)
    writer.owns_io ? close(writer.io) : flush(writer.io)
    nothing
end

obs_types_for(header::RinexObsHeader, system::Char) =
    last(header.obs_types[findfirst(p -> first(p) == system, header.obs_types)])

function write_obs_header(writer::RinexObsWriter, first_epoch_time)
    io = writer.io
    header = writer.header
    version_type_line(io, "OBSERVATION DATA", first.(header.obs_types))
    program_line(io, header.program, header.run_by)
    header_line(io, header.marker_name, "MARKER NAME")
    header_line(io, header.marker_type, "MARKER TYPE")
    header_line(io, rpad(header.observer, 20) * header.agency, "OBSERVER / AGENCY")
    header_line(
        io,
        rpad(header.receiver_number, 20) * rpad(header.receiver_type, 20) *
        header.receiver_version,
        "REC # / TYPE / VERS",
    )
    header_line(io, rpad(header.antenna_number, 20) * header.antenna_type, "ANT # / TYPE")
    if !isnothing(header.approx_position)
        content = join(Printf.format(FMT_F14_4, x) for x in header.approx_position)
        header_line(io, content, "APPROX POSITION XYZ")
    end
    content = join(Printf.format(FMT_F14_4, x) for x in header.antenna_delta_hen)
    header_line(io, content, "ANTENNA: DELTA H/E/N")
    for (system, types) in header.obs_types
        for (i, chunk) in enumerate(Iterators.partition(types, 13))
            lead = i == 1 ? string(system, "  ", lpad(length(types), 3)) : " "^6
            header_line(io, lead * join(" " .* chunk), "SYS / # / OBS TYPES")
        end
    end
    if !isnothing(header.interval)
        header_line(io, Printf.format(FMT_F10_3, header.interval), "INTERVAL")
    end
    time_of_first_obs = something(header.time_of_first_obs, first_epoch_time, missing)
    if !ismissing(time_of_first_obs)
        t = time_of_first_obs
        content = lpad(year(t), 6) * lpad(month(t), 6) * lpad(day(t), 6) *
                  lpad(hour(t), 6) * lpad(minute(t), 6) *
                  Printf.format(FMT_F13_7, epoch_seconds(t, 0.0)) *
                  " "^5 * "GPS"
        header_line(io, content, "TIME OF FIRST OBS")
    end
    # Zero phase shift for every carrier-phase observable (mandatory record).
    for (system, types) in header.obs_types, type in types
        startswith(type, "L") || continue
        header_line(io, string(system, " ", type), "SYS / PHASE SHIFT")
    end
    header_line(io, lpad(0, 3), "GLONASS SLOT / FRQ #")
    header_line(io, "", "GLONASS COD/PHS/BIS")
    if !isnothing(header.leap_seconds)
        header_line(io, leap_seconds_content(header.leap_seconds), "LEAP SECONDS")
    end
    header_line(io, "", "END OF HEADER")
    writer.header_written = true
end

indicator(x::Union{Nothing,Int}) = isnothing(x) ? " " : string(x)

"""
    write_epoch!(writer::RinexObsWriter, epoch::ObsEpoch)

Append one epoch record. Writes the file header first if it has not been
written yet.
"""
function write_epoch!(writer::RinexObsWriter, epoch::ObsEpoch)
    writer.header_written || write_obs_header(writer, epoch.time)
    io = writer.io
    t = epoch.time
    print(
        io,
        "> ",
        lpad(year(t), 4), " ",
        lpad(month(t), 2, '0'), " ",
        lpad(day(t), 2, '0'), " ",
        lpad(hour(t), 2, '0'), " ",
        lpad(minute(t), 2, '0'),
        Printf.format(FMT_F11_7, epoch_seconds(t, epoch.fractional_second)),
        "  ", epoch.flag,
        lpad(length(epoch.satellites), 3),
    )
    if !isnothing(epoch.clock_offset)
        print(io, " "^6, Printf.format(FMT_F15_12, epoch.clock_offset))
    end
    println(io)
    for sat in epoch.satellites
        expected = length(obs_types_for(writer.header, sat.system))
        length(sat.observations) == expected || throw(ArgumentError(
            "Satellite $(satellite_id(sat.system, sat.prn)) carries " *
            "$(length(sat.observations)) observations, but the header declares " *
            "$expected observation types for system '$(sat.system)'",
        ))
        # Full-width lines (no trailing-blank trimming) for the benefit of
        # fixed-column parsers, matching RTKLIB and GNSS-SDR output.
        line = satellite_id(sat.system, sat.prn)
        for obs in sat.observations
            line *= isnothing(obs) ? " "^16 :
                    Printf.format(FMT_F14_3, obs.value) * indicator(obs.lli) *
                    indicator(obs.ssi)
        end
        println(io, line)
    end
    nothing
end
