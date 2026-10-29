# Fortran-style fixed-width formatting shared by the obs and nav writers.
# RINEX 3 records are column-oriented: header lines carry 60 columns of
# content followed by the record label; data fields use fixed F/D widths.
# A value wider than its field would shift every field after it, which a
# fixed-column reader cannot detect, so the checks below reject it instead.

const FMT_F14_3 = Printf.Format("%14.3f")
const FMT_F14_4 = Printf.Format("%14.4f")
const FMT_F10_3 = Printf.Format("%10.3f")
const FMT_F11_7 = Printf.Format("%11.7f")
const FMT_F13_7 = Printf.Format("%13.7f")
const FMT_F8_5 = Printf.Format("%8.5f")
const FMT_F8_3 = Printf.Format("%8.3f")
const FMT_F15_12 = Printf.Format("%15.12f")
const FMT_E19_12 = Printf.Format("%19.12E")
const FMT_E12_4 = Printf.Format("%12.4E")
const FMT_E17_10 = Printf.Format("%17.10E")
const FMT_E16_9 = Printf.Format("%16.9E")

# The formats the data records are rendered with. A format used in a record
# belongs here, because the record buffer sizes its reserve from this list.
const RECORD_FORMATS = (FMT_F14_3, FMT_F11_7, FMT_F15_12, FMT_E19_12)

"""
    RecordBuffer()

Scratch buffer of one data record. `Printf` writes into a byte buffer
without allocating, but its `IO` method allocates per field, so the data
writers assemble each record here and write it in one call. Header
records, written once per file, go straight to the IO.
"""
mutable struct RecordBuffer
    bytes::Vector{UInt8}
    position::Int
end
RecordBuffer() = RecordBuffer(Vector{UInt8}(undef, 512), 1)

# Room `Printf` may need for one field of any value (`%f` renders all 309
# integer digits of `floatmax`), reserved before every field so an unchecked
# value cannot write past the buffer. Measured from `RECORD_FORMATS`, so a
# wider format grows it.
const MAX_FIELD_WIDTH = maximum(
    length(Printf.format(format, value)) for format in RECORD_FORMATS,
    value in (floatmax(Float64), -floatmax(Float64), 5.0e-324, -5.0e-324, NaN, -Inf)
)

function reserve!(record::RecordBuffer, count::Int)
    needed = record.position + count - 1
    length(record.bytes) < needed &&
        resize!(record.bytes, max(2 * length(record.bytes), needed))
    record
end

start_record!(record::RecordBuffer) = (record.position = 1; record)

"""
    add_field!(record, format, value)

Append one `Printf` field to `record`. `format` holds a single conversion:
`Printf` boxes the arguments of a format with several of them, and one field
per call is what keeps the writers free of allocations.
"""
function add_field!(record::RecordBuffer, format::Printf.Format, value)
    reserve!(record, MAX_FIELD_WIDTH)
    record.position = Printf.format(record.bytes, record.position, format, value)
    record
end

"""
    add_integer!(record, value, width, pad = ' ')

Append the non-negative integer `value` right-aligned in `width` columns,
rejecting one that does not fit.
"""
function add_integer!(
    record::RecordBuffer,
    value::Integer,
    width::Int,
    pad::UInt8 = UInt8(' '),
)
    count = ndigits(value)
    (value >= 0 && count <= width) || throw(
        ArgumentError(
            "$value does not fit the $width columns of an integer field, which holds " *
            "0 to $(10^width - 1)",
        ),
    )
    reserve!(record, width)
    bytes = record.bytes
    start = record.position
    for i = start:(start+width-count-1)
        bytes[i] = pad
    end
    remaining = value
    for i = (start+width-1):-1:(start+width-count)
        bytes[i] = UInt8('0' + remaining % 10)
        remaining ÷= 10
    end
    record.position = start + width
    record
end

"""
    add_blanks!(record, count)

Append `count` blank columns, the RINEX encoding of a field without a value.
"""
function add_blanks!(record::RecordBuffer, count::Int)
    reserve!(record, count)
    fill!(view(record.bytes, record.position:(record.position+count-1)), UInt8(' '))
    record.position += count
    record
end

