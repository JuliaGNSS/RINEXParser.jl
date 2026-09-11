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

@testset "BeiDou navigation file" begin
    lines = written_lines(RinexNavWriter, RinexNavHeader(satellite_system = 'C')) do writer
        @test write_ephemeris!(writer, bds_eph)
        # The age of the ephemeris grows while the parameter set stays the
        # same, so it must not make the record a new one.
        @test !write_ephemeris!(writer, modify(bds_eph; aode = 2.0, aodc = 2.0))
        # A new parameter set comes with a new Toe.
        @test write_ephemeris!(writer, modify(bds_eph; toe = 269400.0))
    end

    @test content(lines[1]) == "     3.05           N: GNSS NAV DATA    C: BDS"

    body = body_lines(lines)
    @test length(body) == 16
    @test body[1][1:23] == "C21 2020 01 01 02 00 00"
    clock = parse.(Float64, [body[1][c:(c+18)] for c in (24, 43, 62)])
    @test clock ≈ [bds_eph.af0, bds_eph.af1, bds_eph.af2]
    # Round-trip the Keplerian elements of broadcast orbit lines 1-4.
    @test orbit_values(body, 2:5) ≈ [
        bds_eph.aode,
        bds_eph.crs,
        bds_eph.deltan,
        bds_eph.m0,
        bds_eph.cuc,
        bds_eph.e,
        bds_eph.cus,
        bds_eph.sqrt_a,
        bds_eph.toe,
        bds_eph.cic,
        bds_eph.omega0,
        bds_eph.cis,
        bds_eph.i0,
        bds_eph.crc,
        bds_eph.omega,
        bds_eph.omegadot,
    ]
    # Line 5 carries IDOT, the spare and the BDT week. The spare is left
    # blank (section 6.4), so the week keeps its columns; the spare trailing
    # the week ends the line and is left off.
    @test body[6] == "    -3.239297798064E-10" * " "^19 * " 7.300000000000E+02"
    @test orbit_values(body, 7:7) ≈
          [bds_eph.sv_accuracy, bds_eph.sath1, bds_eph.tgd1_b1_b3, bds_eph.tgd2_b2_b3]
    # Line 7 is the transmission time and the age of the clock data.
    @test strip(body[8]) == "2.664650000000E+05 1.000000000000E+00"
    @test body[9][1:3] == "C21"
end

@testset "the BeiDou record of the RINEX 3.05 example" begin
    # The C01 record of Table A15, written back field by field. The example
    # is the spec's own, so it pins the column layout of the record - the
    # blank spare of broadcast orbit line 5 included - against the format
    # rather than against this implementation.
    eph = BeiDouEphemeris(;
        prn = 1,
        toc = DateTime(2014, 5, 10, 0, 0, 0),
        af0 = 2.969256602228e-4,
        af1 = 2.196998138970e-11,
        af2 = 0.0,
        aode = 1.0,
        crs = 4.365468750000e2,
        deltan = 1.318269196918e-9,
        m0 = -3.118148933476,
        cuc = 1.447647809982e-5,
        e = 2.822051756084e-4,
        cus = 8.092261850834e-6,
        sqrt_a = 6.493480609894e3,
        toe = 5.184e5,
        cic = -2.654269337654e-8,
        omega0 = 3.076630958509,
        cis = -3.864988684654e-8,
        i0 = 1.103024081152e-1,
        crc = -2.506406250000e2,
        omega = 2.587808789012,
        omegadot = -3.039412318009e-10,
        idot = 2.389385241772e-10,
        week = 435.0,
        sv_accuracy = 2.0,
        sath1 = 0.0,
        tgd1_b1_b3 = 1.42e-8,
        tgd2_b2_b3 = -1.04e-8,
        transmission_time = 5.184e5,
        aodc = 0.0,
    )
    lines = written_lines(RinexNavWriter, RinexNavHeader(satellite_system = 'C')) do writer
        write_ephemeris!(writer, eph)
    end
    # The spec prints the example with a lowercase exponent, which RINEX
    # allows next to the "E" and "D" of the Fortran formats.
    @test body_lines(lines) == [
        "C01 2014 05 10 00 00 00 2.969256602228E-04 2.196998138970E-11 0.000000000000E+00",
        "     1.000000000000E+00 4.365468750000E+02 1.318269196918E-09-3.118148933476E+00",
        "     1.447647809982E-05 2.822051756084E-04 8.092261850834E-06 6.493480609894E+03",
        "     5.184000000000E+05-2.654269337654E-08 3.076630958509E+00-3.864988684654E-08",
        "     1.103024081152E-01-2.506406250000E+02 2.587808789012E+00-3.039412318009E-10",
        "     2.389385241772E-10                    4.350000000000E+02",
        "     2.000000000000E+00 0.000000000000E+00 1.420000000000E-08-1.040000000000E-08",
        "     5.184000000000E+05 0.000000000000E+00",
    ]
