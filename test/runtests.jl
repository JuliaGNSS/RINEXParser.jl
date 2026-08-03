using Test
using Dates
using Printf
using RINEXParser

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
RINEXParser.system(::MinimalEphemeris) = 'C'
RINEXParser.dedupe_key(eph::MinimalEphemeris) = (RINEXParser.system(eph), eph.prn, eph.toe)
RINEXParser.orbit_lines(eph::MinimalEphemeris) = ((eph.toe,),)

@testset "observation file" begin
    header = RinexObsHeader(
        marker_name = "TEST",
        receiver_type = "GNSSReceiver.jl",
        antenna_type = "UNKNOWN",
        approx_position = (4141446.0044, 604023.0011, 4796597.5545),
        obs_types = ['G' => ["C1C", "L1C", "D1C", "S1C"]],
        interval = 1.0,
        leap_seconds = 18,
    )
    epoch = ObsEpoch(
        DateTime(2020, 1, 1, 0, 0, 30),
        [
            SatObs(
                'G',
                2,
                [
                    ObsValue(21234567.89),
                    ObsValue(111583948.752, lli = 0, ssi = 7),
                    ObsValue(-1234.567),
                    ObsValue(45.2),
                ],
            ),
            SatObs(
                'G',
                13,
                [ObsValue(23456789.012), nothing, ObsValue(2345.678), ObsValue(38.1)],
            ),
        ],
        clock_offset = -1.23456789e-4,
    )

    lines = written_lines(w -> write_epoch!(w, epoch), RinexObsWriter, header)

    @testset "header records" begin
        @test label(lines[1]) == "RINEX VERSION / TYPE"
        @test content(lines[1]) == "     3.05           OBSERVATION DATA    G: GPS"
        expected_labels = [
            "RINEX VERSION / TYPE",
            "PGM / RUN BY / DATE",
            "MARKER NAME",
            "MARKER TYPE",
            "OBSERVER / AGENCY",
            "REC # / TYPE / VERS",
            "ANT # / TYPE",
            "APPROX POSITION XYZ",
            "ANTENNA: DELTA H/E/N",
            "SYS / # / OBS TYPES",
            "INTERVAL",
            "TIME OF FIRST OBS",
            "SYS / PHASE SHIFT",
            "GLONASS SLOT / FRQ #",
            "GLONASS COD/PHS/BIS",
            "LEAP SECONDS",
            "END OF HEADER",
        ]
        header_lines = lines[1:findfirst(l->label(l)=="END OF HEADER", lines)]
        @test label.(header_lines) == expected_labels
        @test all(length(l) <= 80 for l in header_lines)
        @test content(lines[8]) == "  4141446.0044   604023.0011  4796597.5545"
        @test content(lines[10]) == "G    4 C1C L1C D1C S1C"
        # Time of first obs is taken from the first epoch.
        @test content(lines[12]) == "  2020     1     1     0     0   30.0000000     GPS"
        @test content(lines[13]) == "G L1C"
    end

    @testset "epoch record" begin
        epoch_line = lines[findfirst(startswith(">"), lines)]
        @test first(epoch_line, 35) == "> 2020 01 01 00 00 30.0000000  0  2"
        # Receiver clock offset occupies columns 42-56 (F15.12).
        @test epoch_line[42:56] == "-0.000123456789"
        sat_lines = lines[(end-1):end]
        @test first(sat_lines[1], 3) == "G02"
        # Value in columns 4-17, then one column each for LLI and SSI.
        @test sat_lines[1][4:17] == "  21234567.890"
        @test sat_lines[1][20:35] == " 111583948.75207"
        @test sat_lines[2] ==
              "G13" *
              "  23456789.012" *
              "  " *
              " "^16 *
              "      2345.678" *
              "  " *
              "        38.100" *
              "  "
    end

    @testset "more than 13 obs types use continuation lines" begin
        many = [
            "C1C",
            "L1C",
            "D1C",
            "S1C",
            "C2W",
            "L2W",
            "D2W",
            "S2W",
            "C2L",
            "L2L",
            "D2L",
            "S2L",
            "C5Q",
            "L5Q",
            "D5Q",
            "S5Q",
        ]
        wide = RinexObsHeader(obs_types = ['G' => many])
        lines = written_lines(w -> nothing, RinexObsWriter, wide)
        type_lines = filter(l -> label(l) == "SYS / # / OBS TYPES", lines)
        @test length(type_lines) == 2
        @test content(type_lines[1]) ==
              "G   16 C1C L1C D1C S1C C2W L2W D2W S2W C2L L2L D2L S2L C5Q"
        @test content(type_lines[2]) == "       L5Q D5Q S5Q"
    end

    @testset "observation count must match header" begin
        bad = ObsEpoch(DateTime(2020, 1, 1), [SatObs('G', 1, [ObsValue(1.0)])])
        writer = RinexObsWriter(IOBuffer(), header)
        @test_throws ArgumentError write_epoch!(writer, bad)
    end

    @testset "observations addressed by observation type" begin
        # The same satellite record as above, built from descriptors in an
        # order of its own instead of the header's.
        same(a::SatObs, b::SatObs) =
            a.system == b.system && a.prn == b.prn && a.observations == b.observations

        by_code = SatObs(
            header,
            'G',
            2,
            "L1C" => ObsValue(111583948.752; lli = 0, ssi = 7),
            "S1C" => 45.2,
            "C1C" => 21234567.89,
            :D1C => -1234.567,
        )
        @test same(by_code, first(epoch.satellites))

        # Observation types the header declares but the call does not
        # mention stay blank, and so does an explicit `nothing`. Any
        # iterable of pairs works, which is what a receiver collects when
        # the available observables vary per satellite.
        sparse = SatObs(
            header,
            'G',
            13,
            ["C1C" => 23456789.012, "L1C" => nothing, "D1C" => 2345.678, "S1C" => 38.1],
        )
        @test same(sparse, last(epoch.satellites))
        @test SatObs(header, 'G', 7).observations == fill(nothing, 4)

        # A writer stands in for its header, which is what a receiver holds.
        writer = RinexObsWriter(IOBuffer(), header)
        @test same(
            SatObs(writer, 'G', 2, "C1C" => 21234567.89),
            SatObs(header, 'G', 2, "C1C" => 21234567.89),
        )

        @test_throws ArgumentError SatObs(header, 'G', 2, "C2W" => 1.0)
        @test_throws ArgumentError SatObs(header, 'E', 2, "C1C" => 1.0)
        @test_throws ArgumentError SatObs(header, 'G', 2, "C1C" => 1.0, "C1C" => 2.0)
        # Neither half of a pair falls through to a conversion error.
        @test_throws ArgumentError SatObs(header, 'G', 2, 1 => 1.0)
        @test_throws ArgumentError SatObs(header, 'G', 2, "C1C" => "21234567.890")
        @test_throws ArgumentError SatObs(header, 'G', 2, [ObsValue(1.0)])
    end

    @testset "the header can be completed until it is written" begin
        lazy = RinexObsHeader(obs_types = ['G' => ["C1C"]])
        lines = written_lines(RinexObsWriter, lazy) do writer
            writer.header.approx_position = (4141446.0044, 604023.0011, 4796597.5545)
            writer.header.leap_seconds = 18
            writer.header.marker_name = "ROOF-1"
            write_epoch!(writer, ObsEpoch(DateTime(2020, 1, 1), SatObs[]))
        end
        @test content(lines[findfirst(l -> label(l) == "MARKER NAME", lines)]) == "ROOF-1"
        @test content(lines[findfirst(l -> label(l) == "APPROX POSITION XYZ", lines)]) ==
              "  4141446.0044   604023.0011  4796597.5545"
        @test !isnothing(findfirst(l -> label(l) == "LEAP SECONDS", lines))
    end

    @testset "the time system follows the constellation" begin
        function time_system(obs_types)
            lines = written_lines(
                w -> write_epoch!(w, ObsEpoch(DateTime(2020, 1, 1), SatObs[])),
                RinexObsWriter,
                RinexObsHeader(; obs_types),
            )
            record = only(filter(l -> label(l) == "TIME OF FIRST OBS", lines))
            last(split(content(record)))
        end
        @test time_system(['G' => ["C1C"]]) == "GPS"
        @test time_system(['E' => ["C1C"]]) == "GAL"
        @test time_system(['C' => ["C1C"]]) == "BDT"
        # A mixed file is written in GPS time.
        @test time_system(['G' => ["C1C"], 'E' => ["C1C"]]) == "GPS"
    end

    @testset "a record is never silently shifted out of alignment" begin
        write_value(value; kwargs...) = body_lines(
            written_lines(
                w -> write_epoch!(
                    w,
                    ObsEpoch(
                        DateTime(2020, 1, 1),
                        [SatObs('G', 1, [ObsValue(value; kwargs...)])],
                    ),
                ),
                RinexObsWriter,
                RinexObsHeader(obs_types = ['G' => ["C1C"]]),
            ),
        )[2]

        # A measurement that is not available leaves its field blank, which
        # is what RINEX means by "no observation" - "NaN" would keep the
        # columns aligned and be read back as a number.
        @test write_value(NaN) == "G01" * " "^16
        @test write_value(Inf; lli = 0, ssi = 7) == "G01" * " "^16
        # The widest value the field holds, and the first one it does not.
        @test write_value(9999999999.999) == "G01" * "9999999999.999" * "  "
        @test write_value(-999999999.999) == "G01" * "-999999999.999" * "  "
        @test_throws ArgumentError write_value(1e10)
        @test_throws ArgumentError write_value(-1e9)
        # An indicator holds a single column, so any digit passes - a
        # receiver reports ssi = 0 for a signal strength it does not have -
        # and anything wider does not.
        @test write_value(1.0; lli = 0, ssi = 0) == "G01" * "         1.000" * "00"
        @test_throws ArgumentError ObsValue(1.0; lli = 10)
        @test_throws ArgumentError ObsValue(1.0; ssi = -1)
        # The seconds of the epoch record are a fixed field like any other.
        seconds(fractional_second) = write_epoch!(
            RinexObsWriter(IOBuffer(), RinexObsHeader(obs_types = ['G' => ["C1C"]])),
            ObsEpoch(DateTime(2020, 1, 1), SatObs[]; fractional_second),
        )
        @test isnothing(seconds(1.0e-5))
        @test_throws ArgumentError seconds(NaN)
        # So does the receiver clock offset of the epoch record.
        offset(value) = write_epoch!(
            RinexObsWriter(IOBuffer(), RinexObsHeader(obs_types = ['G' => ["C1C"]])),
            ObsEpoch(DateTime(2020, 1, 1), SatObs[]; clock_offset = value),
        )
        @test isnothing(offset(-0.999))
        @test_throws ArgumentError offset(100.0)
        # And so does the two-column satellite number.
        @test_throws ArgumentError write_epoch!(
            RinexObsWriter(IOBuffer(), RinexObsHeader(obs_types = ['G' => ["C1C"]])),
            ObsEpoch(DateTime(2020, 1, 1), [SatObs('G', 100, [ObsValue(1.0)])]),
        )
    end

    @testset "epochs are written without allocating per field" begin
        many = RinexObsHeader(
            obs_types = ['G' => ["C1C", "L1C", "D1C", "S1C", "C5Q", "L5Q", "D5Q", "S5Q"]],
        )
        sats = [
            SatObs(
                many,
                'G',
                prn,
                (code => 2.1e7 + prn for code in last(many.obs_types[1]))...,
            ) for prn = 1:30
        ]
        epoch = ObsEpoch(DateTime(2020, 1, 1), sats; clock_offset = -1.2e-4)
        writer = RinexObsWriter(devnull, many)
        write_epoch!(writer, epoch)                       # compile and write the header
        allocated = @allocated for _ = 1:10
            write_epoch!(writer, epoch)
        end
        # A per-field string would be some 90 kB for these 240 observations;
        # the record buffer needs none of it.
        @test allocated / 10 < 1024
    end
