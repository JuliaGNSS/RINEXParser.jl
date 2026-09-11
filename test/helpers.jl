function written_lines(f, writer_type, args...)
    io = IOBuffer()
    writer_type(f, io, args...)
    readlines(seekstart(io))
end

label(line) = length(line) > 60 ? rstrip(line[61:end]) : ""
content(line) = rstrip(first(line, 60))

function modify(eph::T; kwargs...) where {T}
    fields = Dict{Symbol,Any}(f => getfield(eph, f) for f in fieldnames(T))
    merge!(fields, Dict(kwargs))
    T(; fields...)
end

body_lines(lines) = lines[(findfirst(l->label(l)=="END OF HEADER", lines)+1):end]

# A broadcast orbit line carries four values of 19 columns each, after the
# four leading blanks.
orbit_values(body, lines) =
    [parse(Float64, body[l][c:(c+18)]) for l in lines for c in (5, 24, 43, 62)]

gps_eph = GPSEphemeris(;
    prn = 13,
    toc = DateTime(2020, 1, 1, 2, 0, 0),
    af0 = -3.153673559427e-4,
    af1 = -1.000444171950e-11,
    af2 = 0.0,
    iode = 83.0,
    crs = -49.15625,
    deltan = 4.464114626131e-9,
    m0 = 2.909791674811,
    cuc = -2.428889274597e-6,
    e = 4.421935591381e-3,
    cus = 3.278255462646e-6,
    sqrt_a = 5.153687646866e3,
    toe = 266400.0,
    cic = -2.216547727585e-7,
    omega0 = 1.148673191606,
    cis = 1.955777406693e-7,
    i0 = 9.755690921935e-1,
    crc = 287.46875,
    omega = 8.130950284124e-1,
    omegadot = -8.087836629593e-9,
    idot = -5.03592332984e-10,
    week = 2086.0,
    sv_accuracy = 2.0,
    sv_health = 0.0,
    tgd = -1.117587089539e-8,
    iodc = 83.0,
    transmission_time = 259218.0,
)

gal_eph = GalileoEphemeris(;
    prn = 3,
    toc = DateTime(2020, 1, 1, 2, 0, 0),
    af0 = -5.335765890777e-4,
    af1 = -8.100187187665e-12,
    af2 = 0.0,
    iodnav = 91.0,
    crs = 74.03125,
    deltan = 2.900835219221e-9,
    m0 = -2.421956924348,
    cuc = 3.362074494362e-6,
    e = 2.630989672616e-4,
    cus = 8.752569556236e-6,
    sqrt_a = 5.440613872528e3,
    toe = 266400.0,
    cic = 4.470348358154e-8,
    omega0 = -2.113594073071,
    cis = 7.264316082001e-8,
    i0 = 9.906056228347e-1,
    crc = 145.71875,
    omega = 8.529762196642e-2,
    omegadot = -5.406296899347e-9,
    idot = 2.575107271162e-10,
    week = 2086.0,
    sisa = 3.12,
    sv_health = 0.0,
    bgd_e5a_e1 = -8.847936987877e-9,
    bgd_e5b_e1 = -9.313225746155e-9,
    transmission_time = 266465.0,
)

bds_eph = BeiDouEphemeris(;
    prn = 21,
    toc = DateTime(2020, 1, 1, 2, 0, 0),
    af0 = -2.229036763310e-4,
    af1 = 1.396483990392e-11,
    af2 = 0.0,
    aode = 1.0,
    crs = -3.128125000000e2,
    deltan = 1.281847459404e-9,
    m0 = -1.573072741952,
    cuc = -1.019053161144e-5,
    e = 6.324013043195e-4,
    cus = 6.938725709915e-6,
    sqrt_a = 6.493413494110e3,
    toe = 266400.0,
    cic = 1.769512891769e-7,
    omega0 = -2.204464371371,
    cis = -1.303851604462e-7,
    i0 = 9.626440735042e-1,
    crc = 1.755781250000e2,
    omega = -2.936387939148,
    omegadot = -2.157608862158e-9,
    idot = -3.239297798064e-10,
    week = 730.0,
    sv_accuracy = 2.0,
    sath1 = 0.0,
    tgd1_b1_b3 = -1.100000000000e-8,
    tgd2_b2_b3 = -1.170000000000e-8,
    transmission_time = 266465.0,
    aodc = 1.0,
)

# Stand-in for a constellation this package does not model yet: writing it
# must need no more than the ephemeris interface.
struct MinimalEphemeris
    prn::Int
    toc::DateTime
    af0::Float64
    af1::Float64
    af2::Float64
    toe::Float64
end
RINEXParser.system(::MinimalEphemeris) = 'J'
RINEXParser.dedupe_key(eph::MinimalEphemeris) = (RINEXParser.system(eph), eph.prn, eph.toe)
RINEXParser.orbit_lines(eph::MinimalEphemeris) = ((eph.toe,),)
