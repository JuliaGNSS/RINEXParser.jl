# The decoded navigation messages of GNSSDecoder, written through its
# package extension.

# GPS week 2124 (the week 10-bit `WN = 76` resolves to around mid-2020) starts on
# Sunday 2020-09-20; the reference times below are four days into it.
const GPS_WEEK = 2124
const YEAR = 2020
const GPS_TOW = 4 * 86400
const GPS_TOC = DateTime(2020, 9, 24)

# A GPS LNAV data set carrying every field `is_decoding_completed_for_positioning` requires,
# so `rinex_ephemeris` can be checked against hand-computed record values. The orbital
# elements are a real broadcast set (GPS PRN 5) in the units the decoder stores — angles
# already scaled from semicircles to radians — so the record values are physically
# meaningful and a unit slip shows up as an impossible orbit. The subframe 4 page 18
# ionosphere / UTC parameters are passed in only where a test needs them.
gps_lnav_data(; kwargs...) = GNSSDecoder.GPSL1CAData(;
    last_subframe_id = 3,
    integrity_status_flag = false,
    TOW = 82596,
    alert_flag = false,
    anti_spoof_flag = true,
    # Subframe 1 — clock correction and satellite status
    WN = 76,
    code_on_L2 = 1,
    # URA index 0, the 2.0 m the record below expects.
    URA_index = 0,
    sv_health = 0,
    IODC = 63,
    L2_P_data_flag = false,
    T_GD = -1.071020960808e-8,
    t_0c = GPS_TOW,
    a_f0 = -2.989266067743e-5,
    a_f1 = 1.364242052659e-12,
    a_f2 = 0.0,
    # Subframe 2 — ephemeris, part 1
    IODE_Sub_2 = 63,
    C_rs = -4.49375e1,
    Δn = 5.19633e-9,           # rad/s
    M_0 = 2.79930,             # rad
    C_uc = -2.296641469002e-6,
    e = 5.172203877009e-3,
    C_us = 7.340684533119e-6,
    sqrt_A = 5.1535496521e3,
    t_0e = GPS_TOW,
    fit_interval = false,
    AODO = 0,
    # Subframe 3 — ephemeris, part 2
    C_ic = -3.166496753693e-8,
    Ω_0 = 2.91237,             # rad
    C_is = -6.705522537231e-8,
    i_0 = 0.947436,            # rad — a GPS orbit is inclined ~54°
    C_rc = 2.330625e2,
    ω = 0.577340,              # rad
    Ω_dot = -8.29275e-9,       # rad/s
    IODE_Sub_3 = 63,
    i_dot = -2.23225e-10,      # rad/s
    kwargs...,
)

# The same for Galileo I/NAV, with a real Galileo orbit (semi-major axis ~29 600 km, orbits
# inclined ~56°). `WN` is the 12-bit week counted from GPS week 1024, so the record's
# GPS-aligned week is `WN + 1024`.
galileo_inav_data(; kwargs...) = GNSSDecoder.GalileoINAVData(;
    WN = GPS_WEEK - 1024,
    TOW = 82596,
    SVID = 24,
    t_0e = Float64(GPS_TOW),
    M_0 = -1.42357,            # rad
    e = 2.1998010845e-4,
    sqrt_A = 5.4406533737e3,
    Ω_0 = 1.83094,             # rad
    i_0 = 0.976274,            # rad — a Galileo orbit is inclined ~56°
    ω = -2.51837,              # rad
    i_dot = -1.75001e-10,
    Ω_dot = -5.35001e-9,
    Δn = 2.79251e-9,
    C_uc = -6.5192580223e-7,
    C_us = 8.4526836872e-6,
    C_rc = 1.4059375e2,
    C_rs = -2.28125e1,
    C_ic = 1.4901161194e-8,
    C_is = 1.4901161194e-8,
    SISA_E1_E5b = 107,
    t_0c = Float64(GPS_TOW),
    a_f0 = -5.2394117482e-4,
    a_f1 = -1.5265128291e-12,
    a_f2 = 0.0,
    IOD_nav1 = UInt(37),
    IOD_nav2 = UInt(37),
    IOD_nav3 = UInt(37),
    IOD_nav4 = UInt(37),
    E1B_SHS = GNSSDecoder.signal_ok,
    E5b_SHS = GNSSDecoder.signal_ok,
    E1B_DVS = GNSSDecoder.navigation_data_valid,
    E5b_DVS = GNSSDecoder.navigation_data_valid,
    BGD_E1_E5a = 2.7939677238e-9,
    BGD_E1_E5b = 3.4924596548e-9,
    kwargs...,
)