end

@testset "single-system header rejects other constellations" begin
    writer = RinexNavWriter(IOBuffer(), RinexNavHeader(satellite_system = 'G'))
    @test_throws ArgumentError write_ephemeris!(writer, gal_eph)
    @test write_ephemeris!(writer, gps_eph)
end

@testset "Table A8 bit fields" begin
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
    # Section 6.8 gives the exponent of a navigation field two digits, so a
    # value needing three is rejected whichever sign it has - `1e-100` would
    # occupy the 19 columns of the field, but not as the number it is.
    @test_throws ArgumentError write_ephemeris!(writer, modify(gps_eph; crs = -1e-100))
    @test_throws ArgumentError write_ephemeris!(writer, modify(gps_eph; crs = 1e-100))
    @test_throws ArgumentError write_ephemeris!(writer, modify(gps_eph; af0 = -1.5e100))
    @test_throws ArgumentError write_ephemeris!(writer, modify(gps_eph; af0 = 1.5e100))
    # The largest and smallest a two-digit exponent reaches still fit.
    lines = written_lines(RinexNavWriter, RinexNavHeader()) do w
        @test write_ephemeris!(w, modify(gps_eph; crs = 1e-99, cuc = -9.9e99))
    end
    @test body_lines(lines)[2][24:42] == " 1.000000000000E-99"
    @test body_lines(lines)[3][5:23] == "-9.900000000000E+99"

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
    qzss = MinimalEphemeris(3, DateTime(2020, 1, 1, 2, 0, 0), 1.0e-4, 0.0, 0.0, 266400.0)
    lines = written_lines(RinexNavWriter, RinexNavHeader(satellite_system = 'J')) do writer
        @test write_ephemeris!(writer, qzss)
        @test !write_ephemeris!(writer, qzss)
    end
    @test content(lines[1]) == "     3.05           N: GNSS NAV DATA    J: QZSS"
    body = body_lines(lines)
    @test length(body) == 2
    @test body[1][1:23] == "J03 2020 01 01 02 00 00"
    # Clock coefficients default to the af0/af1/af2 fields.
    clock = parse.(Float64, [body[1][c:(c+18)] for c in (24, 43, 62)])
    @test clock ≈ [qzss.af0, qzss.af1, qzss.af2]
    @test strip(body[2]) == "2.664000000000E+05"
end

