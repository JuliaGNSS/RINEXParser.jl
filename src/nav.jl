"""
    IonosphericCorrection(type, parameters; time_mark = nothing, sv_id = nothing)

Ionospheric correction header record, e.g. Klobuchar parameters as
`IonosphericCorrection("GPSA", (α0, α1, α2, α3))` and
`IonosphericCorrection("GPSB", (β0, β1, β2, β3))`.

`time_mark` and `sv_id` say when the parameters were transmitted and by
which satellite. The mark is the hour of the day of the transmission time as
a letter, `'A'` for 00h-01h through `'X'` for 23h-24h. RINEX 3.05 Table A5
makes both **mandatory for BDS** - a constellation broadcasting several sets
a day, whose readers need to tell them apart - and optional elsewhere, so a
`"BDSA"` or `"BDSB"` record without them is rejected.
"""
struct IonosphericCorrection
    type::String
    parameters::NTuple{4,Float64}
    time_mark::Union{Nothing,Char}
    sv_id::Union{Nothing,Int}
    function IonosphericCorrection(type, parameters, time_mark, sv_id)
        type = String(type)
        if !isnothing(time_mark)
            time_mark in 'A':'X' || throw(
                ArgumentError(
                    "The time mark of an ionospheric correction is the hour of the " *
                    "day of its transmission time as 'A' (00h-01h) to 'X' " *
                    "(23h-24h), not '$time_mark'",
                ),
            )
        end
        if !isnothing(sv_id)
            0 < sv_id < 100 || throw(
                ArgumentError(
                    "The satellite that transmitted an ionospheric correction is " *
                    "given by its number, which holds 1-99, not $sv_id",
                ),
            )
        end
        if startswith(type, "BDS") && (isnothing(time_mark) || isnothing(sv_id))
            throw(
                ArgumentError(
                    "A BDS ionospheric correction carries the time mark and the " *
                    "satellite number of its transmission, which RINEX 3.05 makes " *
                    "mandatory for BDS; pass time_mark and sv_id",
                ),
            )
        end
        new(type, NTuple{4,Float64}(parameters), time_mark, sv_id)
    end
end
IonosphericCorrection(type, parameters; time_mark = nothing, sv_id = nothing) =
    IonosphericCorrection(type, parameters, time_mark, sv_id)

"""
    TimeSystemCorrection(type, a0, a1, reference_time, reference_week)

Time system correction header record, e.g. GPS-to-UTC as
`TimeSystemCorrection("GPUT", a0, a1, t_ot, week)`.
"""
struct TimeSystemCorrection
    type::String
    a0::Float64
    a1::Float64
    reference_time::Int
    reference_week::Int
end

"""
    RinexNavHeader(; kwargs...)

Header of a RINEX 3.05 navigation file. The corrections and leap seconds
are decoded from the navigation message, so they may become available only
after the writer is created. Assigning to `writer.header` replaces it any
time before the first [`write_ephemeris!`](@ref) call writes it out.

`satellite_system` is the system character of a single-constellation file
(e.g. `'G'`); leave it as `nothing` for a mixed navigation file that may
carry ephemerides of several constellations.
"""
Base.@kwdef mutable struct RinexNavHeader
    program::String = "RINEXParser.jl"
    run_by::String = ""
    satellite_system::Union{Nothing,Char} = nothing
    ionospheric_corrections::Vector{IonosphericCorrection} = IonosphericCorrection[]
    time_system_corrections::Vector{TimeSystemCorrection} = TimeSystemCorrection[]
    leap_seconds::Union{Nothing,LeapSeconds} = nothing
end

