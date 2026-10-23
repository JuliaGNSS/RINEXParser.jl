"""
    IonosphericCorrection(type, parameters; time_mark = nothing, sv_id = nothing)

Ionospheric correction header record, e.g. Klobuchar parameters as
`IonosphericCorrection("GPSA", (α0, α1, α2, α3))` and
`IonosphericCorrection("GPSB", (β0, β1, β2, β3))`. `type` is one of the
correction types of RINEX 3.05 Table A5: `"GAL"`, `"GPSA"`, `"GPSB"`,
`"QZSA"`, `"QZSB"`, `"BDSA"`, `"BDSB"`, `"IRNA"` or `"IRNB"`.

Galileo's NeQuick record carries three coefficients, `(ai0, ai1, ai2)`, and
its fourth field is a spare written blank. A fourth value of zero, passed
for that spare, is accepted and dropped.

`time_mark` and `sv_id` say when the parameters were transmitted and by
which satellite. The mark is the hour of the day of the transmission time as
a letter, `'A'` for 00h-01h through `'X'` for 23h-24h. RINEX 3.05 Table A5
makes both **mandatory for BDS** - a constellation broadcasting several sets
a day, whose readers need to tell them apart - and optional elsewhere, so a
`"BDSA"` or `"BDSB"` record without them is rejected.
"""
struct IonosphericCorrection
    type::String
    parameters::Union{NTuple{3,Float64},NTuple{4,Float64}}
    time_mark::Union{Nothing,Char}
    sv_id::Union{Nothing,Int}
    function IonosphericCorrection(type, parameters, time_mark, sv_id)
        type = String(type)
        type in IONOSPHERIC_CORRECTION_TYPES || throw(
            ArgumentError(
                "\"$type\" is not an ionospheric correction type; RINEX 3.05 " *
                "defines $(join(IONOSPHERIC_CORRECTION_TYPES, ", "))",
            ),
        )
        parameters = ionospheric_parameters(type, Tuple(parameters))
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
        new(type, parameters, time_mark, sv_id)
    end
end

const IONOSPHERIC_CORRECTION_TYPES =
    ("GAL", "GPSA", "GPSB", "QZSA", "QZSB", "BDSA", "BDSB", "IRNA", "IRNB")

function ionospheric_parameters(type, parameters::Tuple)
    if type == "GAL"
        (length(parameters) == 4 && iszero(last(parameters))) &&
            return NTuple{3,Float64}(parameters[1:3])
        length(parameters) == 3 || throw(
            ArgumentError(
                "A GAL ionospheric correction carries the three coefficients " *
                "ai0, ai1 and ai2, not $(length(parameters)) values",
            ),
        )
        return NTuple{3,Float64}(parameters)
    end
    length(parameters) == 4 || throw(
        ArgumentError(
            "A $type ionospheric correction carries four parameters, not " *
            "$(length(parameters))",
        ),
    )
    NTuple{4,Float64}(parameters)
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
after the writer is created. [`set_header!`](@ref) completes or replaces it
any time before the first [`write_ephemeris!`](@ref) call writes it out, and
[`add_header_records!`](@ref) collects them from decoded navigation messages.

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
    iode::Int
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
    codes_on_l2::Int = 0
    week::Int
    l2p_data_flag::Int = 0
    sv_accuracy::Float64
    sv_health::Int
    tgd::Float64
    iodc::Int
    transmission_time::Float64
    fit_interval::Float64 = 4.0
end

satellite_system(::GPSEphemeris) = 'G'
dedupe_key(eph::GPSEphemeris) = record_contents(eph, (:transmission_time,))
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
    iodnav::Int
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
    data_sources::Int = 513
    week::Int
    sisa::Float64
    sv_health::Int
    bgd_e5a_e1::Float64
    bgd_e5b_e1::Float64
    transmission_time::Float64
end