function add_char!(record::RecordBuffer, char::Char)
    reserve!(record, 1)
    record.bytes[record.position] = UInt8(char)
    record.position += 1
    record
end

"""
    end_line!(record)

End the current line of `record`, keeping it in the buffer. A record of
several lines - an observation epoch, an ephemeris - is assembled whole
before any of it is written, so that a value one of its later lines cannot
hold leaves the file without the lines before it.
"""
end_line!(record::RecordBuffer) = add_char!(record, '\n')

"""
    flush_record!(io, record)

Write the assembled record to `io` and reset the buffer.
"""
function flush_record!(io::IO, record::RecordBuffer)
    bytes = record.bytes
    GC.@preserve bytes unsafe_write(io, pointer(bytes), record.position - 1)
    start_record!(record)
    nothing
end

"""
    header_line(io, content, label)

Write one RINEX header record: `content` padded to 60 columns followed by
the record `label` (columns 61-80). Longer content is rejected, as a last
check behind the per-field ones.
"""
function header_line(io::IO, content::AbstractString, label::AbstractString)
    length(content) <= 60 || throw(
        ArgumentError(
            "The content of the $label record is $(length(content)) columns wide, " *
            "but a header record holds 60 columns before its label",
        ),
    )
    println(io, rpad(content, 60), label)
end

"""
    check_header_field(value, width, description) -> String

Return the header field `value`, or throw an `ArgumentError` if it is wider
than the `width` columns the record gives it.
"""
check_header_field(value::AbstractString, width::Int, description) =
    length(value) <= width ? value :
    throw(
        ArgumentError(
            "$description is \"$value\", which is $(length(value)) columns wide, " *
            "but the record holds $width columns for it",
        ),
    )

const SATELLITE_SYSTEM_NAMES = Dict(
    'G' => "GPS",
    'R' => "GLONASS",
    'E' => "Galileo",
    'C' => "BDS",
    'J' => "QZSS",
    'I' => "NavIC/IRNSS",
    'S' => "SBAS",
)

"""
    check_satellite_system(satellite_system) -> Char

Return the satellite system character `satellite_system`, or throw an
`ArgumentError` if it does not name a RINEX constellation.
"""
check_satellite_system(satellite_system::Char) =
    haskey(SATELLITE_SYSTEM_NAMES, satellite_system) ? satellite_system :
    throw(ArgumentError("Unknown satellite system character '$satellite_system'"))

"""
    system_character(satellite_systems) -> Char

The satellite system a file containing `satellite_systems` is written for: the
character of its constellation if it holds exactly one, `'M'` for a mixed
file - several systems, or a file that is not pinned to one - otherwise.
Every character is checked, also in a mixed file where none of them is
returned.
"""
function system_character(satellite_systems)
    foreach(check_satellite_system, satellite_systems)
    length(satellite_systems) == 1 ? only(satellite_systems) : 'M'
end

"""
    system_identification(satellite_systems) -> String

The satellite-system field of the `RINEX VERSION / TYPE` record, derived
from the set of satellite system characters contained in the file.
"""
function system_identification(satellite_systems)
    satellite_system = system_character(satellite_systems)
    satellite_system == 'M' ? "M: Mixed" :
    string(satellite_system, ": ", SATELLITE_SYSTEM_NAMES[satellite_system])
end

# Time systems of the constellations, as the three-letter codes of the
# TIME OF FIRST/LAST OBS records. SBAS broadcasts in GPS time and has no
# time system of its own.
const TIME_SYSTEMS = Dict(
    'G' => "GPS",
    'R' => "GLO",
    'E' => "GAL",
    'C' => "BDT",
    'J' => "QZS",
    'I' => "IRN",
    'S' => "GPS",
)