"""
    GPSEphemeris(; kwargs...)

One GPS LNAV broadcast ephemeris in the units RINEX expects (semicircle
angles already converted to radians, `sqrt_a` in `√m`, times in seconds of
GPS week). Field names follow the RINEX 3.05 GPS navigation record
(Table A6).
"""
Base.@kwdef struct GPSEphemeris
    prn::Int
    toc::DateTime
    af0::Float64
    af1::Float64
    af2::Float64
    iode::Float64
    crs::Float64
    deltan::Float64
    m0::Float64
    cuc::Float64
    e::Float64
    cus::Float64
    sqrt_a::Float64
    toe::Float64
    cic::Float64
    omega0::Float64
    cis::Float64
    i0::Float64
    crc::Float64
    omega::Float64
    omegadot::Float64
    idot::Float64
    codes_on_l2::Float64 = 0.0
    week::Float64
    l2p_data_flag::Float64 = 0.0
    sv_accuracy::Float64
    sv_health::Float64
    tgd::Float64
    iodc::Float64
    transmission_time::Float64
    fit_interval::Float64 = 4.0
end

system(::GPSEphemeris) = 'G'
# `toe` is a second of the week and `iodc` a 10-bit counter, so neither
# separates two ephemerides of different weeks on its own: the week belongs
# in the key, or a record would be dropped as a repeat of one a week older.
dedupe_key(eph::GPSEphemeris) = (system(eph), eph.prn, eph.iodc, eph.week, eph.toe)
orbit_lines(eph::GPSEphemeris) = (
    (eph.iode, eph.crs, eph.deltan, eph.m0),
    (eph.cuc, eph.e, eph.cus, eph.sqrt_a),
    (eph.toe, eph.cic, eph.omega0, eph.cis),
    (eph.i0, eph.crc, eph.omega, eph.omegadot),
    (eph.idot, eph.codes_on_l2, eph.week, eph.l2p_data_flag),
    (eph.sv_accuracy, eph.sv_health, eph.tgd, eph.iodc),
    (eph.transmission_time, eph.fit_interval),
)

"""
    GalileoEphemeris(; kwargs...)

One Galileo I/NAV or F/NAV broadcast ephemeris in the units RINEX expects
(angles in radians, `sqrt_a` in `√m`, times in seconds of Galileo week).
Field names follow the RINEX 3.05 Galileo navigation record (Table A8).

`data_sources` encodes the navigation message source and clock reference
(bit field, Table A8) and `sv_health` packs the per-signal validity and
health bits; both are assembled by
[`galileo_data_sources`](@ref) and [`galileo_sv_health`](@ref). The default
`data_sources = 513` is an I/NAV message from E1-B with E5b/E1 clock
parameters. `sisa` is the signal-in-space accuracy in meters, and
`bgd_e5a_e1`/`bgd_e5b_e1` are the broadcast group delays in seconds.

`week` follows the RINEX convention of a continuous week number aligned
with the GPS week, which is the 12-bit GST week of the navigation message
plus 1024 (the Galileo epoch falls into GPS week 1024).
"""
Base.@kwdef struct GalileoEphemeris
    prn::Int
    toc::DateTime
    af0::Float64
    af1::Float64
    af2::Float64
    iodnav::Float64
    crs::Float64
    deltan::Float64
    m0::Float64
    cuc::Float64
    e::Float64
    cus::Float64
    sqrt_a::Float64
    toe::Float64
    cic::Float64
    omega0::Float64
    cis::Float64
    i0::Float64
    crc::Float64
    omega::Float64
    omegadot::Float64
    idot::Float64
    data_sources::Float64 = 513.0
    week::Float64
    sisa::Float64
    sv_health::Float64
    bgd_e5a_e1::Float64
    bgd_e5b_e1::Float64
    transmission_time::Float64
end

