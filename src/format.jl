# Fortran-style fixed-width formatting shared by the obs and nav writers.
# RINEX 3 records are column-oriented: header lines carry 60 columns of
# content followed by the record label; data fields use fixed F/D widths.

const FMT_F14_3 = Printf.Format("%14.3f")
const FMT_F14_4 = Printf.Format("%14.4f")
const FMT_F10_3 = Printf.Format("%10.3f")
const FMT_F11_7 = Printf.Format("%11.7f")
const FMT_F13_7 = Printf.Format("%13.7f")
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

Scratch buffer of one data record. `Printf` renders a field into a byte
buffer without allocating, while its `IO` method allocates a worst-case
buffer per field (464 bytes for an `F14.3`), so the data writers - which
run per epoch and per ephemeris - assemble each record here and hand the
finished line to the IO in a single write. Header records are written
straight to the IO instead; they happen once per file.
"""
mutable struct RecordBuffer
    bytes::Vector{UInt8}
    position::Int
end
RecordBuffer() = RecordBuffer(Vector{UInt8}(undef, 512), 1)

# Room `Printf` may need for one field, whatever value it is handed: an `%f`
# conversion renders the 309 integer digits of the largest `Float64` ahead
# of its decimals, far past the columns the field occupies in a valid
# record. Reserved before every field, so that a value the writers do not
# range-check cannot write past the end of the buffer - and measured from
# the formats in use rather than assumed, so that a wider format added to
# `RECORD_FORMATS` grows the reserve with it.
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

Append the non-negative integer `value` right-aligned in `width` columns.
A value of more columns than the field holds is rejected rather than
shifting the rest of the record.
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
    end_record!(io, record)

Write the assembled record to `io` as one line and reset the buffer.
"""
function end_record!(io::IO, record::RecordBuffer)
    add_char!(record, '\n')
    bytes = record.bytes
    GC.@preserve bytes unsafe_write(io, pointer(bytes), record.position - 1)
    start_record!(record)
    nothing
end

"""
    header_line(io, content, label)

Write one RINEX header record: `content` padded to 60 columns followed by
the record `label` (columns 61-80).
"""
function header_line(io::IO, content::AbstractString, label::AbstractString)
    println(io, rpad(content, 60), label)
end

const SYSTEM_NAMES = Dict(
    'G' => "GPS",
    'R' => "GLONASS",
    'E' => "GALILEO",
    'C' => "BDS",
    'J' => "QZSS",
    'I' => "NavIC",
    'S' => "SBAS",
)

"""
    check_satellite_system(sys) -> Char

Return the satellite system character `sys`, or throw an `ArgumentError`
if it does not name a RINEX constellation.
"""
check_satellite_system(sys::Char) =
    haskey(SYSTEM_NAMES, sys) ? sys :
    throw(ArgumentError("Unknown satellite system character '$sys'"))

"""
    system_identification(systems) -> String

The satellite-system field of the `RINEX VERSION / TYPE` record, derived
from the set of system characters contained in the file. A single
character names its constellation; anything else - several systems, or a
file that is not pinned to one - is identified as mixed. Every character
is checked, also in a mixed file where none of them reaches the record.
"""
function system_identification(systems)
    foreach(check_satellite_system, systems)
    length(systems) == 1 || return "M: MIXED"
    sys = only(systems)
    string(sys, ": ", SYSTEM_NAMES[sys])
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
    time_system(systems) -> String

Time system of the epochs of an observation file containing `systems`, for
the `TIME OF FIRST OBS` record. A single-constellation file is written in
that constellation's time system; a file carrying several constellations
uses GPS time, as RINEX prescribes for mixed files.
"""
function time_system(systems)
    length(systems) == 1 || return "GPS"
    TIME_SYSTEMS[check_satellite_system(only(systems))]
end

function version_type_line(io::IO, file_type::AbstractString, systems)
    content =
        rpad(@sprintf("%9.2f", RINEX_VERSION), 20) *
        rpad(file_type, 20) *
        system_identification(systems)
    header_line(io, content, "RINEX VERSION / TYPE")
end

function program_line(io::IO, program, run_by)
    date = Dates.format(now(UTC), "yyyymmdd HHMMSS") * " UTC"
    content = rpad(program, 20) * rpad(run_by, 20) * date
    header_line(io, content, "PGM / RUN BY / DATE")
end

satellite_id(system::Char, prn::Integer) = string(system, lpad(prn, 2, '0'))

"""
    add_satellite_id!(record, system, prn)

Append the three-column satellite identification that opens a data record.
A satellite number outside 1-99 is rejected: it would not fit its two
columns and shift the whole record.
"""
function add_satellite_id!(record::RecordBuffer, system::Char, prn::Integer)
    0 < prn < 100 || throw(
        ArgumentError(
            "Satellite number $prn of system '$system' does not fit the two columns " *
            "of a RINEX satellite identification, which holds 1-99",
        ),
    )
    add_char!(record, system)
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

Whether `value` rendered with `digits` decimals fits `width` columns. A
value that does not fit overflows its field and shifts every field behind
it on the line, which a fixed-column parser cannot detect - so the writers
reject it instead of corrupting the record. `NaN` and `Inf` do not fit
either: they render in the right width, and a parser reads them back as a
measurement that was never made.
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
columns: a sign if the value is negative, the leading digit, the point, the
decimals, `E`, the exponent sign and the exponent digits - of which `Printf`
writes two even for a one-digit exponent. A three-digit exponent therefore
overflows an `E19.12` field, but only for a negative value: `-1e-100` takes
20 columns where `1e-100` takes 19. `NaN` and `Inf` do not fit either, for
the reason given at [`fits_fixed_field`](@ref).
"""
function fits_scientific_field(value::Float64, digits::Int, width::Int)
    isfinite(value) || return false
    exponent = iszero(value) ? 0 : floor(Int, log10(abs(value)))
    # Rounding the mantissa can carry into the exponent, and 9.9999999999996e99
    # reaches the file as 1.000000000000E+100.
    round(abs(value) / exp10(exponent); digits) >= 10 && (exponent += 1)
    signbit(value) + 4 + digits + max(2, ndigits(exponent)) <= width
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
    leap_seconds_content(leap_seconds) -> String

Content of the `LEAP SECONDS` header record. A plain `Int` fills only the
current leap-second count; an `NTuple{4,Int}` additionally fills the
future/past count ΔtLSF and the week and day number of the leap-second
event, which some parsers require.
"""
leap_seconds_content(leap_seconds::Int) = lpad(leap_seconds, 6)
leap_seconds_content(leap_seconds::NTuple{4,Int}) = join(lpad(x, 6) for x in leap_seconds)

"""
    epoch_seconds(time, fractional_second) -> Float64

Seconds within the minute of a record epoch, including sub-millisecond
`fractional_second` that `DateTime` cannot carry.
"""
epoch_seconds(time::DateTime, fractional_second) =
    second(time) + millisecond(time) / 1000 + fractional_second