"""
    galileo_data_sources(; inav_e1b = false, fnav_e5a = false, inav_e5b = false) -> Int

The `data_sources` bit field of a [`GalileoEphemeris`](@ref) (RINEX 3.05
Table A8), assembled from the navigation messages the record was decoded
from.

A record comes from one message type, and its clock parameters, `toc` and
`sisa` are the ones that message broadcasts (section 5.4.3): F/NAV carries
the E5a/E1 clock and I/NAV the E5b/E1 clock, so the clock bits (8 and 9)
follow from the source and are set here. A receiver decoding both messages
writes one record of each:

    galileo_data_sources(; inav_e1b = true)  # 513, I/NAV
    galileo_data_sources(; fnav_e5a = true)  # 258, F/NAV

An I/NAV record merged from both of its carriers sets `inav_e1b` and
`inav_e5b` together. A source mixing F/NAV and I/NAV is rejected.
"""
function galileo_data_sources(;
    inav_e1b::Bool = false,
    fnav_e5a::Bool = false,
    inav_e5b::Bool = false,
)
    inav = inav_e1b || inav_e5b
    (fnav_e5a || inav) || throw(
        ArgumentError(
            "A Galileo ephemeris needs at least one navigation message source: " *
            "inav_e1b, fnav_e5a or inav_e5b",
        ),
    )
    (fnav_e5a && inav) && throw(
        ArgumentError(
            "A Galileo ephemeris comes from F/NAV or from I/NAV, which RINEX 3.05 " *
            "writes as separate records; write one record per message",
        ),
    )
    clock_e5a_e1 = fnav_e5a
    clock_e5b_e1 = inav
    inav_e1b << 0 | fnav_e5a << 1 | inav_e5b << 2 | clock_e5a_e1 << 8 | clock_e5b_e1 << 9
end

"""
    galileo_sv_health(; e1b_dvs = 0, e1b_hs = 0, e5a_dvs = 0, e5a_hs = 0,
                        e5b_dvs = 0, e5b_hs = 0) -> Int

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
    bits
end

check_health_field(value::Integer, name, largest) =
    0 <= value <= largest ? Int(value) :
    throw(ArgumentError("Health field $name is $value, but it holds 0-$largest"))

satellite_system(::GalileoEphemeris) = 'E'
dedupe_key(eph::GalileoEphemeris) = record_contents(eph, (:transmission_time,))
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
    aode::Int
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
    week::Int
    sv_accuracy::Float64
    sath1::Int
    tgd1_b1_b3::Float64
    tgd2_b2_b3::Float64
    transmission_time::Float64
    aodc::Int
end

satellite_system(::BeiDouEphemeris) = 'C'
# The ages of the ephemeris and clock data count up while the parameter set
# stays the same, so like the transmission time they do not change a record.
dedupe_key(eph::BeiDouEphemeris) = record_contents(eph, (:transmission_time, :aode, :aodc))
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
    record_contents(eph, ignored) -> Tuple

Every field of `eph` except the `ignored` ones, as the key of a record.
Section 5.4.3 asks for a new record whenever the contents change, and the
health, accuracy or data validity status can change without the issue of
data: a key made of the identifying fields alone would drop that update.
The transmission time is always ignored, since every broadcast of the same
record carries a new one.
"""
record_contents(eph, ignored::Tuple{Vararg{Symbol}}) = (
    satellite_system(eph),
    (getfield(eph, f) for f in fieldnames(typeof(eph)) if !(f in ignored))...,
)

