const MAX_PHASE_SHIFT_SATELLITES = 99

"""
    check_phase_shift_satellites(system, code, satellites) -> satellites

Return the satellite list of a [`PhaseShift`](@ref), or throw an
`ArgumentError` if the record cannot hold it. The list is a `Vector`, so it
stays open to `push!` after the shift was constructed; the header writer
therefore checks it again, and this is what both of them call.
"""
function check_phase_shift_satellites(system::Char, code, satellites)
    foreach(prn -> check_satellite_number(system, prn), satellites)
    # The list is counted into an `I2.2` field, and the count is what tells
    # a reader how many of the identifications that follow to read.
    length(satellites) <= MAX_PHASE_SHIFT_SATELLITES || throw(
        ArgumentError(
            "The phase shift of $system $code names $(length(satellites)) " *
            "satellites, but the record counts them in two columns, which holds " *
            "$MAX_PHASE_SHIFT_SATELLITES; leave the list empty to name every " *
            "satellite of the system",
        ),
    )
    satellites
end

"""
    PhaseShift(system, code, correction; satellites = Int[])

One `SYS / PHASE SHIFT` header record: the correction in cycles that was
applied to the carrier phase `code` of `system` to align it with the
reference signal of its band (RINEX 3.05 Table A23). `satellites` names the
satellite numbers the correction applies to; an empty list means every
satellite of the system, which is the usual case.

RINEX 3.05 section 5.2.12 gives the record three distinct readings, and the
one a file makes is a statement about its data:

  - a **correction** (`-0.25`) says the phase was not aligned as it came out
    of the receiver and this is what was added to align it,
  - **zero** says the phase arrived aligned - from the receiver or from a
    stream such as RTCM-MSM - and nothing was applied,
  - a **blank** correction says the code is the reference signal of its band
    and needs none. This is what a code no `PhaseShift` names is written as.

The default is therefore a claim that every carrier phase in the file is a
reference signal. A file carrying a non-reference code (GPS `L2S`, Galileo
`L8Q`, ...) has to say which of the first two applies to it, or a reader
cannot reconstruct what the receiver measured.
"""
struct PhaseShift
    system::Char
    code::String
    correction::Float64
    satellites::Vector{Int}
    function PhaseShift(system, code, correction, satellites)
        check_satellite_system(system)
        startswith(code, "L") || throw(
            ArgumentError(
                "A phase shift corrects a carrier phase, so \"$code\" is not a code " *
                "it can be given for; carrier phase codes start with \"L\"",
            ),
        )
        # Converted before it is measured against its columns, so that the
        # `Real` the constructor takes reaches the check as the `Float64` it
        # is written as.
        correction = Float64(correction)
        fits_fixed_field(correction, 5, 8) ||
            fixed_field_error("Phase shift of $system $code", correction, 5, 8)
        new(
            system,
            String(code),
            correction,
            check_phase_shift_satellites(system, code, collect(Int, satellites)),
        )
    end
end
PhaseShift(system::Char, code::AbstractString, correction::Real; satellites = Int[]) =
    PhaseShift(system, code, correction, satellites)

"""
    RinexObsHeader(; obs_types, kwargs...)

Header of a RINEX 3.05 observation file.

`obs_types` maps each satellite system character to the ordered list of
observation descriptors (RINEX table A2, e.g. `"C1C"`, `"L1C"`, `"D1C"`,
`"S1C"`) the file carries for that system. It is given as a vector of pairs
to keep the system order deterministic:

    obs_types = ['G' => ["C1C", "L1C", "D1C", "S1C"]]

`phase_shifts` carries the [`PhaseShift`](@ref) records of the carrier
phases that were corrected to align them with the reference signal of their
band; a phase code no entry names is written as a reference signal that
needed none.

`time_of_first_obs` may be left as `nothing`; it is then taken from the
first epoch passed to [`write_epoch!`](@ref) and assigned to the header, so
that [`rinex_filename`](@ref) can name the file from the header afterwards.

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
    phase_shifts::Vector{PhaseShift} = PhaseShift[]
    interval::Union{Nothing,Float64} = nothing
    time_of_first_obs::Union{Nothing,DateTime} = nothing
    leap_seconds::Union{Nothing,LeapSeconds} = nothing
end

"""
    ObsValue(value; lli = nothing, ssi = nothing)

A single observation: the measurement `value` plus the optional loss-of-lock
indicator `lli` and signal-strength indicator `ssi`. Units follow RINEX
conventions: pseudorange in meters, carrier phase in whole cycles, Doppler
in Hz, signal strength in dB-Hz.