# A BeiDou D1 navigation data set carrying every field a record needs, with a real BDS-3
# MEO orbit (semi-major axis ~27 900 km, inclined ~55°). BeiDou counts its weeks from
# 2006-01-01, so its week 730 begins on 2019-12-29 and second 345600 — four days in — is
# 2020-01-02, which is what the record's epoch line has to say.
const BDT_WEEK = 730
const BDT_SOW = 4 * 86400
beidou_dnav_data(; kwargs...) = GNSSDecoder.BeiDouDNAVData(;
    last_subframe_id = 3,
    SOW = BDT_SOW + 65,
    WN = BDT_WEEK,
    URAI = 0,
    SatH1 = false,
    AODE = 1,
    AODC = 1,
    t_0c = BDT_SOW,
    t_0e = BDT_SOW,
    a_f0 = -2.229036763310e-4,
    a_f1 = 1.396483990392e-11,
    a_f2 = 0.0,
    T_GD1 = -1.100000000000e-8,
    T_GD2 = -1.170000000000e-8,
    sqrt_A = 5.282622100830e3,
    e = 6.324013043195e-4,
    ω = -2.936387939148,
    Δn = 1.281847459404e-9,
    M_0 = -1.573072741952,
    Ω_0 = -2.204464371371,
    Ω_dot = -2.157608862158e-9,
    i_0 = 9.626440735042e-1,
    i_dot = -3.239297798064e-10,
    C_uc = -1.019053161144e-5,
    C_us = 6.938725709915e-6,
    C_rc = 1.755781250000e2,
    C_rs = -3.128125000000e2,
    C_ic = 1.769512891769e-7,
    C_is = -1.303851604462e-7,
    kwargs...,
)

# A decoder state holding `data` as validated navigation data.
decoder_with(system, prn, data) = GNSSDecoder.GNSSDecoderState(
    GNSSDecoderState(system, prn);
    data,
    raw_data = data,
    num_bits_since_sync = 0,
)

