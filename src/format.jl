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