"""
    galileo_data_sources(; inav_e1b = false, fnav_e5a = false, inav_e5b = false,
                           clock_e5a_e1 = false, clock_e5b_e1 = false) -> Float64

The `data_sources` bit field of a [`GalileoEphemeris`](@ref) (RINEX 3.05
Table A8), assembled from the navigation messages the record was decoded
from and the signal pair its clock parameters, `toc` and `sisa` refer to.

At least one message source is required, and exactly one clock reference:
the two Galileo services publish separate clock corrections, so a record
carries either the E5a/E1 or the E5b/E1 set. The two records a Galileo
receiver writes are

    galileo_data_sources(; inav_e1b = true, clock_e5b_e1 = true)  # 513, I/NAV
    galileo_data_sources(; fnav_e5a = true, clock_e5a_e1 = true)  # 258, F/NAV

and an I/NAV record decoded from both of its carriers sets `inav_e1b` and
`inav_e5b` together. All three sources at once are rejected: I/NAV and F/NAV
carry different information, so a record cannot come from both.
"""
function galileo_data_sources(;
    inav_e1b::Bool = false,
    fnav_e5a::Bool = false,
    inav_e5b::Bool = false,
    clock_e5a_e1::Bool = false,
    clock_e5b_e1::Bool = false,
)
    inav_e1b ||
        fnav_e5a ||
        inav_e5b ||
        throw(
            ArgumentError(
                "A Galileo ephemeris needs at least one navigation message source: " *
                "inav_e1b, fnav_e5a or inav_e5b",
            ),
        )
    inav_e1b &&
        fnav_e5a &&
        inav_e5b &&
        throw(
            ArgumentError(
                "The data sources of a Galileo ephemeris cannot name all three " *
                "messages: I/NAV and F/NAV carry different information, so a record " *
                "decoded from both is not one record (RINEX 3.05 Table A8)",
            ),
        )
    clock_e5a_e1 == clock_e5b_e1 && throw(
        ArgumentError(
            "A Galileo ephemeris carries the clock parameters of exactly one signal " *
            "pair: set either clock_e5a_e1 (F/NAV) or clock_e5b_e1 (I/NAV)",
        ),
    )
    bits =
        inav_e1b << 0 | fnav_e5a << 1 | inav_e5b << 2 | clock_e5a_e1 << 8 |
        clock_e5b_e1 << 9
    Float64(bits)
end

"""
    galileo_sv_health(; e1b_dvs = 0, e1b_hs = 0, e5a_dvs = 0, e5a_hs = 0,
                        e5b_dvs = 0, e5b_hs = 0) -> Float64

The `sv_health` bit field of a [`GalileoEphemeris`](@ref) (RINEX 3.05 Table
A8), packed from the data validity status (`dvs`, 0 or 1) and health
status (`hs`, 0-3) of each signal as they are broadcast in the navigation
message. `galileo_sv_health()` is a satellite healthy on every signal.
"""
function galileo_sv_health(;
    e1b_dvs::Integer = 0,
    e1b_hs::Integer = 0,
    e5a_dvs::Integer = 0,
    e5a_hs::Integer = 0,
    e5b_dvs::Integer = 0,
    e5b_hs::Integer = 0,
)
    bits =
        check_health_field(e1b_dvs, "e1b_dvs", 1) << 0 |
        check_health_field(e1b_hs, "e1b_hs", 3) << 1 |
        check_health_field(e5a_dvs, "e5a_dvs", 1) << 3 |
        check_health_field(e5a_hs, "e5a_hs", 3) << 4 |
        check_health_field(e5b_dvs, "e5b_dvs", 1) << 6 |
        check_health_field(e5b_hs, "e5b_hs", 3) << 7
    Float64(bits)
end

check_health_field(value::Integer, name, largest) =
    0 <= value <= largest ? Int(value) :
    throw(ArgumentError("Health field $name is $value, but it holds 0-$largest"))

system(::GalileoEphemeris) = 'E'
# I/NAV and F/NAV broadcast the same orbit for one IODnav but different
# clock parameters and group delays, so RINEX 3.05 keeps them as separate
# records: the message source is part of the record identity.
dedupe_key(eph::GalileoEphemeris) =
    (system(eph), eph.prn, eph.iodnav, eph.week, eph.toe, eph.data_sources)
orbit_lines(eph::GalileoEphemeris) = (
    (eph.iodnav, eph.crs, eph.deltan, eph.m0),
    (eph.cuc, eph.e, eph.cus, eph.sqrt_a),
    (eph.toe, eph.cic, eph.omega0, eph.cis),
    (eph.i0, eph.crc, eph.omega, eph.omegadot),
    (eph.idot, eph.data_sources, eph.week),
    (eph.sisa, eph.sv_health, eph.bgd_e5a_e1, eph.bgd_e5b_e1),
    (eph.transmission_time,),
)

