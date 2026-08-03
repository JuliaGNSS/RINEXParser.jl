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

The header is mutable, and the writer only reads it when it writes the
header out on the first epoch, so fields that the data provides late - a
position solution, the leap seconds decoded from the navigation message -
can be assigned to `writer.header` any time before that:

    writer.header.approx_position = position
    writer.header.leap_seconds = leap_seconds
"""
Base.@kwdef mutable struct RinexObsHeader
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

A single observation: the measurement `value` plus the optional loss-of-lock
indicator `lli` and signal-strength indicator `ssi`. Units follow RINEX
conventions: pseudorange in meters, carrier phase in whole cycles, Doppler
in Hz, signal strength in dB-Hz.

RINEX documents the loss-of-lock indicator as a bit field of 0-7 and the
signal strength as 1-9, but both are written as a single digit, so any of
0-9 is accepted - `ssi = 0` is what a receiver reports for a projected
signal strength it does not have yet.

A non-finite `value` is written as a blank field, which is how RINEX
records that an observation type carries no measurement for a satellite.
"""
struct ObsValue
    value::Float64
    lli::Union{Nothing,Int}
    ssi::Union{Nothing,Int}
    function ObsValue(value, lli, ssi)
        new(value, check_indicator(lli, "lli"), check_indicator(ssi, "ssi"))
    end
end
ObsValue(value; lli = nothing, ssi = nothing) = ObsValue(value, lli, ssi)

# Both indicators occupy a single column, so a value of more than one digit
# would shift the rest of the record.
check_indicator(::Nothing, name) = nothing
check_indicator(indicator::Integer, name) =
    0 <= indicator <= 9 ? Int(indicator) :
    throw(
        ArgumentError(
            "Observation indicator $name is $indicator, but it occupies a single " *
            "column and holds 0-9",
        ),
    )

"""
    SatObs(system, prn, observations)
    SatObs(header, system, prn, "C1C" => value, "L1C" => value, ...)

Observations of one satellite in one epoch.

The first form takes the observations aligned with the header's `obs_types`
list for `system`, using `nothing` for observation types without a
measurement. The second form addresses them by observation descriptor
instead and derives the alignment from `header` (a [`RinexObsHeader`](@ref)
or a [`RinexObsWriter`](@ref)), which cannot be misaligned:

    SatObs(writer, 'G', 2, "C1C" => 21234567.890, "L1C" => ObsValue(111583948.752; ssi = 7))

A value is a plain number, an [`ObsValue`](@ref) carrying the loss-of-lock
and signal-strength indicators, or `nothing` for a measurement that is not
available in this epoch. Observation types the header declares but the call
does not mention are left blank. Descriptors may also be given as symbols
(`:C1C`), and as any iterable of pairs instead of separate arguments.
"""
struct SatObs
    system::Char
    prn::Int
    observations::Vector{Union{Nothing,ObsValue}}
end
SatObs(system::Char, prn::Integer, observations::AbstractVector) =
    SatObs(system, Int(prn), Vector{Union{Nothing,ObsValue}}(observations))

SatObs(header::RinexObsHeader, system::Char, prn::Integer, observations::Pair...) =
    SatObs(header, system, prn, observations)

function SatObs(header::RinexObsHeader, system::Char, prn::Integer, observations)
    types = obs_types_for(header, system)
    values = Vector{Union{Nothing,ObsValue}}(nothing, length(types))
    given = falses(length(types))
    for observation in observations
        observation isa Pair || throw(
            ArgumentError(
                "Observations addressed by observation type are given as " *
                "\"C1C\" => value pairs, not as $(typeof(observation)); the form " *
                "taking a vector aligned with the header's obs_types is " *
                "SatObs(system, prn, observations)",
            ),
        )
        descriptor, value = observation
        code = obs_code(descriptor)
        index = findfirst(==(code), types)
        isnothing(index) && throw(
            ArgumentError(
                "Observation type \"$code\" is not declared for system '$system' in " *
                "the header, which carries $(join(types, ", "))",
            ),
        )
        given[index] &&
            throw(ArgumentError("Observation type \"$code\" is given more than once"))
        given[index] = true
        values[index] = obs_value(value)
    end
    SatObs(system, Int(prn), values)
end

# The two halves of an observation pair, each answering what it does not
# accept instead of failing to convert it.
obs_code(descriptor::AbstractString) = String(descriptor)
obs_code(descriptor::Symbol) = String(descriptor)
obs_code(descriptor) = throw(
    ArgumentError(
        "An observation type is named by a string or a symbol, like \"C1C\" or " *
        ":C1C, not by a $(typeof(descriptor))",
    ),
)

obs_value(value::ObsValue) = value
obs_value(value::Real) = ObsValue(value)
obs_value(::Nothing) = nothing
obs_value(value) = throw(
    ArgumentError(
        "An observation is a number, an ObsValue or nothing for a measurement that " *
        "is not available, not a $(typeof(value))",
    ),
)

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
ObsEpoch(
    time::DateTime,
    satellites::AbstractVector{SatObs};
    fractional_second = 0.0,
    flag = 0,
    clock_offset = nothing,
) = ObsEpoch(time, fractional_second, flag, clock_offset, collect(satellites))

"""
    RinexObsWriter(target, header::RinexObsHeader)

Streaming writer for a RINEX 3.05 observation file. `target` is a path or
an `IO`. The header is written lazily on the first [`write_epoch!`](@ref),
so `time_of_first_obs` can be filled in from the data, and the mutable
[`RinexObsHeader`](@ref) in `writer.header` can be completed until then.
Close the writer (or use the do-block form) to flush the file.

    RinexObsWriter("data.obs", header) do writer
        write_epoch!(writer, epoch)
    end
"""
mutable struct RinexObsWriter{T<:IO}
    io::T
    header::RinexObsHeader
    header_written::Bool
    owns_io::Bool
    record::RecordBuffer