end

@testset "navigation file" begin
    header = RinexNavHeader(
        satellite_system = 'G',
        ionospheric_corrections = [
            IonosphericCorrection("GPSA", (1.1176e-8, -7.4506e-9, -5.9605e-8, 1.1921e-7)),
            IonosphericCorrection("GPSB", (9.0112e4, -6.5536e4, -1.3107e5, 4.5875e5)),
        ],
        time_system_corrections = [
            TimeSystemCorrection("GPUT", -3.7252902985e-9, -1.065814104e-14, 61440, 2086),
        ],
        leap_seconds = 18,
    )
    eph = gps_eph

    lines = written_lines(RinexNavWriter, header) do writer
        @test write_ephemeris!(writer, eph)
        # The same ephemeris (PRN, IODC, Toe) is skipped on repeat.
        @test !write_ephemeris!(writer, eph)
        @test write_ephemeris!(writer, modify(eph; iode = 84.0, iodc = 84.0))
    end

    @testset "header records" begin
        @test content(lines[1]) == "     3.05           N: GNSS NAV DATA    G: GPS"
        @test label(lines[3]) == "IONOSPHERIC CORR"
        @test content(lines[3]) == "GPSA   1.1176E-08 -7.4506E-09 -5.9605E-08  1.1921E-07"
        @test label(lines[5]) == "TIME SYSTEM CORR"
        @test content(lines[5]) == "GPUT -3.7252902985E-09-1.065814104E-14  61440 2086"
        @test label(lines[6]) == "LEAP SECONDS"
        @test label(lines[7]) == "END OF HEADER"
    end

    @testset "ephemeris record" begin
        body = body_lines(lines)
        @test length(body) == 16
        @test body[1][1:23] == "G13 2020 01 01 02 00 00"
        @test body[1][24:42] == "-3.153673559427E-04"
        @test body[2] ==
              "    " *
              " 8.300000000000E+01" *
              "-4.915625000000E+01" *
              " 4.464114626131E-09" *
              " 2.909791674811E+00"
        @test all(length(line) <= 80 for line in body)
        # Last line carries only transmission time and fit interval.
        @test strip(body[8]) == "2.592180000000E+05 4.000000000000E+00"
        # Round-trip every numeric field through the file.
        @test orbit_values(body, 2:7) ≈ [
            eph.iode,
            eph.crs,
            eph.deltan,
            eph.m0,
            eph.cuc,
            eph.e,
            eph.cus,
            eph.sqrt_a,
            eph.toe,
            eph.cic,
            eph.omega0,
            eph.cis,
            eph.i0,
            eph.crc,
            eph.omega,
            eph.omegadot,
            eph.idot,
            eph.codes_on_l2,
            eph.week,
            eph.l2p_data_flag,
            eph.sv_accuracy,
            eph.sv_health,
            eph.tgd,
            eph.iodc,
        ]
    end