"""
    time_system(satellite_systems) -> String
    time_system(header::RinexObsHeader) -> String

Time system of the epochs of an observation file containing `satellite_systems`,
the satellite system characters, or those of the `obs_codes` of `header`, as the
three-letter code of the `TIME OF FIRST OBS` record: `"GPS"`, `"GLO"`, `"GAL"`,
`"BDT"`, `"QZS"` or `"IRN"`. A single-constellation file is written in that
constellation's time system; a file carrying several constellations uses GPS
time, as RINEX prescribes for mixed files. Every epoch passed to
[`write_epoch!`](@ref) has to be in this time system.

With GNSSSignals loaded, `time_system(GNSSSignals.BDT())` gives the code of a
GNSSSignals time system - `"GPS"`, `"GAL"` or `"BDT"` - and
[`gnss_time_system`](@ref) the time system of a code.
"""
function time_system(satellite_systems)
    length(satellite_systems) == 1 || return "GPS"
    TIME_SYSTEMS[check_satellite_system(only(satellite_systems))]
end

function version_type_line(io::IO, file_type::AbstractString, satellite_systems)
    content =
        rpad(@sprintf("%9.2f", RINEX_VERSION), 20) *
        rpad(file_type, 20) *
        system_identification(satellite_systems)
    header_line(io, content, "RINEX VERSION / TYPE")
end

function program_line(io::IO, program, run_by)
    date = Dates.format(now(UTC), "yyyymmdd HHMMSS") * " UTC"
    content = rpad(program, 20) * rpad(run_by, 20) * date
    header_line(io, content, "PGM / RUN BY / DATE")
end

satellite_id(satellite_system::Char, prn::Integer) =
    string(satellite_system, lpad(prn, 2, '0'))

"""
    check_satellite_number(satellite_system, prn) -> Int

Return the satellite number `prn`, or throw an `ArgumentError` if it is
outside the 1-99 of the two columns of a satellite identification.
"""
check_satellite_number(satellite_system::Char, prn::Integer) =
    0 < prn < 100 ? Int(prn) :
    throw(
        ArgumentError(
            "Satellite number $prn of satellite system '$satellite_system' does not " *
            "fit the two columns of a RINEX satellite identification, which holds 1-99",
        ),
    )

"""
    add_satellite_id!(record, satellite_system, prn)

Append the three-column satellite identification that opens a data record.
"""
function add_satellite_id!(record::RecordBuffer, satellite_system::Char, prn::Integer)
    check_satellite_number(satellite_system, prn)
    add_char!(record, satellite_system)
    add_integer!(record, prn, 2, UInt8('0'))
end

"""
    add_epoch_date!(record, time)

Append the calendar epoch of a data record up to the minute: the year in
four columns, then month, day, hour and minute in two zero-padded columns
each. The seconds follow in the field the individual record uses for them -
`F11.7` in an observation epoch, two integer columns in a navigation record.
"""
function add_epoch_date!(record::RecordBuffer, time::DateTime)
    add_integer!(record, year(time), 4)
    for value in (month(time), day(time), hour(time), minute(time))
        add_char!(record, ' ')
        add_integer!(record, value, 2, UInt8('0'))
    end
    record
end

"""
    fits_fixed_field(value, digits, width) -> Bool

Whether `value` rendered with `digits` decimals fits `width` columns. `NaN`
and `Inf` do not: they render in the right width, but a reader takes them
for a measurement.
"""
function fits_fixed_field(value::Float64, digits::Int, width::Int)
    # Rounding is what reaches the file, so 9999999999.9996 counts as the
    # eleven digits it is printed with, not the ten it has.
    rounded = round(value; digits)
    limit = exp10(width - digits - 1 - (signbit(rounded) ? 1 : 0))
    abs(rounded) < limit
end

"""
    fits_scientific_field(value, digits, width) -> Bool

Whether `value` rendered in `E` notation with `digits` decimals fits `width`
columns: sign, leading digit, point, decimals, `E` and a signed two-digit
exponent. RINEX section 6.8 gives the exponent two digits, so a value
needing three, such as `1e-100`, never fits. Nor do `NaN` and `Inf`, as for
[`fits_fixed_field`](@ref).
"""
function fits_scientific_field(value::Float64, digits::Int, width::Int)
    isfinite(value) || return false
    exponent = iszero(value) ? 0 : floor(Int, log10(abs(value)))
    # Rounding the mantissa can carry into the exponent, and 9.9999999999996e99
    # reaches the file as 1.000000000000E+100.
    round(abs(value) / exp10(exponent); digits) >= 10 && (exponent += 1)
    ndigits(exponent) <= 2 && signbit(value) + 6 + digits <= width
end