end
function RinexObsWriter(io::IO, header::RinexObsHeader)
    check_obs_header(header)
    RinexObsWriter(io, header, false, false, RecordBuffer())
end
function RinexObsWriter(path::AbstractString, header::RinexObsHeader)
    check_obs_header(header)
    RinexObsWriter(open(path, "w"), header, false, true, RecordBuffer())
end

function RinexObsWriter(f::Function, target, header::RinexObsHeader)
    writer = RinexObsWriter(target, header)
    try
        f(writer)
    finally
        close(writer)
    end
end

# Checked when the writer is created, so an unknown system character does
# not surface from the lazy header write inside `close`.
check_obs_header(header::RinexObsHeader) =
    foreach(check_satellite_system, first.(header.obs_types))

function Base.close(writer::RinexObsWriter)
    try
        # An empty file still gets its header, so it is valid RINEX.
        writer.header_written || write_obs_header(writer, nothing)
    finally
        writer.owns_io ? close(writer.io) : flush(writer.io)
    end
    nothing
end

SatObs(writer::RinexObsWriter, system::Char, prn::Integer, observations::Pair...) =
    SatObs(writer.header, system, prn, observations)
SatObs(writer::RinexObsWriter, system::Char, prn::Integer, observations) =
    SatObs(writer.header, system, prn, observations)

function obs_types_for(header::RinexObsHeader, system::Char)
    index = findfirst(p -> first(p) == system, header.obs_types)
    isnothing(index) && throw(
        ArgumentError(
            "The header declares no observation types for system '$system'; it " *
            "carries the systems $(join(map(p -> "'$(first(p))'", header.obs_types), ", "))",
        ),
    )
    last(header.obs_types[index])
end

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
        rpad(header.receiver_number, 20) *
        rpad(header.receiver_type, 20) *
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
        content =
            lpad(year(t), 6) *
            lpad(month(t), 6) *
            lpad(day(t), 6) *
            lpad(hour(t), 6) *
            lpad(minute(t), 6) *
            Printf.format(FMT_F13_7, epoch_seconds(t, 0.0)) *
            " "^5 *
            time_system(first.(header.obs_types))
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

add_indicator!(record::RecordBuffer, ::Nothing) = add_char!(record, ' ')
add_indicator!(record::RecordBuffer, indicator::Int) =
    add_char!(record, Char('0' + indicator))

# An observation field is 14 columns of value plus one column each for the
# loss-of-lock and signal-strength indicator. A measurement that is not
# available - `nothing`, or a value that is not finite - leaves the whole
# field blank, which is what RINEX reads as "no observation"; a finite value
# too large for its columns is an error rather than a shifted record.
add_observation!(record::RecordBuffer, ::Nothing, sat::SatObs, code) =
    add_blanks!(record, 16)
function add_observation!(record::RecordBuffer, obs::ObsValue, sat::SatObs, code)
    isfinite(obs.value) || return add_blanks!(record, 16)
    fits_fixed_field(obs.value, 3, 14) || fixed_field_error(
        "Observation $code of satellite $(satellite_id(sat.system, sat.prn))",
        obs.value,
        3,
        14,
    )
    add_field!(record, FMT_F14_3, obs.value)
    add_indicator!(record, obs.lli)
    add_indicator!(record, obs.ssi)
end

"""
    write_epoch!(writer::RinexObsWriter, epoch::ObsEpoch)

Append one epoch record. Writes the file header first if it has not been
written yet.
"""
function write_epoch!(writer::RinexObsWriter, epoch::ObsEpoch)
    writer.header_written || write_obs_header(writer, epoch.time)
    io = writer.io
    record = start_record!(writer.record)
    t = epoch.time
    add_char!(record, '>')
    add_char!(record, ' ')
    add_epoch_date!(record, t)
    seconds = epoch_seconds(t, epoch.fractional_second)
    fits_fixed_field(seconds, 7, 11) ||
        fixed_field_error("Seconds of the epoch", seconds, 7, 11)
    add_field!(record, FMT_F11_7, seconds)
    add_blanks!(record, 2)
    add_integer!(record, epoch.flag, 1)
    add_integer!(record, length(epoch.satellites), 3)
    if !isnothing(epoch.clock_offset)
        offset = epoch.clock_offset
        fits_fixed_field(offset, 12, 15) ||
            fixed_field_error("Receiver clock offset of the epoch", offset, 12, 15)
        add_blanks!(record, 6)
        add_field!(record, FMT_F15_12, offset)
    end
    end_record!(io, record)
    for sat in epoch.satellites
        types = obs_types_for(writer.header, sat.system)
        length(sat.observations) == length(types) || throw(
            ArgumentError(
                "Satellite $(satellite_id(sat.system, sat.prn)) carries " *
                "$(length(sat.observations)) observations, but the header declares " *
                "$(length(types)) observation types for system '$(sat.system)'",
            ),
        )
        # Full-width lines (no trailing-blank trimming) for the benefit of
        # fixed-column parsers, matching RTKLIB and GNSS-SDR output.
        add_satellite_id!(record, sat.system, sat.prn)
        for (code, obs) in zip(types, sat.observations)
            add_observation!(record, obs, sat, code)
        end
        end_record!(io, record)
    end
    nothing
end