end

@testset "mixed navigation file with Galileo" begin
    gal = gal_eph
    # Same satellite number, issue of data and Toe as the Galileo record.
    gps = modify(gps_eph; prn = 3, iode = 91.0, iodc = 91.0)

    lines = written_lines(RinexNavWriter, RinexNavHeader()) do writer
        @test write_ephemeris!(writer, gal)
        @test !write_ephemeris!(writer, gal)
        # Same PRN/IOD/Toe in another system is a different ephemeris.
        @test write_ephemeris!(writer, gps)
    end

    # Without a fixed satellite_system the file is marked as mixed.
    @test content(lines[1]) == "     3.05           N: GNSS NAV DATA    M: MIXED"

    body = body_lines(lines)
    @test length(body) == 16
    @test body[1][1:23] == "E03 2020 01 01 02 00 00"
    @test body[1][24:42] == "-5.335765890777E-04"
    # Line 5 carries IDOT, data sources (I/NAV E1-B default), GAL week.
    @test strip(body[6]) == "2.575107271162E-10 5.130000000000E+02 2.086000000000E+03"
    @test strip(body[8]) == "2.664650000000E+05"
    @test body[9][1:3] == "G03"
    # Round-trip the Galileo orbit fields.
    @test orbit_values(body, 2:5) ≈ [
        gal.iodnav,
        gal.crs,
        gal.deltan,
        gal.m0,
        gal.cuc,
        gal.e,
        gal.cus,
        gal.sqrt_a,
        gal.toe,
        gal.cic,
        gal.omega0,
        gal.cis,
        gal.i0,
        gal.crc,
        gal.omega,
        gal.omegadot,
    ]
    @test orbit_values(body, 7:7) ≈
          [gal.sisa, gal.sv_health, gal.bgd_e5a_e1, gal.bgd_e5b_e1]