@testset "GPS LNAV ephemeris record" begin
    decoder = decoder_with(GPSL1CA(), 13, gps_lnav_data())
    @test is_decoding_completed_for_positioning(decoder)
    eph = rinex_ephemeris(decoder; approximate_year = YEAR)
    @test eph isa GPSEphemeris
    @test eph.prn == 13
    # The 10-bit broadcast week leaves the cycle to the year of the
    # observation, which every decoder is given.
    @test_throws UndefKeywordError rinex_ephemeris(decoder)
    @test eph.week == GPS_WEEK
    @test rinex_ephemeris(decoder; approximate_year = 2001).week == GPS_WEEK - 1024
    @test eph.toc == GPS_TOC
    # Clock polynomial and group delay pass through unscaled.
    @test eph.af0 == -2.989266067743e-5
    @test eph.af1 == 1.364242052659e-12
    @test eph.af2 == 0.0
    @test eph.tgd == -1.071020960808e-8
    # RINEX wants angles in radians, which is what the decoder already holds:
    # it applies the ICD's semicircle scaling as it parses the message, so
    # scaling again here would double it. A GPS orbit is inclined ~55°, which
    # a semicircle/radian slip would put near 170°.
    @test eph.m0 == 2.79930
    @test eph.omega0 == 2.91237
    @test eph.i0 == 0.947436
    @test eph.omega == 0.577340
    @test eph.deltan == 5.19633e-9
    @test eph.omegadot == -8.29275e-9
    @test eph.idot == -2.23225e-10
    @test rad2deg(eph.i0) ≈ 54.3 atol = 1.0
    # And the orbit it describes is a GPS one: a ~26 560 km semi-major axis,
    # nearly circular.
    @test eph.sqrt_a^2 ≈ 2.656e7 rtol = 1e-3
    @test eph.e < 0.02
    @test eph.crs == -4.49375e1
    @test eph.cuc == -2.296641469002e-6
    @test eph.toe == GPS_TOW
    @test eph.iode == 63
    @test eph.iodc == 63
    @test eph.sv_health == 0
    # URA index 0 is 2 m.
    @test eph.sv_accuracy == 2.0
    @test eph.codes_on_l2 == 1
    @test eph.l2p_data_flag == 0
    @test eph.transmission_time == 82596
    # The broadcast flag only says "nominal" or "extended"; nominal is four
    # hours.
    @test eph.fit_interval == 4.0
    extended = decoder_with(GPSL1CA(), 13, gps_lnav_data(; fit_interval = true))
    @test rinex_ephemeris(extended; approximate_year = YEAR).fit_interval == 6.0
    # An unhealthy satellite's 6-bit health word is written as the number it
    # encodes.
    unhealthy = decoder_with(GPSL1CA(), 13, gps_lnav_data(; sv_health = 0b111111))
    @test rinex_ephemeris(unhealthy; approximate_year = YEAR).sv_health == 63
    # User range accuracy across both segments of IS-GPS-200 Table 20-I, the
    # nominal values of the odd indices below 6 rounded as RINEX 3.05 Table A6
    # asks, and the index without a prediction, which the table writes as
    # 8192 m, "use at own risk".
    accuracy(index) = rinex_ephemeris(
        decoder_with(GPSL1CA(), 13, gps_lnav_data(; URA_index = index));
        approximate_year = YEAR,
    ).sv_accuracy
    @test accuracy(1) == 2.8
    @test accuracy(5) == 11.3
    @test accuracy(6) == 16.0
    @test accuracy(7) == 32.0
    @test accuracy(14) == 4096.0
    @test accuracy(15) == 8192.0

    # The record is written as it comes.
    lines = written_lines(RinexNavWriter, RinexNavHeader()) do writer
        @test write_ephemeris!(writer, eph)
    end
    @test startswith(body_lines(lines)[1], "G13 2020 09 24 00 00 00")
end

@testset "a message that is not complete has no record" begin
    # A partially decoded message would write zeros into the record.
    partial = decoder_with(GPSL1CA(), 13, gps_lnav_data(; sqrt_A = nothing))
    @test !is_decoding_completed_for_positioning(partial)
    @test isnothing(rinex_ephemeris(partial; approximate_year = YEAR))
    @test isnothing(
        rinex_ephemeris(GNSSDecoderState(GalileoE1B(), 24); approximate_year = YEAR),
    )
    # And without a decoded week a record cannot be dated.
    weekless = decoder_with(GalileoE1B(), 24, galileo_inav_data(; WN = nothing))
    @test isnothing(rinex_ephemeris(weekless; approximate_year = YEAR))
    # It will have one once it is complete.
    @test has_rinex_ephemeris(partial)
    @test has_rinex_ephemeris(GNSSDecoderState(GalileoE1B(), 24))
end