"""
    fixed_field_error(description, value, digits, width)

Throw the `ArgumentError` of a value the field cannot hold, kept out of line
so that the check itself stays free of the message it never builds.
"""
@noinline function fixed_field_error(description, value::Float64, digits::Int, width::Int)
    reason =
        isfinite(value) ?
        "does not fit the $width columns of an F$width.$digits field; the rest of " *
        "the record would be shifted out of alignment" :
        "is not finite, and this field has no encoding for a value that is missing"
    throw(ArgumentError("$description is $value, which $reason"))
end

"""
    LeapSeconds(count; future_count = nothing, week = nothing, day = nothing,
                time_system = "")

The `LEAP SECONDS` header record. `count` is the current number of leap
seconds; `future_count` (ΔtLSF), `week` (WN_LSF) and `day` (DN) describe the
leap-second event the message announces, which some parsers require.

`time_system` is what the week and day count in: `"GPS"` (weeks from
1980-01-06, days 1-7) or `"BDT"` (weeks from 2006-01-01, days 0-6). The
default `""` leaves the field blank, which a reader takes as `"GPS"`.

A header also takes a plain `Int` or an `NTuple{4,Int}`: `leap_seconds = 18`
or `leap_seconds = (18, 18, 2185, 7)`.
"""
struct LeapSeconds
    count::Int
    future_count::Union{Nothing,Int}
    week::Union{Nothing,Int}
    day::Union{Nothing,Int}
    time_system::String
    function LeapSeconds(count, future_count, week, day, time_system)
        time_system in ("", "GPS", "BDT") || throw(
            ArgumentError(
                "The time system of a LEAP SECONDS record is \"GPS\" or \"BDT\", " *
                "or \"\" to leave the field blank, not \"$time_system\"",
            ),
        )
        # The day number counts the day before the event, from the first day
        # of the week of the respective system.
        if !isnothing(day)
            days = time_system == "BDT" ? (0:6) : (1:7)
            day in days || throw(
                ArgumentError(
                    "The day number of a LEAP SECONDS record in " *
                    "$(isempty(time_system) ? "GPS" : time_system) time is " *
                    "$(first(days))-$(last(days)), not $day",
                ),
            )
        end
        new(count, future_count, week, day, time_system)
    end
end
LeapSeconds(
    count::Integer;
    future_count = nothing,
    week = nothing,
    day = nothing,
    time_system = "",
) = LeapSeconds(Int(count), future_count, week, day, String(time_system))

Base.convert(::Type{LeapSeconds}, count::Integer) = LeapSeconds(count)
Base.convert(::Type{LeapSeconds}, fields::NTuple{4,Integer}) =
    LeapSeconds(fields[1]; future_count = fields[2], week = fields[3], day = fields[4])

# A field the record does not carry is blank rather than zero, which is a
# leap-second count of its own.
leap_seconds_field(::Nothing) = " "^6
leap_seconds_field(value::Int) = lpad(value, 6)

# `4I6,A3`: the identifier follows the day number with no separator, so it
# occupies columns 25-27. The four counts are always written, blank where
# the record does not carry them, to put it there.
leap_seconds_content(leap_seconds::LeapSeconds) =
    lpad(leap_seconds.count, 6) *
    leap_seconds_field(leap_seconds.future_count) *
    leap_seconds_field(leap_seconds.week) *
    leap_seconds_field(leap_seconds.day) *
    leap_seconds.time_system

"""
    epoch_minute_seconds(time, fractional_second) -> (DateTime, Float64)

The minute of a record epoch and the seconds within it, including the
sub-millisecond `fractional_second` that `DateTime` cannot carry. The
seconds are rounded to their seven decimals first, so seconds that round to
60 carry into the next minute, and negative ones borrow from the minute
before.
"""
function epoch_minute_seconds(time::DateTime, fractional_second)
    start = floor(time, Minute)
    seconds = round(second(time) + millisecond(time) / 1000 + fractional_second; digits = 7)
    seconds >= 60 && return start + Minute(1), seconds - 60
    seconds < 0 && return start - Minute(1), seconds + 60
    # Adding zero turns a `-0.0` into the `0.0` it is written as.
    start, seconds + 0.0
end