"""
    BeiDouEphemeris(; kwargs...)

One BeiDou D1/D2 broadcast ephemeris in the units RINEX expects (angles in
radians, `sqrt_a` in `√m`, times in seconds of BDT week). Field names follow
the RINEX 3.05 BDS navigation record (Table A14).

`aode` and `aodc` are the age of the ephemeris and of the clock data, and
`sath1` is the autonomous satellite health flag (0 healthy). `tgd1_b1_b3`
and `tgd2_b2_b3` are the two broadcast group delays in seconds.

Unlike Galileo, whose `week` RINEX aligns with the GPS week, `toc`, `toe`,
`week` and `transmission_time` of a BDS record are in BeiDou time: `week` is
the continuous BDT week counted from the BDT epoch (2006-01-01) - the
broadcast 13-bit week plus 8192 per roll-over - and the seconds of week are
BDT seconds, 14 s behind GPS time.

`transmission_time` is written as it is given and has to refer to `week`,
so a message received after the week of the ephemeris rolled over is passed
in adjusted by ±604800 s. The spec's encoding of a transmission time that is
not known is `0.999999999999e9`.
"""
Base.@kwdef struct BeiDouEphemeris
    prn::Int
    toc::DateTime
    af0::Float64
    af1::Float64
    af2::Float64
    aode::Float64
    crs::Float64
    deltan::Float64
    m0::Float64
    cuc::Float64
    e::Float64
    cus::Float64
    sqrt_a::Float64
    toe::Float64
    cic::Float64
    omega0::Float64
    cis::Float64
    i0::Float64
    crc::Float64
    omega::Float64
    omegadot::Float64
    idot::Float64
    week::Float64
    sv_accuracy::Float64
    sath1::Float64
    tgd1_b1_b3::Float64
    tgd2_b2_b3::Float64
    transmission_time::Float64
    aodc::Float64
end

system(::BeiDouEphemeris) = 'C'
# `aode` counts the hours the parameter set has been in use, so it grows
# while the ephemeris stays the same and cannot identify the record; the
# reference times do, as BeiDou issues a new `toe` with every new set.
dedupe_key(eph::BeiDouEphemeris) = (system(eph), eph.prn, eph.toc, eph.toe)
# Broadcast orbit line 5 holds a spare between IDOT and the week, written
# blank as section 6.4 asks and the example of Table A15 shows; the spares
# trailing the week and the age of the clock data end their line and are
# left off, as Galileo's is.
orbit_lines(eph::BeiDouEphemeris) = (
    (eph.aode, eph.crs, eph.deltan, eph.m0),
    (eph.cuc, eph.e, eph.cus, eph.sqrt_a),
    (eph.toe, eph.cic, eph.omega0, eph.cis),
    (eph.i0, eph.crc, eph.omega, eph.omegadot),
    (eph.idot, nothing, eph.week),
    (eph.sv_accuracy, eph.sath1, eph.tgd1_b1_b3, eph.tgd2_b2_b3),
    (eph.transmission_time, eph.aodc),
)

# The clock polynomial occupies the same three fields in every navigation
# record, so an ephemeris type gets it for free.
clock_coefficients(eph) = (eph.af0, eph.af1, eph.af2)

"""
    RinexNavWriter(target, header::RinexNavHeader)

Streaming writer for a RINEX 3.05 navigation file. `target` is a path or
an `IO`. The header is written lazily on the first
[`write_ephemeris!`](@ref). Ephemerides repeating a record that was
already written - same satellite, issue of data, time of ephemeris, and
for Galileo the navigation message source - are skipped, so it is safe to
forward every decoded subframe. A BeiDou record is identified by its
reference times instead of its issue of data, whose age counter grows
while the ephemeris stays the same. Close the writer (or use the do-block
form) to flush the file.
"""
mutable struct RinexNavWriter{T<:IO}
    io::T
    header::RinexNavHeader
    header_written::Bool
    owns_io::Bool
    # Keys come from `dedupe_key`, whose shape differs per ephemeris type.
    written::Set{Tuple}
    record::RecordBuffer
