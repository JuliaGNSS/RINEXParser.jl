using Test
using Dates
using RINEX

function written_lines(f, writer_type, args...)
    io = IOBuffer()
    writer_type(f, io, args...)
    readlines(seekstart(io))
end

label(line) = length(line) > 60 ? rstrip(line[61:end]) : ""
content(line) = rstrip(first(line, 60))

function modify(eph::GPSEphemeris; kwargs...)
    fields = Dict{Symbol,Any}(f => getfield(eph, f) for f in fieldnames(GPSEphemeris))
    merge!(fields, Dict(kwargs))
    GPSEphemeris(; fields...)
end

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
            SatObs('G', 2, [
                ObsValue(21234567.89),
                ObsValue(111583948.752, lli = 0, ssi = 7),
                ObsValue(-1234.567),
                ObsValue(45.2),
            ]),
            SatObs('G', 13, [
                ObsValue(23456789.012),
                nothing,
                ObsValue(2345.678),
                ObsValue(38.1),
            ]),
        ],
        clock_offset = -1.23456789e-4,
    )

    lines = written_lines(w -> write_epoch!(w, epoch), RinexObsWriter, header)

    @testset "header records" begin
        @test label(lines[1]) == "RINEX VERSION / TYPE"
        @test content(lines[1]) == "     3.05           OBSERVATION DATA    G: GPS"
        expected_labels = [
            "RINEX VERSION / TYPE", "PGM / RUN BY / DATE", "MARKER NAME",
            "MARKER TYPE", "OBSERVER / AGENCY", "REC # / TYPE / VERS",
            "ANT # / TYPE", "APPROX POSITION XYZ", "ANTENNA: DELTA H/E/N",
            "SYS / # / OBS TYPES", "INTERVAL", "TIME OF FIRST OBS",
            "SYS / PHASE SHIFT", "GLONASS SLOT / FRQ #", "GLONASS COD/PHS/BIS",
            "LEAP SECONDS", "END OF HEADER",
        ]
        header_lines = lines[1:findfirst(l -> label(l) == "END OF HEADER", lines)]
        @test label.(header_lines) == expected_labels
        @test all(length(l) <= 80 for l in header_lines)
        @test content(lines[8]) == "  4141446.0044   604023.0011  4796597.5545"
        @test content(lines[10]) == "G    4 C1C L1C D1C S1C"
        # Time of first obs is taken from the first epoch.
        @test content(lines[12]) ==
              "  2020     1     1     0     0   30.0000000     GPS"
        @test content(lines[13]) == "G L1C"
    end

    @testset "epoch record" begin
        epoch_line = lines[findfirst(startswith(">"), lines)]
        @test first(epoch_line, 35) == "> 2020 01 01 00 00 30.0000000  0  2"
        # Receiver clock offset occupies columns 42-56 (F15.12).
        @test epoch_line[42:56] == "-0.000123456789"
        sat_lines = lines[(end - 1):end]
        @test first(sat_lines[1], 3) == "G02"
        # Value in columns 4-17, then one column each for LLI and SSI.
        @test sat_lines[1][4:17] == "  21234567.890"
        @test sat_lines[1][20:35] == " 111583948.75207"
        @test sat_lines[2] == "G13" * "  23456789.012" * "  " * " "^16 *
              "      2345.678" * "  " * "        38.100" * "  "
    end

    @testset "more than 13 obs types use continuation lines" begin
        many = ["C1C", "L1C", "D1C", "S1C", "C2W", "L2W", "D2W", "S2W",
            "C2L", "L2L", "D2L", "S2L", "C5Q", "L5Q", "D5Q", "S5Q"]
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
end

@testset "navigation file" begin
    header = RinexNavHeader(
        ionospheric_corrections = [
            IonosphericCorrection("GPSA", (1.1176e-8, -7.4506e-9, -5.9605e-8, 1.1921e-7)),
            IonosphericCorrection("GPSB", (9.0112e4, -6.5536e4, -1.3107e5, 4.5875e5)),
        ],
        time_system_corrections = [
            TimeSystemCorrection("GPUT", -3.7252902985e-9, -1.065814104e-14, 61440, 2086),
        ],
        leap_seconds = 18,
    )
    eph = GPSEphemeris(
        prn = 13,
        toc = DateTime(2020, 1, 1, 2, 0, 0),
        af0 = -3.153673559427e-4, af1 = -1.000444171950e-11, af2 = 0.0,
        iode = 83.0, crs = -49.15625, deltan = 4.464114626131e-9,
        m0 = 2.909791674811,
        cuc = -2.428889274597e-6, e = 4.421935591381e-3,
        cus = 3.278255462646e-6, sqrt_a = 5.153687646866e3,
        toe = 266400.0, cic = -2.216547727585e-7,
        omega0 = 1.148673191606, cis = 1.955777406693e-7,
        i0 = 9.755690921935e-1, crc = 287.46875,
        omega = 8.130950284124e-1, omegadot = -8.087836629593e-9,
        idot = -5.03592332984e-10, week = 2086.0,
        sv_accuracy = 2.0, sv_health = 0.0,
        tgd = -1.117587089539e-8, iodc = 83.0,
        transmission_time = 259218.0,
    )

    lines = written_lines(RinexNavWriter, header) do writer
        @test write_ephemeris!(writer, eph)
        # The same ephemeris (PRN, IODC, Toe) is skipped on repeat.
        @test !write_ephemeris!(writer, eph)
        @test write_ephemeris!(writer, modify(eph; iode = 84.0, iodc = 84.0))
    end

    @testset "header records" begin
        @test content(lines[1]) == "     3.05           N: GNSS NAV DATA    G: GPS"
        @test label(lines[3]) == "IONOSPHERIC CORR"
        @test content(lines[3]) ==
              "GPSA   1.1176E-08 -7.4506E-09 -5.9605E-08  1.1921E-07"
        @test label(lines[5]) == "TIME SYSTEM CORR"
        @test content(lines[5]) ==
              "GPUT -3.7252902985E-09-1.065814104E-14  61440 2086"
        @test label(lines[6]) == "LEAP SECONDS"
        @test label(lines[7]) == "END OF HEADER"
    end

    @testset "ephemeris record" begin
        body = lines[8:end]
        @test length(body) == 16
        @test body[1][1:23] == "G13 2020 01 01 02 00 00"
        @test body[1][24:42] == "-3.153673559427E-04"
        @test body[2] == "    " * " 8.300000000000E+01" * "-4.915625000000E+01" *
              " 4.464114626131E-09" * " 2.909791674811E+00"
        @test all(length(line) <= 80 for line in body)
        # Last line carries only transmission time and fit interval.
        @test strip(body[8]) == "2.592180000000E+05 4.000000000000E+00"
        # Round-trip every numeric field through the file.
        values = [parse(Float64, body[l][c:c+18])
                  for l in 2:7 for c in (5, 24, 43, 62)]
        @test values ≈ [
            eph.iode, eph.crs, eph.deltan, eph.m0,
            eph.cuc, eph.e, eph.cus, eph.sqrt_a,
            eph.toe, eph.cic, eph.omega0, eph.cis,
            eph.i0, eph.crc, eph.omega, eph.omegadot,
            eph.idot, eph.codes_on_l2, eph.week, eph.l2p_data_flag,
            eph.sv_accuracy, eph.sv_health, eph.tgd, eph.iodc,
        ]
    end
end