@testset "an ephemeris broadcast across a week crossover" begin
    # Late on a Saturday the next week's ephemeris is already on the air, its
    # reference times at zero of that week. The record carries the week of
    # `toe`, and the transmission time on that week's count.
    ahead = rinex_ephemeris(
        decoder_with(GPSL1CA(), 13, gps_lnav_data(; TOW = 604000, t_0e = 0, t_0c = 0));
        approximate_year = YEAR,
    )
    @test ahead.week == GPS_WEEK + 1
    @test ahead.toc == GPS_TOC + Day(3)
    @test ahead.transmission_time == 604000 - 604800
    # Just after the crossover, the last ephemeris of the old week may still be
    # broadcast.
    behind = rinex_ephemeris(
        decoder_with(
            GalileoE1B(),
            24,
            galileo_inav_data(; TOW = 30, t_0e = 597600.0, t_0c = 597600.0),
        );
        approximate_year = YEAR,
    )
    @test behind.week == GPS_WEEK - 1
    @test behind.toc == GPS_TOC - Day(11) + Second(597600)
    @test behind.transmission_time == 30 + 604800
end

@testset "Galileo ephemeris records" begin
    decoder = decoder_with(GalileoE1B(), 24, galileo_inav_data())
    eph = rinex_ephemeris(decoder; approximate_year = YEAR)
    @test eph isa GalileoEphemeris
    @test eph.prn == 24
    # Galileo's 12-bit week counts from GPS week 1024, so the record's week is
    # GPS-aligned. The week is broadcast whole, so the year is not read.
    @test eph.week == GPS_WEEK
    @test rinex_ephemeris(decoder; approximate_year = 2001) == eph
    @test eph.toc == GPS_TOC
    @test eph.iodnav == 37
    @test eph.bgd_e5a_e1 == 2.7939677238e-9
    @test eph.bgd_e5b_e1 == 3.4924596548e-9
    # I/NAV from E1-B with E5b/E1 clock terms: bit 0 and bit 9.
    @test eph.data_sources == 1 + 512
    # The same message decoded from E5b says so: bit 2 instead of bit 0.
    e5b = decoder_with(GalileoE5bI(), 24, galileo_inav_data())
    @test rinex_ephemeris(e5b; approximate_year = YEAR).data_sources == 4 + 512
    # SISA index 107 falls in the fourth segment of Table 92: 2 m + 0.16 m per
    # step.
    @test eph.sisa ≈ 2.0 + 0.16 * 7
    @test eph.sv_health == 0
    @test eph.m0 == -1.42357
    # A Galileo orbit: inclined ~56°, semi-major axis ~29 600 km.
    @test rad2deg(eph.i0) ≈ 55.9 atol = 1.0
    @test eph.sqrt_a^2 ≈ 2.960e7 rtol = 1e-3
    @test eph.transmission_time == 82596

    # A degraded E1-B: the data-validity bit is bit 0 and the two health bits
    # sit above it, while E5b - healthy in the same message - leaves bits 6-8
    # clear.
    degraded = decoder_with(
        GalileoE1B(),
        24,
        galileo_inav_data(;
            E1B_SHS = GNSSDecoder.signal_out_of_service,
            E1B_DVS = GNSSDecoder.working_without_guarantee,
        ),
    )
    @test rinex_ephemeris(degraded; approximate_year = YEAR).sv_health == 0b011
    e5b_down = decoder_with(
        GalileoE1B(),
        24,
        galileo_inav_data(; E5b_SHS = GNSSDecoder.signal_out_of_service),
    )
    @test rinex_ephemeris(e5b_down; approximate_year = YEAR).sv_health == 0b010_000_000

    # Signal-in-space accuracy across every segment of the table, plus the
    # two ranges that mean no prediction is available.
    sisa(index) = rinex_ephemeris(
        decoder_with(GalileoE1B(), 24, galileo_inav_data(; SISA_E1_E5b = index));
        approximate_year = YEAR,
    ).sisa
    @test sisa(0) == 0.0
    @test sisa(49) ≈ 0.49
    @test sisa(50) ≈ 0.5
    @test sisa(74) ≈ 0.98
    @test sisa(75) ≈ 1.0
    @test sisa(99) ≈ 1.96
    @test sisa(100) ≈ 2.0
    @test sisa(125) ≈ 6.0
    @test sisa(200) == -1.0
    @test sisa(255) == -1.0
