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
"""
Base.@kwdef mutable struct RinexNavHeader
    program::String = "RINEX.jl"
    run_by::String = ""
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
    version_type_line(io, "N: GNSS NAV DATA", ('G',))
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
    write_ephemeris!(writer::RinexNavWriter, eph::GPSEphemeris) -> Bool

Append one ephemeris record, writing the file header first if necessary.
Returns whether the record was written (`false` for an ephemeris that was
already written before).
"""
function write_ephemeris!(writer::RinexNavWriter, eph::GPSEphemeris)
    key = (system(eph), eph.prn, eph.iodc, eph.toe)
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
    println(io, join(Printf.format(FMT_E19_12, v) for v in (eph.af0, eph.af1, eph.af2)))
    broadcast_orbit_line(io, eph.iode, eph.crs, eph.deltan, eph.m0)
    broadcast_orbit_line(io, eph.cuc, eph.e, eph.cus, eph.sqrt_a)
    broadcast_orbit_line(io, eph.toe, eph.cic, eph.omega0, eph.cis)
    broadcast_orbit_line(io, eph.i0, eph.crc, eph.omega, eph.omegadot)
    broadcast_orbit_line(io, eph.idot, eph.codes_on_l2, eph.week, eph.l2p_data_flag)
    broadcast_orbit_line(io, eph.sv_accuracy, eph.sv_health, eph.tgd, eph.iodc)
    broadcast_orbit_line(io, eph.transmission_time, eph.fit_interval)
    push!(writer.written, key)
    true
end