The loss-of-lock indicator is a bit field of three bits, so it holds 0-7
(section 6.7.1). The signal strength is documented as 1-9, and `ssi = 0` is
accepted next to those: it is what a receiver reports for a projected signal
strength it does not have yet.

A non-finite `value` is written as a blank field, which is how RINEX
records that an observation type carries no measurement for a satellite.
"""
struct ObsValue
    value::Float64
    lli::Union{Nothing,Int}
    ssi::Union{Nothing,Int}
    function ObsValue(value, lli, ssi)
        new(value, check_indicator(lli, "lli", 7), check_indicator(ssi, "ssi", 9))
    end
end
ObsValue(value; lli = nothing, ssi = nothing) = ObsValue(value, lli, ssi)

# Both indicators occupy a single column, so neither can hold more than one
# digit; the loss-of-lock indicator is narrower still, being three bits.
check_indicator(::Nothing, name, largest) = nothing
check_indicator(indicator::Integer, name, largest) =
    0 <= indicator <= largest ? Int(indicator) :
    throw(
        ArgumentError("Observation indicator $name is $indicator, but it holds 0-$largest"),
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

`flag` is 0 for an ordinary epoch and 1 to mark a power failure between the
previous epoch and this one. The remaining flags of RINEX 3.05 Table A3
(2-5) introduce event records, whose epoch line counts header records rather
than satellites and is followed by those instead of by observations; this
writer does not produce them, so it rejects those flags rather than write
observations under a record type that does not carry them.
"""
struct ObsEpoch
    time::DateTime
    fractional_second::Float64
    flag::Int
    clock_offset::Union{Nothing,Float64}
    satellites::Vector{SatObs}
    function ObsEpoch(time, fractional_second, flag, clock_offset, satellites)
        flag in (0, 1) || throw(
            ArgumentError(
                "The epoch flag is $flag, but this writer records observations, " *
                "which is flag 0 or - for a power failure since the previous epoch " *
                "- flag 1; the event records of flags 2-5 are not written",
            ),
        )
        new(time, fractional_second, flag, clock_offset, satellites)
    end
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

# Checked when the writer is created, so a header the records cannot hold
# does not surface from the lazy header write inside `close`.
function check_obs_header(header::RinexObsHeader)
    foreach(check_satellite_system, first.(header.obs_types))
    check_header_field(header.program, 20, "The program of the header")
    check_header_field(header.run_by, 20, "The agency running the program")
    check_header_field(header.marker_name, 60, "The marker name")
    check_header_field(header.marker_type, 20, "The marker type")
    check_header_field(header.observer, 20, "The observer")
    check_header_field(header.agency, 40, "The agency")
    check_header_field(header.receiver_number, 20, "The receiver number")
    check_header_field(header.receiver_type, 20, "The receiver type")
    check_header_field(header.receiver_version, 20, "The receiver version")
    check_header_field(header.antenna_number, 20, "The antenna number")
    check_header_field(header.antenna_type, 20, "The antenna type")
    for (i, shift) in enumerate(header.phase_shifts)
        check_phase_shift_satellites(shift.system, shift.code, shift.satellites)
        codes = obs_types_for(header, shift.system)
        shift.code in codes || throw(
            ArgumentError(
                "The phase shift of $(shift.system) $(shift.code) names an " *
                "observation type the header does not declare for system " *
                "'$(shift.system)'; it declares $(join(codes, ", "))",
            ),
        )
        # One code may carry several records, one per group of satellites,
        # but a satellite cannot be told two corrections for the same phase
        # - and an empty list already claims all of them.
        for other in view(header.phase_shifts, 1:(i-1))
            (other.system == shift.system && other.code == shift.code) || continue
            overlap =
                isempty(shift.satellites) || isempty(other.satellites) ?
                "every satellite of the system" :
                let shared = intersect(shift.satellites, other.satellites)
                    isempty(shared) ? "" :
                    join(map(prn -> satellite_id(shift.system, prn), sort(shared)), ", ")
                end
            isempty(overlap) || throw(
                ArgumentError(
                    "Two phase shifts of $(shift.system) $(shift.code) apply to " *
                    "$overlap, which would tell it two corrections for one " *
                    "carrier phase",
                ),
            )
        end
    end
    nothing
end