end

@testset "BeiDou D1 ephemeris record" begin
    decoder = decoder_with(BeiDouB1I(), 21, beidou_dnav_data())
    eph = rinex_ephemeris(decoder; approximate_year = YEAR)
    @test eph isa BeiDouEphemeris
    @test eph.prn == 21
    # BDS counts its own weeks from its own origin, so the record's week is
    # the broadcast one as it stands, and the epoch it makes is BDT. Reading
    # it as a GPS week would date the record in 2033 instead.
    @test eph.week == BDT_WEEK
    @test eph.toc == DateTime(2020, 1, 2)
    @test eph.toe == Float64(BDT_SOW)
    @test eph.sqrt_a ≈ 5.282622100830e3
    @test eph.i0 ≈ 9.626440735042e-1
    # The two group delays and the age counters land in their own fields.
    @test eph.tgd1_b1_b3 ≈ -1.1e-8
    @test eph.tgd2_b2_b3 ≈ -1.17e-8
    @test (eph.aode, eph.aodc) == (1, 1)
    @test eph.sath1 == 0
    # URAI 0 is 2.0 m by the same two segments as GPS, and the top of the
    # range, no prediction, is 8192 m, "use at own risk", as for GPS (RINEX
    # 3.05 Table A14), not the -1 of Galileo's NAPA.
    @test eph.sv_accuracy == 2.0
    accuracy(index) = rinex_ephemeris(
        decoder_with(BeiDouB1I(), 21, beidou_dnav_data(; URAI = index));
        approximate_year = YEAR,
    ).sv_accuracy
    @test accuracy(14) == 4096.0
    @test accuracy(15) == 8192.0

    # The transmission time refers to the record's own week: a subframe
    # received just after a week crossover is counted from the week before,
    # which its `toe` belongs to.
    @test eph.transmission_time == Float64(BDT_SOW + 65)
    rolled = rinex_ephemeris(
        decoder_with(BeiDouB1I(), 21, beidou_dnav_data(; SOW = 30, t_0e = 604000));
        approximate_year = YEAR,
    )
    @test rolled.transmission_time == 30 + 604800
    @test rolled.week == BDT_WEEK - 1

    lines = written_lines(RinexNavWriter, RinexNavHeader()) do writer
        @test write_ephemeris!(writer, eph)
    end
    @test startswith(body_lines(lines)[1], "C21 2020 01 02 00 00 00")
end

@testset "RINEX 3.05 has no record for the CNAV messages" begin
    # GPS L5 and L2C and BDS B1C broadcast a quasi-Keplerian ephemeris RINEX
    # 3.05 cannot express, so those decoders yield no record.
    for system in (GPSL5I(), GPSL2CM())
        @test isnothing(
            rinex_ephemeris(GNSSDecoderState(system, 3); approximate_year = YEAR),
        )
        @test !has_rinex_ephemeris(GNSSDecoderState(system, 3))
    end
    b1c = decoder_with(BeiDouB1C_D(), 21, GNSSDecoder.BeiDouB1CData())
    @test isnothing(rinex_ephemeris(b1c; approximate_year = YEAR))
    @test !has_rinex_ephemeris(b1c)
    @test has_rinex_ephemeris(GNSSDecoderState(GalileoE5aI(), 24))
    @test has_rinex_ephemeris(GNSSDecoderState(BeiDouB1I(), 21))
end