@testset "BDS header records carry what the format makes mandatory" begin
    # Table A5 makes the time mark and the satellite number mandatory for a
    # BDS ionospheric correction: the constellation broadcasts several sets
    # a day, and a reader has to tell them apart.
    @test_throws ArgumentError IonosphericCorrection("BDSA", (1.0, 0.0, 0.0, 0.0))
    @test_throws ArgumentError IonosphericCorrection(
        "BDSB",
        (1.0, 0.0, 0.0, 0.0);
        time_mark = 'A',
    )
    @test_throws ArgumentError IonosphericCorrection(
        "BDSA",
        (1.0, 0.0, 0.0, 0.0);
        time_mark = 'Y',
        sv_id = 6,
    )
    # Optional for the other constellations, which keep working without.
    @test IonosphericCorrection("GPSA", (1.0, 0.0, 0.0, 0.0)).time_mark === nothing

    header = RinexNavHeader(
        satellite_system = 'C',
        ionospheric_corrections = [
            IonosphericCorrection(
                "BDSA",
                (1.1176e-8, 2.9802e-8, -4.1723e-7, 4.7684e-7);
                time_mark = 'A',
                sv_id = 6,
            ),
        ],
        # A BDS file counts the leap-second week from the BDT epoch, which
        # only the time system identifier tells a reader.
        leap_seconds = LeapSeconds(
            4;
            future_count = 4,
            week = 730,
            day = 0,
            time_system = "BDT",
        ),
    )
    lines = written_lines(RinexNavWriter, header) do writer
        write_ephemeris!(writer, bds_eph)
    end
    iono = only(filter(l -> label(l) == "IONOSPHERIC CORR", lines))
    @test content(iono) == "BDSA   1.1176E-08  2.9802E-08 -4.1723E-07  4.7684E-07 A  6"
    # `A4,1X`, `4D12.4`, then the time mark as `1X,A1` and the satellite
    # number as `1X,I2`.
    @test iono[55] == 'A'
    @test iono[57:58] == " 6"
    leap = only(filter(l -> label(l) == "LEAP SECONDS", lines))
    # `4I6,A3`: the identifier follows the day number with no separator.
    @test content(leap) == "     4     4   730     0BDT"
    @test leap[25:27] == "BDT"
    # It lands in the same columns when the counts between are blank.
    blank = written_lines(
        RinexNavWriter,
        RinexNavHeader(
            satellite_system = 'C',
            leap_seconds = LeapSeconds(4; time_system = "BDT"),
        ),
    ) do writer
        write_ephemeris!(writer, bds_eph)
    end
    @test only(filter(l -> label(l) == "LEAP SECONDS", blank))[25:27] == "BDT"

    # Blank defaults to GPS, which is what a file that says nothing gets.
    plain = written_lines(RinexNavWriter, RinexNavHeader(leap_seconds = 18)) do writer
        write_ephemeris!(writer, gps_eph)
    end
    @test content(only(filter(l -> label(l) == "LEAP SECONDS", plain))) == "    18"
    # An Int and a 4-tuple still name a record, as they did before.
    @test RinexNavHeader(leap_seconds = (18, 18, 2185, 7)).leap_seconds.week == 2185
    @test RinexNavHeader(leap_seconds = 18).leap_seconds.count == 18
    # Only the two identifiers the format defines, and the day number is
    # counted the way the named system counts it.
    @test_throws ArgumentError LeapSeconds(18; time_system = "GAL")
    @test_throws ArgumentError LeapSeconds(18; day = 0)
    @test_throws ArgumentError LeapSeconds(4; day = 7, time_system = "BDT")
end

@testset "ephemerides of different weeks are different records" begin
    # `toe` is a second of the week and the issue of data a counter that
    # wraps, so neither separates two ephemerides a week apart.
    lines = written_lines(RinexNavWriter, RinexNavHeader()) do writer
        @test write_ephemeris!(writer, gps_eph)
        @test !write_ephemeris!(writer, gps_eph)
        @test write_ephemeris!(writer, modify(gps_eph; week = gps_eph.week + 1))
        @test write_ephemeris!(writer, gal_eph)
        @test !write_ephemeris!(writer, gal_eph)
        @test write_ephemeris!(writer, modify(gal_eph; week = gal_eph.week + 1))
    end
    @test length(body_lines(lines)) == 4 * 8
end

@testset "a Galileo record cannot come from I/NAV and F/NAV at once" begin
    # Table A8: the two messages carry different information, so a record
    # decoded from both is not one record.
    @test_throws ArgumentError galileo_data_sources(;
        inav_e1b = true,
        fnav_e5a = true,
        inav_e5b = true,
        clock_e5b_e1 = true,
    )
    # The pairs a receiver does produce are unaffected.
    @test galileo_data_sources(; inav_e1b = true, inav_e5b = true, clock_e5b_e1 = true) ==
          517.0
end