"""
    RinexNavWriter(target, header::RinexNavHeader = RinexNavHeader(); overflow = :throw)

Streaming writer for a RINEX 3.05 navigation file. `target` is a path, an
`IO`, or a [`RinexDirectory`](@ref) that names the file by the long
filename convention when it is closed. The header is written lazily on the
first [`write_ephemeris!`](@ref), and [`set_header!`](@ref) replaces it until
then. An ephemeris repeating a record that was
already written - the same contents but for the transmission time, and for
BeiDou the ages of the data - is skipped, so it is safe to forward every
decoded subframe; one whose health, accuracy or any other value changed
under the same issue of data is a new record, as section 5.4.3 asks. Close
the writer (or use the do-block form) to flush the file.

`overflow` says what becomes of an ephemeris with a value that does not fit
its E19.12 field, or is not finite - which a navigation record, unlike an
observation, has no blank encoding for. `:throw` rejects it with an
`ArgumentError`. `:skip` leaves the record out, makes
[`write_ephemeris!`](@ref) return `false`, and warns once per record, so
that a receiver forwarding every decoded message keeps its output when one
message was decoded wrong. Either way the file stays as it was: the whole
record is checked before its first line is written.
"""
mutable struct RinexNavWriter{T<:IO}
    io::T
    header::RinexNavHeader
    header_written::Bool
    owns_io::Bool
    # Keys come from `dedupe_key`, whose shape differs per ephemeris type.
    written::Set{Tuple}
    overflow::Symbol
    # The `dedupe_key`s of the records `overflow = :skip` left out, so that
    # each is warned about once however often it is offered again.
    skipped::Set{Tuple}
    record::RecordBuffer
    # As in `RinexObsWriter`.
    path::Union{Nothing,String}
    directory::Union{Nothing,RinexDirectory}
    # The toc of the first record, which a file to a `RinexDirectory` without
    # another start time is named after.
    first_toc::Union{Nothing,DateTime}
end
function RinexNavWriter(
    io::IO,
    header::RinexNavHeader = RinexNavHeader();
    overflow::Symbol = :throw,
)
    check_nav_writer(header, overflow)
    nav_writer(io, header, overflow, false, nothing, nothing)
end
function RinexNavWriter(
    path::AbstractString,
    header::RinexNavHeader = RinexNavHeader();
    overflow::Symbol = :throw,
)
    check_nav_writer(header, overflow)
    nav_writer(open(path, "w"), header, overflow, true, String(path), nothing)
end
function RinexNavWriter(
    target::RinexDirectory,
    header::RinexNavHeader = RinexNavHeader();
    overflow::Symbol = :throw,
)
    (isnothing(target.session) || target.session isa RinexObsWriter) || throw(
        ArgumentError(
            "The session of a navigation file is the RinexObsWriter of its " *
            "observations, not a $(typeof(target.session))",
        ),
    )
    check_nav_writer(header, overflow)
    # Checked now rather than when the name is needed on `close`.
    file_name(header, target; fallback = DateTime(2000))
    path, io = open_temporary(target)
    nav_writer(io, header, overflow, true, path, target)
end

nav_writer(io, header, overflow, owns_io, path, directory) = RinexNavWriter(
    io,
    header,
    false,
    owns_io,
    Set{Tuple}(),
    overflow,
    Set{Tuple}(),
    RecordBuffer(),
    path,
    directory,
    nothing,
)

RinexNavWriter(
    f::Function,
    target,
    header::RinexNavHeader = RinexNavHeader();
    keywords...,
) = with_writer(f, RinexNavWriter(target, header; keywords...))

# Checked by every constructor before it opens a file, so that a writer it
# rejects leaves none behind.
function check_nav_writer(header, overflow)
    check_nav_header(header)
    overflow in (:throw, :skip) || throw(
        ArgumentError(
            "overflow is :throw to reject an ephemeris with a value that does not fit " *
            "its field or :skip to leave the record out, not :$overflow",
        ),
    )
    nothing
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
    had_records = writer.header_written
    try
        had_records || write_nav_header(writer)
    finally
        writer.owns_io ? close(writer.io) : flush(writer.io)
    end
    isnothing(writer.directory) ||
        (writer.path = name_file!(writer, had_records, writer.first_toc))
    writer.directory = nothing
    nothing
end

header_written(writer::RinexNavWriter) = writer.header_written

function set_header!(writer::RinexNavWriter, header::RinexNavHeader)
    check_header_unwritten(writer)
    check_nav_header(header)
    writer.header = header
    writer
end

file_path(writer::RinexNavWriter) = writer.path

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
            # The spare fourth field of a GAL record.
            " "^(12 * (4 - length(corr.parameters))) *
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
#
# Returns `nothing`, or the `(line_number, field, value)` of the first value
# that does not fit, for `write_ephemeris!` to reject or skip the record by.
function add_orbit_values!(record::RecordBuffer, line_number::Int, values)
    # Counters and bit fields are integers, written as the floats of every
    # other field of the record.
    for (i, value) in enumerate(map(orbit_value, values))
        # A spare the record has to keep a place for, because a value of the
        # line follows it. Section 6.4 asks for spares to be left blank, so
        # that a future version assigning them a meaning cannot be read out
        # of a zero that was never broadcast.
        if isnothing(value)
            add_blanks!(record, 19)
            continue
        end
        fits_scientific_field(value, 12, 19) || return (line_number, i, value)
        add_field!(record, FMT_E19_12, value)
    end
    nothing