# GPS subframe 4 page 18: the Klobuchar ionosphere model, the UTC offset and
# the leap seconds.
gps_page_18(; kwargs...) = gps_lnav_data(;
    α_0 = 1.0244548321e-8,
    α_1 = 2.2351741791e-8,
    α_2 = -5.9604644775e-8,
    α_3 = -1.1920928955e-7,
    β_0 = 8.8064e4,
    β_1 = 4.9152e4,
    β_2 = -6.5536e4,
    β_3 = -1.9661e5,
    A_0UTC = -9.3132257462e-10,
    A_1UTC = -7.1054273576e-15,
    t_0t = 5.8982e5,
    WN_0t = 76,
    Δt_LS = 18,
    Δt_LSF = 18,
    WN_LSF = 137,
    DN = 7,
    kwargs...,
)

@testset "navigation-header records of GPS" begin
    gps = decoder_with(GPSL1CA(), 13, gps_page_18())
    header = add_header_records!(RinexNavHeader(), gps; approximate_year = YEAR)
    iono = header.ionospheric_corrections
    @test [c.type for c in iono] == ["GPSA", "GPSB"]
    @test iono[1].parameters ==
          (1.0244548321e-8, 2.2351741791e-8, -5.9604644775e-8, -1.1920928955e-7)
    utc = only(header.time_system_corrections)
    @test utc.type == "GPUT"
    @test utc.a0 == -9.3132257462e-10
    # The reference week is broadcast in 8 bits (76 is week 2124 mod 256),
    # but RINEX wants the continuous one.
    @test utc.reference_week == GPS_WEEK
    # The four-field leap-second record, which some parsers require. Its week,
    # 137 in 8 bits, is the one nearest the current week: 2185. GPS counts
    # against the epoch a blank identifier is read as.
    leap = header.leap_seconds
    @test (leap.count, leap.future_count, leap.week, leap.day) == (18, 18, 2185, 7)
    @test leap.time_system == ""

    # Collected again from the same message, or a newer one, a record is
    # replaced rather than repeated.
    add_header_records!(header, gps; approximate_year = YEAR)
    newer = decoder_with(GPSL1CA(), 5, gps_page_18(; α_0 = 2.0e-8))
    add_header_records!(header, newer; approximate_year = YEAR)
    @test [c.type for c in header.ionospheric_corrections] == ["GPSA", "GPSB"]
    @test header.ionospheric_corrections[1].parameters[1] == 2.0e-8
    @test length(header.time_system_corrections) == 1

    # A satellite that has not sent page 18 yet contributes nothing.
    empty = add_header_records!(
        RinexNavHeader(),
        decoder_with(GPSL1CA(), 13, gps_lnav_data());
        approximate_year = YEAR,
    )
    @test isempty(empty.ionospheric_corrections)
    @test isempty(empty.time_system_corrections)
    @test isnothing(empty.leap_seconds)
    # Without the decoder's week the truncated weeks cannot be resolved: the
    # UTC and leap-second records wait for it.
    weekless = add_header_records!(
        RinexNavHeader(),
        decoder_with(GPSL1CA(), 13, gps_page_18(; WN = nothing));
        approximate_year = YEAR,
    )
    @test length(weekless.ionospheric_corrections) == 2
    @test isempty(weekless.time_system_corrections)
    @test isnothing(weekless.leap_seconds)
    @test_throws UndefKeywordError add_header_records!(RinexNavHeader(), gps)
    # A message without header records leaves the header as it was.
    @test add_header_records!(
        header,
        GNSSDecoderState(GPSL5I(), 3);
        approximate_year = YEAR,
    ) === header

    # The header is written as it was collected.
    lines = written_lines(RinexNavWriter, header) do writer
        write_ephemeris!(writer, rinex_ephemeris(gps; approximate_year = YEAR))
    end
    @test count(l -> label(l) == "IONOSPHERIC CORR", lines) == 2
    @test only(filter(l -> label(l) == "LEAP SECONDS", lines))[1:24] ==
          "    18    18  2185     7"
end