end

@testset "Galileo F/NAV and I/NAV are separate records" begin
    lines = written_lines(RinexNavWriter, RinexNavHeader(satellite_system = 'E')) do writer
        @test write_ephemeris!(writer, gal_eph)
        # Same PRN/IODnav/Toe, but F/NAV from E5a-I with E5a/E1 clock
        # parameters (data source bits 1 and 8).
        @test write_ephemeris!(writer, modify(gal_eph; data_sources = 258.0))
    end
    body = body_lines(lines)
    @test length(body) == 16
    @test strip(body[14]) == "2.575107271162E-10 2.580000000000E+02 2.086000000000E+03"
end

@testset "single-system header rejects other constellations" begin
    writer = RinexNavWriter(IOBuffer(), RinexNavHeader(satellite_system = 'G'))
    @test_throws ArgumentError write_ephemeris!(writer, gal_eph)
    @test write_ephemeris!(writer, gps_eph)
end

@testset "unknown satellite system character" begin
    # Rejected when the writer is created, before a file is opened.
    @test_throws ArgumentError RinexNavWriter(
        IOBuffer(),
        RinexNavHeader(satellite_system = 'X'),
    )
    # Every character of a mixed observation file is checked, although none
    # of them reaches the RINEX VERSION / TYPE record.
    @test_throws ArgumentError RinexObsWriter(
        IOBuffer(),
        RinexObsHeader(obs_types = ['G' => ["C1C"], 'X' => ["C1C"]]),
    )
    # A header replaced with an invalid one must not leak the file handle.
    path = tempname()
    writer = RinexNavWriter(path)
    writer.header = RinexNavHeader(satellite_system = 'X')
    @test_throws ArgumentError close(writer)
    @test !isopen(writer.io)
    rm(path, force = true)