end

orbit_value(::Nothing) = nothing
orbit_value(value::Real) = Float64(value)

# Line 0 is the clock polynomial at the end of the record epoch line.
function ephemeris_field_problem(system, prn, (line_number, i, value))
    position =
        line_number == 0 ? "the clock polynomial" : "broadcast orbit line $line_number"
    reason =
        isfinite(value) ?
        "does not fit the 19 columns of an E19.12 field; the rest of the record " *
        "would be shifted out of alignment" :
        "is not finite, and a navigation record field has no encoding for a value " *
        "that is missing"
    "Field $i of $position of the ephemeris of satellite " *
    "$(satellite_id(system, prn)) is $value, which $reason"
end

function broadcast_orbit_line(record::RecordBuffer, line_number::Int, values)
    add_blanks!(record, 4)
    problem = add_orbit_values!(record, line_number, values)
    end_line!(record)
    problem
end

# Reject the record, or with `overflow = :skip` leave it out and say so once.
@noinline function reject_ephemeris(writer::RinexNavWriter, key, system, prn, field)
    problem = ephemeris_field_problem(system, prn, field)
    writer.overflow == :skip || throw(ArgumentError(problem))
    push!(writer.skipped, key)
    @warn "$problem, so the record is left out of the file"
    false
end

"""
    write_ephemeris!(writer::RinexNavWriter, eph) -> Bool

Append one ephemeris record ([`GPSEphemeris`](@ref),
[`GalileoEphemeris`](@ref) or [`BeiDouEphemeris`](@ref)), writing the file
header first if necessary. Returns whether the record was written: `false`
for an ephemeris that was already written before, and for one the writer's
`overflow = :skip` left out (see [`RinexNavWriter`](@ref)). Throws an
`ArgumentError` if the header pins the file to a single constellation and
`eph` belongs to another one.

The whole record is checked before its first line is written, so an
ephemeris this rejects leaves the file as it was.

`eph` may be of any type implementing the ephemeris interface, so a
constellation this package does not know yet can be written by defining

  - `RINEXParser.satellite_system(eph)`: the RINEX satellite system character,
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
        pinned == satellite_system(eph) ||
        throw(
            ArgumentError(
                "Satellite $(satellite_id(satellite_system(eph), eph.prn)) does not belong to " *
                "system '$pinned' of the single-system header; leave the header's " *
                "satellite_system as nothing to write a mixed navigation file",
            ),
        )
    key = dedupe_key(eph)
    (key in writer.written || key in writer.skipped) && return false
    sys = satellite_system(eph)
    prn = eph.prn
    t = eph.toc
    # The record epoch holds whole seconds (`I2`).
    iszero(millisecond(t)) || throw(
        ArgumentError(
            "The toc of $(satellite_id(sys, prn)) is $t, but the epoch of a " *
            "navigation record holds whole seconds",
        ),
    )
    # Assembled whole before it is written, so a rejected ephemeris leaves
    # the file as it was.
    record = start_record!(writer.record)
    add_satellite_id!(record, sys, prn)
    add_char!(record, ' ')
    add_epoch_date!(record, t)
    add_char!(record, ' ')
    add_integer!(record, second(t), 2, UInt8('0'))
    problem = add_orbit_values!(record, 0, clock_coefficients(eph))
    end_line!(record)
    for (line_number, line) in enumerate(orbit_lines(eph))
        isnothing(problem) || break
        problem = broadcast_orbit_line(record, line_number, line)
    end
    isnothing(problem) || return reject_ephemeris(writer, key, sys, prn, problem)
    writer.header_written || write_nav_header(writer)
    flush_record!(writer.io, record)
    push!(writer.written, key)
    isnothing(writer.first_toc) && (writer.first_toc = t)
    true
end