@testset "navigation-header records of Galileo" begin
    # The NeQuick coefficients, and word types 6 and 10: the UTC offset and
    # the Galileo-to-GPS time offset.
    galileo = decoder_with(
        GalileoE1B(),
        24,
        galileo_inav_data(;
            a_i0 = 4.5e1,
            a_i1 = 1.5625e-2,
            a_i2 = -3.0517578125e-3,
            A_0UTC = -9.3132257462e-10,
            A_1UTC = -7.1054273576e-15,
            t_0t = 5.184e5,
            WN_0t = 76,
            A_0G = 1.8626451492e-9,
            A_1G = 8.8817841970e-16,
            t_0G = 5.184e5,
            WN_0G = 12,
        ),
    )
    header = add_header_records!(RinexNavHeader(), galileo; approximate_year = YEAR)
    iono = only(header.ionospheric_corrections)
    @test iono.type == "GAL"
    @test iono.parameters == (4.5e1, 1.5625e-2, -3.0517578125e-3)
    corrections = header.time_system_corrections
    @test [c.type for c in corrections] == ["GAUT", "GAGP"]
    # The UTC week is broadcast in 8 bits and the GGTO week in 6 (12 is week
    # 2124 mod 64); both are written as the continuous week aligned with GPS.
    @test [c.reference_week for c in corrections] == [GPS_WEEK, GPS_WEEK]
    @test add_header_records!(RinexNavHeader(), galileo; approximate_year = 2001).time_system_corrections ==
          corrections
end

@testset "navigation-header records of BeiDou" begin
    broadcast = (;
        α_0 = 1.0244548321e-8,
        α_1 = 2.2351741791e-8,
        α_2 = -5.9604644775e-8,
        α_3 = -1.1920928955e-7,
        β_0 = 8.8064e4,
        β_1 = 4.9152e4,
        β_2 = -6.5536e4,
        β_3 = -1.9661e5,
        A_0UTC = -9.3132257462e-10,
        A_1UTC = -7.1054273576e-15,
        Δt_LS = 4,
        Δt_LSF = 4,
        WN_LSF = mod(BDT_WEEK + 3, 256),
        DN = 2,
    )
    data = beidou_dnav_data(; broadcast...)
    header = add_header_records!(
        RinexNavHeader(),
        decoder_with(BeiDouB1I(), 21, data);
        approximate_year = YEAR,
    )
    iono = header.ionospheric_corrections
    @test [c.type for c in iono] == ["BDSA", "BDSB"]
    # The BDS ionosphere records carry the transmission the coefficients
    # arrived on, which RINEX makes mandatory for BDS alone: the satellite,
    # and the hour of the day as a letter. Second 345665 of a BDT week is
    # 00h-01h of its fifth day, so `A`.
    @test all(c -> c.sv_id == 21 && c.time_mark == 'A', iono)
    # Several sets a day are told apart by when and by whom they were sent,
    # so another satellite's set is a record of its own.
    add_header_records!(
        header,
        decoder_with(BeiDouB1I(), 22, data);
        approximate_year = YEAR,
    )
    @test length(header.ionospheric_corrections) == 4
    utc = only(header.time_system_corrections)
    @test utc.type == "BDUT"
    @test utc.reference_week == BDT_WEEK
    # BDS's broadcast leap seconds are BDT - UTC, 14 fewer than the GPS - UTC
    # a blank identifier is read as, and its week and day count from the BDT
    # epoch. Naming the time system is what makes those numbers mean what
    # they say.
    leap = header.leap_seconds
    @test (leap.count, leap.future_count, leap.day) == (4, 4, 2)
    @test leap.time_system == "BDT"
    # The event's week is broadcast in 8 bits, and written as the continuous
    # BDT week.
    @test leap.week == BDT_WEEK + 3
    # Without a second of week there is no mark to give, so no record is
    # claimed.
    unmarked = beidou_dnav_data(; broadcast..., SOW = nothing)
    @test isempty(
        add_header_records!(
            RinexNavHeader(),
            decoder_with(BeiDouB1I(), 21, unmarked);
            approximate_year = YEAR,
        ).ionospheric_corrections,
    )