function Base.close(writer::RinexObsWriter)
    try
        # An empty file still gets its header, so it is valid RINEX.
        writer.header_written || write_obs_header(writer, nothing, 0.0)
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
            "carries the systems " *
            join(map(p -> "'$(first(p))'", header.obs_types), ", "),
        ),
    )
    last(header.obs_types[index])
end

function write_obs_header(writer::RinexObsWriter, first_epoch_time, first_epoch_fraction)
    io = writer.io
    header = writer.header
    # Checked again here, not only where the writer was created: the header
    # is documented as assignable until this runs, so this is the first
    # point at which what is written out is known.
    check_obs_header(header)
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
    # The epoch the record is taken from carries the sub-millisecond part of
    # its seconds, which the header field is wide enough to hold; a time the
    # header itself was given has none. Taking it from the data also fills
    # the header field in, so that `rinex_filename` can name the file from
    # the header once the first epoch has been written.
    if isnothing(header.time_of_first_obs) && !isnothing(first_epoch_time)
        header.time_of_first_obs = first_epoch_time
        fraction = first_epoch_fraction
    else
        fraction = 0.0
    end
    if !isnothing(header.time_of_first_obs)
        t = header.time_of_first_obs
        content =
            lpad(year(t), 6) *
            lpad(month(t), 6) *
            lpad(day(t), 6) *
            lpad(hour(t), 6) *
            lpad(minute(t), 6) *
            Printf.format(FMT_F13_7, epoch_seconds(t, fraction)) *
            " "^5 *
            time_system(first.(header.obs_types))
        header_line(io, content, "TIME OF FIRST OBS")
    end
    # One record per carrier phase, which the format makes mandatory: the
    # correction that aligned it, or a blank saying it is the reference
    # signal of its band. See `PhaseShift` for what each of them claims.
    for (system, types) in header.obs_types, type in types
        startswith(type, "L") || continue
        stated = false
        # A code may carry more than one record, because a correction need
        # not apply to every satellite of the system.
        for shift in header.phase_shifts
            (shift.system == system && shift.code == type) || continue
            phase_shift_lines(io, system, type, shift)
            stated = true
        end
        stated || phase_shift_lines(io, system, type, nothing)
    end
    header_line(io, lpad(0, 3), "GLONASS SLOT / FRQ #")
    header_line(io, "", "GLONASS COD/PHS/BIS")
    if !isnothing(header.leap_seconds)
        header_line(io, leap_seconds_content(header.leap_seconds), "LEAP SECONDS")
    end
    header_line(io, "", "END OF HEADER")
    writer.header_written = true
end

# `A1,1X,A3,1X,F8.5,2X,I2.2` and then the satellite numbers as `10(1X,A3)`,
# continued on further records - indented past the fields they repeat - when
# more than ten of them are named.
const PHASE_SHIFT_SATELLITES_PER_LINE = 10

function phase_shift_lines(io::IO, system::Char, code::AbstractString, ::Nothing)
    header_line(io, string(system, ' ', code), "SYS / PHASE SHIFT")
end
function phase_shift_lines(io::IO, system::Char, code::AbstractString, shift::PhaseShift)
    lead = string(system, ' ', code, ' ') * Printf.format(FMT_F8_5, shift.correction)
    if isempty(shift.satellites)
        return header_line(io, lead, "SYS / PHASE SHIFT")
    end
    # A count of zero already means "every satellite of the system", so the
    # field carries the length of a list that is written out.
    lead *= " "^2 * lpad(length(shift.satellites), 2, '0')
    for (i, chunk) in
        enumerate(Iterators.partition(shift.satellites, PHASE_SHIFT_SATELLITES_PER_LINE))
        content =
            (i == 1 ? lead : " "^18) *
            join(' ' * satellite_id(system, prn) for prn in chunk)
        header_line(io, content, "SYS / PHASE SHIFT")
    end
    nothing
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
written yet. The whole epoch is checked before its first line is written, so
an epoch this rejects leaves the file as it was.
"""
function write_epoch!(writer::RinexObsWriter, epoch::ObsEpoch)
    # The epoch line and every satellite line are assembled in the buffer,
    # and a value a field cannot hold throws while they are: nothing has
    # reached the file at that point, so a rejected epoch leaves it as it
    # was. Writing the lines as they were formatted used to leave a fragment
    # behind that the epochs following it could not be told apart from.
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
    end_line!(record)
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
        end_line!(record)
    end
    writer.header_written || write_obs_header(writer, epoch.time, epoch.fractional_second)
    flush_record!(writer.io, record)
    nothing
end