end

@testset "Table A15 bit fields" begin
    # The two records of a Galileo receiver: I/NAV from E1-B with the
    # E5b/E1 clock parameters, F/NAV from E5a-I with the E5a/E1 ones.
    @test galileo_data_sources(; inav_e1b = true, clock_e5b_e1 = true) == 513.0
    @test galileo_data_sources(; fnav_e5a = true, clock_e5a_e1 = true) == 258.0
    # I/NAV decoded from both of its carriers.
    @test galileo_data_sources(; inav_e1b = true, inav_e5b = true, clock_e5b_e1 = true) ==
          517.0
    # The default of GalileoEphemeris is the I/NAV record.
    @test gal_eph.data_sources ==
          galileo_data_sources(; inav_e1b = true, clock_e5b_e1 = true)
    # A record needs a message source and exactly one clock reference.
    @test_throws ArgumentError galileo_data_sources(; clock_e5b_e1 = true)
    @test_throws ArgumentError galileo_data_sources(; inav_e1b = true)
    @test_throws ArgumentError galileo_data_sources(;
        inav_e1b = true,
        clock_e5a_e1 = true,
        clock_e5b_e1 = true,
    )

    @test galileo_sv_health() == 0.0
    # E1-B data invalid and out of service, E5a/E5b healthy.
    @test galileo_sv_health(; e1b_dvs = 1, e1b_hs = 1) == 3.0
    # Every field of the packed word, in its own bits.
    @test galileo_sv_health(; e5a_dvs = 1) == 8.0
    @test galileo_sv_health(; e5a_hs = 3) == 48.0
    @test galileo_sv_health(; e5b_dvs = 1) == 64.0
    @test galileo_sv_health(; e5b_hs = 3) == 384.0
    @test_throws ArgumentError galileo_sv_health(; e1b_dvs = 2)
    @test_throws ArgumentError galileo_sv_health(; e5b_hs = 4)