end
function RinexNavWriter(io::IO, header::RinexNavHeader = RinexNavHeader())
    check_nav_header(header)
    RinexNavWriter(io, header, false, false, Set{Tuple}(), RecordBuffer())
end
function RinexNavWriter(path::AbstractString, header::RinexNavHeader = RinexNavHeader())
    check_nav_header(header)
    RinexNavWriter(open(path, "w"), header, false, true, Set{Tuple}(), RecordBuffer())
end

function RinexNavWriter(f::Function, target, header::RinexNavHeader = RinexNavHeader())
    writer = RinexNavWriter(target, header)
    try
        f(writer)
    finally
        close(writer)
    end
end

# Checked when the writer is created, not only when the header is written
# out: the lazy header write happens inside `close`, where an exception
# would leak the file handle and mask the exception of a do-block body.
function check_nav_header(header::RinexNavHeader)
    isnothing(header.satellite_system) || check_satellite_system(header.satellite_system)
    check_header_field(header.program, 20, "The program of the header")
    check_header_field(header.run_by, 20, "The agency running the program")
    for corr in header.ionospheric_corrections
        check_header_field(corr.type, 4, "The type of an ionospheric correction")
    end
    for corr in header.time_system_corrections
        check_header_field(corr.type, 4, "The type of a time system correction")
    end
    nothing
end

function Base.close(writer::RinexNavWriter)
    try
        writer.header_written || write_nav_header(writer)
    finally
        writer.owns_io ? close(writer.io) : flush(writer.io)
    end
    nothing
end

function write_nav_header(writer::RinexNavWriter)
    io = writer.io
    header = writer.header
    # As in the observation header: the fields stay assignable until the
    # header is written, so they are checked again where they are used.
    check_nav_header(header)
    systems = isnothing(header.satellite_system) ? () : (header.satellite_system,)
    version_type_line(io, "N: GNSS NAV DATA", systems)
    program_line(io, header.program, header.run_by)
    for corr in header.ionospheric_corrections
        content =
            rpad(corr.type, 4) *
            " " *
            join(Printf.format(FMT_E12_4, p) for p in corr.parameters) *
            # `1X,A1` and `1X,I2`, both blank where the record does not carry
            # them - which only a BDS record cannot be.
            (isnothing(corr.time_mark) ? " "^2 : " " * corr.time_mark) *
            (isnothing(corr.sv_id) ? "" : " " * lpad(corr.sv_id, 2))
        header_line(io, content, "IONOSPHERIC CORR")
    end
    for corr in header.time_system_corrections
        content =
            rpad(corr.type, 4) *
            " " *
            Printf.format(FMT_E17_10, corr.a0) *
            Printf.format(FMT_E16_9, corr.a1) *
            lpad(corr.reference_time, 7) *
            lpad(corr.reference_week, 5)
        header_line(io, content, "TIME SYSTEM CORR")
    end
    if !isnothing(header.leap_seconds)
        header_line(io, leap_seconds_content(header.leap_seconds), "LEAP SECONDS")
    end
    header_line(io, "", "END OF HEADER")
    writer.header_written = true
end

# Every navigation record field is 19 columns of E19.12, and every value is
# checked against them like an observation is against its own field. Unlike
# an observation, an ephemeris field has no blank encoding that would mean
# "not available", so a value that is not finite can only be an upstream bug
# and is rejected instead of written as "NaN" into a numeric field. Only a
# spare - `nothing` - is blank, and it is the one thing not checked.
function add_orbit_values!(
    record::RecordBuffer,
    system::Char,
    prn::Integer,
    line_number::Int,
    values,
)
    for (i, value) in enumerate(values)
        # A spare the record has to keep a place for, because a value of the
        # line follows it. Section 6.4 asks for spares to be left blank, so
        # that a future version assigning them a meaning cannot be read out
        # of a zero that was never broadcast.
        if isnothing(value)
            add_blanks!(record, 19)
            continue
        end
        fits_scientific_field(value, 12, 19) ||
            ephemeris_field_error(system, prn, line_number, i, value)
        add_field!(record, FMT_E19_12, value)
    end
