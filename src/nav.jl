"""
    IonosphericCorrection(type, parameters)

Ionospheric correction header record, e.g. Klobuchar parameters as
`IonosphericCorrection("GPSA", (α0, α1, α2, α3))` and
`IonosphericCorrection("GPSB", (β0, β1, β2, β3))`.
"""
struct IonosphericCorrection
    type::String
    parameters::NTuple{4,Float64}
end

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
after the writer is created; the header can be replaced (`writer.header =
new_header`) any time before the first [`write_ephemeris!`](@ref) call
writes it out.

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
    leap_seconds::Union{Nothing,Int,NTuple{4,Int}} = nothing
end

"""
    GPSEphemeris(; kwargs...)

One GPS LNAV broadcast ephemeris in the units RINEX expects (semicircle
angles already converted to radians, `sqrt_a` in `√m`, times in seconds of
GPS week). Field names follow the RINEX 3.05 GPS navigation record
(Table A14).
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
dedupe_key(eph::GPSEphemeris) = (system(eph), eph.prn, eph.iodc, eph.toe)
clock_coefficients(eph::GPSEphemeris) = (eph.af0, eph.af1, eph.af2)
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
Field names follow the RINEX 3.05 Galileo navigation record (Table A15).

`data_sources` encodes the navigation message source and clock reference
(bit field, Table A15); the default `513` is an I/NAV message from E1-B
with E5b/E1 clock parameters. `sisa` is the signal-in-space accuracy in
meters, and `bgd_e5a_e1`/`bgd_e5b_e1` are the broadcast group delays in
seconds.
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

system(::GalileoEphemeris) = 'E'
dedupe_key(eph::GalileoEphemeris) = (system(eph), eph.prn, eph.iodnav, eph.toe)
clock_coefficients(eph::GalileoEphemeris) = (eph.af0, eph.af1, eph.af2)
orbit_lines(eph::GalileoEphemeris) = (
    (eph.iodnav, eph.crs, eph.deltan, eph.m0),
    (eph.cuc, eph.e, eph.cus, eph.sqrt_a),
    (eph.toe, eph.cic, eph.omega0, eph.cis),
    (eph.i0, eph.crc, eph.omega, eph.omegadot),
    (eph.idot, eph.data_sources, eph.week),
    (eph.sisa, eph.sv_health, eph.bgd_e5a_e1, eph.bgd_e5b_e1),
    (eph.transmission_time,),
)

const Ephemeris = Union{GPSEphemeris,GalileoEphemeris}

"""
    RinexNavWriter(target, header::RinexNavHeader)

Streaming writer for a RINEX 3.05 navigation file. `target` is a path or
an `IO`. The header is written lazily on the first
[`write_ephemeris!`](@ref). Repeated ephemerides (same satellite, IODC,
and time of ephemeris) are skipped, so it is safe to forward every decoded
subframe. Close the writer (or use the do-block form) to flush the file.
"""
mutable struct RinexNavWriter{T<:IO}
    io::T
    header::RinexNavHeader
    header_written::Bool
    owns_io::Bool
    written::Set{Tuple{Char,Int,Float64,Float64}}
end
RinexNavWriter(io::IO, header::RinexNavHeader = RinexNavHeader()) =
    RinexNavWriter(io, header, false, false, Set{Tuple{Char,Int,Float64,Float64}}())
RinexNavWriter(path::AbstractString, header::RinexNavHeader = RinexNavHeader()) =
    RinexNavWriter(open(path, "w"), header, false, true, Set{Tuple{Char,Int,Float64,Float64}}())

function RinexNavWriter(f::Function, target, header::RinexNavHeader = RinexNavHeader())
    writer = RinexNavWriter(target, header)
    try
        f(writer)
    finally
        close(writer)
    end
end

function Base.close(writer::RinexNavWriter)
    writer.header_written || write_nav_header(writer)
    writer.owns_io ? close(writer.io) : flush(writer.io)
    nothing
end

function write_nav_header(writer::RinexNavWriter)
    io = writer.io
    header = writer.header
    version_type_line(io, "N: GNSS NAV DATA", (something(header.satellite_system, 'M'),))
    program_line(io, header.program, header.run_by)
    for corr in header.ionospheric_corrections
        content = rpad(corr.type, 4) * " " *
                  join(Printf.format(FMT_E12_4, p) for p in corr.parameters)
        header_line(io, content, "IONOSPHERIC CORR")
    end
    for corr in header.time_system_corrections
        content = rpad(corr.type, 4) * " " *
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

function broadcast_orbit_line(io::IO, values...)
    println(io, " "^4, join(Printf.format(FMT_E19_12, v) for v in values))
end

"""
    write_ephemeris!(writer::RinexNavWriter, eph) -> Bool

Append one ephemeris record ([`GPSEphemeris`](@ref) or
[`GalileoEphemeris`](@ref)), writing the file header first if necessary.
Returns whether the record was written (`false` for an ephemeris that was
already written before).
"""
function write_ephemeris!(writer::RinexNavWriter, eph::Ephemeris)
    key = dedupe_key(eph)
    key in writer.written && return false
    writer.header_written || write_nav_header(writer)
    io = writer.io
    t = eph.toc
    print(
        io,
        satellite_id(system(eph), eph.prn), " ",
        lpad(year(t), 4), " ",
        lpad(month(t), 2, '0'), " ",
        lpad(day(t), 2, '0'), " ",
        lpad(hour(t), 2, '0'), " ",
        lpad(minute(t), 2, '0'), " ",
        lpad(second(t), 2, '0'),
    )
    println(io, join(Printf.format(FMT_E19_12, v) for v in clock_coefficients(eph)))
    for line in orbit_lines(eph)
        broadcast_orbit_line(io, line...)
    end
    push!(writer.written, key)
    true
end