end

@testset "the leap seconds of a mixed file count GPS time" begin
    gps = decoder_with(GPSL1CA(), 13, gps_page_18())
    bds = decoder_with(
        BeiDouB1I(),
        21,
        beidou_dnav_data(; Δt_LS = 4, Δt_LSF = 4, WN_LSF = mod(BDT_WEEK + 3, 256), DN = 2),
    )
    for decoders in ((gps, bds), (bds, gps))
        header = RinexNavHeader()
        foreach(d -> add_header_records!(header, d; approximate_year = YEAR), decoders)
        @test header.leap_seconds.count == 18
    end
    # And a decoded record, which announces the next event, over a count given
    # by hand, which does not.
    header = RinexNavHeader(; leap_seconds = LeapSeconds(18))
    add_header_records!(header, gps; approximate_year = YEAR)
    @test header.leap_seconds.week == 2185
end

@testset "header records of messages without an ephemeris record" begin
    # GPS CNAV (L5, L2C) and the BDS B-CNAV messages have no RINEX 3.05
    # ephemeris record, but broadcast the same header records as LNAV and
    # D1/D2: the reference weeks in 13 bits, and a UTC drift rate the header
    # record has no field for.
    utc_and_leap = (;
        A_0UTC = -9.3132257462e-10,
        A_1UTC = -7.1054273576e-15,
        A_2UTC = 0.0,
        t_0t = 518400,
        Δt_LS = 18,
        Δt_LSF = 18,
        DN = 7,
    )
    l5 = decoder_with(
        GPSL5I(),
        3,
        GNSSDecoder.GPSCNAVData(;
            WN = GPS_WEEK,
            TOW = GPS_TOW,
            α_0 = 1.0244548321e-8,
            α_1 = 2.2351741791e-8,
            α_2 = -5.9604644775e-8,
            α_3 = -1.1920928955e-7,
            β_0 = 8.8064e4,
            β_1 = 4.9152e4,
            β_2 = -6.5536e4,
            β_3 = -1.9661e5,
            WN_0t = GPS_WEEK,
            WN_LSF = 2185,
            utc_and_leap...,
        ),
    )
    @test !has_rinex_ephemeris(l5)
    header = add_header_records!(RinexNavHeader(), l5; approximate_year = YEAR)
    @test [c.type for c in header.ionospheric_corrections] == ["GPSA", "GPSB"]
    utc = only(header.time_system_corrections)
    @test (utc.type, utc.a0, utc.reference_time, utc.reference_week) ==
          ("GPUT", -9.3132257462e-10, 518400, GPS_WEEK)
    leap = header.leap_seconds
    @test (leap.count, leap.week, leap.day, leap.time_system) == (18, 2185, 7, "")

    # B1C: BDT's UTC offset with the reference epoch D1/D2 does not broadcast,
    # and BDT leap seconds. Its ionosphere is BDGIM, which RINEX 3.05 has no
    # record for.
    b1c = decoder_with(
        BeiDouB1C_D(),
        21,
        GNSSDecoder.BeiDouB1CData(;
            WN = BDT_WEEK,
            utc_and_leap...,
            WN_0t = BDT_WEEK,
            Δt_LS = 4,
            Δt_LSF = 4,
            WN_LSF = BDT_WEEK + 3,
            DN = 2,
        ),
    )
    @test !has_rinex_ephemeris(b1c)
    header = add_header_records!(RinexNavHeader(), b1c; approximate_year = YEAR)
    @test isempty(header.ionospheric_corrections)
    utc = only(header.time_system_corrections)
    @test (utc.type, utc.reference_time, utc.reference_week) == ("BDUT", 518400, BDT_WEEK)
    leap = header.leap_seconds
    @test (leap.count, leap.week, leap.day, leap.time_system) == (4, BDT_WEEK + 3, 2, "BDT")
end