end

# Line 0 is the clock polynomial at the end of the record epoch line.
@noinline function ephemeris_field_error(system, prn, line_number, i, value)
    position =
        line_number == 0 ? "the clock polynomial" : "broadcast orbit line $line_number"
    reason =
        isfinite(value) ?
        "does not fit the 19 columns of an E19.12 field; the rest of the record " *
        "would be shifted out of alignment" :
        "is not finite, and a navigation record field has no encoding for a value " *
        "that is missing"
    throw(
        ArgumentError(
            "Field $i of $position of the ephemeris of satellite " *
            "$(satellite_id(system, prn)) is $value, which $reason",
        ),
    )
end

function broadcast_orbit_line(
    record::RecordBuffer,
    system::Char,
    prn::Integer,
    line_number::Int,
    values,
)
    add_blanks!(record, 4)
    add_orbit_values!(record, system, prn, line_number, values)
    end_line!(record)
end

"""
    write_ephemeris!(writer::RinexNavWriter, eph) -> Bool

Append one ephemeris record ([`GPSEphemeris`](@ref),
[`GalileoEphemeris`](@ref) or [`BeiDouEphemeris`](@ref)), writing the file
header first if necessary. Returns whether the record was written (`false`
for an ephemeris that was already written before). Throws an
`ArgumentError` if the header pins the file to a single constellation and
`eph` belongs to another one.

The whole record is checked before its first line is written, so an
ephemeris this rejects leaves the file as it was.

`eph` may be of any type implementing the ephemeris interface, so a
constellation this package does not know yet can be written by defining

  - `RINEXParser.system(eph)`: the RINEX satellite system character,
  - `RINEXParser.dedupe_key(eph)`: a tuple identifying the record, see
    [`RinexNavWriter`](@ref),
  - `RINEXParser.orbit_lines(eph)`: one tuple of at most four values per
    broadcast orbit line, in record order. Use `nothing` for a blank spare
    field. Any `nothing` returned by this method writes a blank, even when
    the field normally requires a value,
  - `RINEXParser.clock_coefficients(eph)`: the three clock polynomial
    coefficients, which default to the `af0`, `af1` and `af2` fields,

The record must also expose `prn` (satellite number) and `toc` (`DateTime`
in the constellation's RINEX time system) fields.
"""
function write_ephemeris!(writer::RinexNavWriter, eph)
    pinned = writer.header.satellite_system
    isnothing(pinned) ||
        pinned == system(eph) ||
        throw(
            ArgumentError(
                "Satellite $(satellite_id(system(eph), eph.prn)) does not belong to " *
                "system '$pinned' of the single-system header; leave the header's " *
                "satellite_system as nothing to write a mixed navigation file",
            ),
        )
    key = dedupe_key(eph)
    key in writer.written && return false
    sys = system(eph)
    prn = eph.prn
    t = eph.toc
    # The eight lines of the record are assembled in the buffer, and a value
    # a field cannot hold throws while they are: nothing has reached the file
    # at that point, so a rejected ephemeris leaves it as it was. Writing the
    # lines as they were formatted used to leave a fragment behind that the
    # records following it could not be told apart from.
    record = start_record!(writer.record)
    add_satellite_id!(record, sys, prn)
    add_char!(record, ' ')
    add_epoch_date!(record, t)
    add_char!(record, ' ')
    add_integer!(record, second(t), 2, UInt8('0'))
    add_orbit_values!(record, sys, prn, 0, clock_coefficients(eph))
    end_line!(record)
    for (line_number, line) in enumerate(orbit_lines(eph))
        broadcast_orbit_line(record, sys, prn, line_number, line)
    end
    writer.header_written || write_nav_header(writer)
    flush_record!(writer.io, record)
    push!(writer.written, key)
    true
end