end

@testset "an ephemeris record is never shifted out of alignment either" begin
    writer = RinexNavWriter(IOBuffer())
    # A navigation record field has no blank encoding, so a value that is
    # not finite is an error rather than a missing measurement.
    @test_throws ArgumentError write_ephemeris!(writer, modify(gps_eph; af1 = NaN))
    @test_throws ArgumentError write_ephemeris!(writer, modify(gps_eph; sqrt_a = Inf))
    @test_throws ArgumentError write_ephemeris!(writer, modify(gal_eph; sisa = NaN))
    @test_throws ArgumentError write_ephemeris!(writer, modify(gps_eph; prn = 100))
    # E19.12 holds a two-digit exponent, and a three-digit one only without
    # a sign: -1e-100 takes 20 columns where 1e-100 takes 19.
    @test_throws ArgumentError write_ephemeris!(writer, modify(gps_eph; crs = -1e-100))
    @test_throws ArgumentError write_ephemeris!(writer, modify(gps_eph; af0 = -1.5e100))
    lines = written_lines(RinexNavWriter, RinexNavHeader()) do w
        @test write_ephemeris!(w, modify(gps_eph; crs = 1e-100))
    end
    @test body_lines(lines)[2][24:42] == "1.000000000000E-100"

    @testset "the record buffer reserves what a format can produce" begin
        # Every value of every record format, not only the ones the guards
        # above let through, fits the room a field reserves in the buffer.
        extremes = (
            floatmax(Float64),
            -floatmax(Float64),
            5.0e-324,
            -5.0e-324,
            0.0,
            NaN,
            Inf,
            -Inf,
            -1.0,
        )
        @test all(
            length(Printf.format(format, value)) <= RINEXParser.MAX_FIELD_WIDTH for
            format in RINEXParser.RECORD_FORMATS, value in extremes
        )
    end
end

@testset "an unknown constellation only needs the ephemeris interface" begin
    bds = MinimalEphemeris(21, DateTime(2020, 1, 1, 2, 0, 0), 1.0e-4, 0.0, 0.0, 266400.0)
    lines = written_lines(RinexNavWriter, RinexNavHeader(satellite_system = 'C')) do writer
        @test write_ephemeris!(writer, bds)
        @test !write_ephemeris!(writer, bds)
    end
    @test content(lines[1]) == "     3.05           N: GNSS NAV DATA    C: BDS"
    body = body_lines(lines)
    @test length(body) == 2
    @test body[1][1:23] == "C21 2020 01 01 02 00 00"
    # Clock coefficients default to the af0/af1/af2 fields.
    clock = parse.(Float64, [body[1][c:(c+18)] for c in (24, 43, 62)])
    @test clock ≈ [bds.af0, bds.af1, bds.af2]
    @test strip(body[2]) == "2.664000000000E+05"
end
