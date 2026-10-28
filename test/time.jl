@testset "the times of a navigation record" begin
    # GPS week 2124 starts on Sunday 2020-09-20.
    times = navigation_times(
        'G';
        week = 2124,
        transmission_time = 82596,
        toe = 345600,
        toc = 345600,
    )
    @test times == (; week = 2124, toc = DateTime(2020, 9, 24), transmission_time = 82596.0)

    # Late on a Saturday the next week's ephemeris is already on the air, its
    # reference times at zero of that week. The record carries the week of
    # `toe`, and the transmission time on that week's count.
    ahead = navigation_times('G'; week = 2124, transmission_time = 604000, toe = 0, toc = 0)
    @test ahead.week == 2125
    @test ahead.toc == DateTime(2020, 9, 27)
    @test ahead.transmission_time == 604000 - 604800

    # Just after the week crossover the last one of the old week may still
    # be. A Galileo week is counted from GPS week 1024, and written aligned
    # with it.
    behind = navigation_times(
        'E';
        week = 2124 - 1024,
        transmission_time = 30,
        toe = 597600,
        toc = 597600,
    )
    @test behind.week == 2123
    @test behind.toc == DateTime(2020, 9, 13) + Second(597600)
    @test behind.transmission_time == 30 + 604800

    # BDS counts its own weeks from 2006-01-01: week 730 begins on
    # 2019-12-29, and four days into it is 2020-01-02 BDT.
    bds = navigation_times(
        'C';
        week = 730,
        transmission_time = 345665,
        toe = 345600,
        toc = 345600,
    )
    @test bds == (; week = 730, toc = DateTime(2020, 1, 2), transmission_time = 345665.0)

    # The clock and the ephemeris reference times are placed in their weeks
    # each on its own.
    split = navigation_times(
        'G';
        week = 2124,
        transmission_time = 604000,
        toe = 0,
        toc = 597600,
    )
    @test split.week == 2125
    @test split.toc == DateTime(2020, 9, 20) + Second(597600)

    @test_throws ArgumentError navigation_times(
        'R';
        week = 2124,
        transmission_time = 0,
        toe = 0,
        toc = 0,
    )

    # The fields go straight into a record.
    eph = GPSEphemeris(;
        (f => getfield(gps_eph, f) for f in fieldnames(GPSEphemeris))...,
        navigation_times(
            'G';
            week = 2124,
            transmission_time = 82596,
            toe = 345600,
            toc = 345600,
        )...,
    )
    @test (eph.week, eph.toc, eph.transmission_time) ==
          (2124, DateTime(2020, 9, 24), 82596.0)
end

@testset "the time mark of an ionospheric correction" begin
    @test ionosphere_time_mark(0) == 'A'
    @test ionosphere_time_mark(3599.9) == 'A'
    @test ionosphere_time_mark(23 * 3600) == 'X'
    # Seconds of the week and seconds of the day give the same hour.
    @test ionosphere_time_mark(4 * 86400 + 12 * 3600) == 'M'
    @test ionosphere_time_mark(12 * 3600) == 'M'
    @test IonosphericCorrection(
        "BDSA",
        (1.0, 2.0, 3.0, 4.0);
        time_mark = ionosphere_time_mark(345665),
        sv_id = 21,
    ).time_mark == 'A'
end

@testset "the time system of an observation file" begin
    @test time_system(['G']) == "GPS"
    @test time_system(['E']) == "GAL"
    @test time_system(['C']) == "BDT"
    # A mixed file is in GPS time, whichever constellation it carries most of.
    @test time_system(['C', 'G']) == "GPS"
    @test time_system(RinexObsHeader(obs_codes = ['C' => ["C2I"]])) == "BDT"
    @test time_system(RinexObsHeader(obs_codes = ['C' => ["C2I"], 'E' => ["C1C"]])) == "GPS"
end

@testset "the time of an observation epoch" begin
    # GPS week 2124 starts on Sunday 2020-09-20.
    t = epoch_time("GPS"; week = 2124, time_of_week = 4 * 86400 + 0.25)
    @test t == (; time = DateTime(2020, 9, 24, 0, 0, 0, 250), fractional_second = 0.0)
    # Below the millisecond the rest goes into the fractional second.
    t = epoch_time("GPS"; week = 2124, time_of_week = 30.1234567)
    @test t.time == DateTime(2020, 9, 20, 0, 0, 30, 123)
    @test t.fractional_second ≈ 4.567e-4 atol = 1e-12
    @test ObsEpoch(t.time, SatObs[]; t.fractional_second) isa ObsEpoch

    # Galileo counts its weeks from GPS week 1024, BDS from 2006-01-01: week
    # 730 begins on 2019-12-29.
    @test epoch_time("GAL"; week = 2124 - 1024, time_of_week = 0).time ==
          DateTime(2020, 9, 20)
    @test epoch_time("BDT"; week = 730, time_of_week = 86400).time == DateTime(2019, 12, 30)

    # A time of week outside the week lies in the week before or after.
    @test epoch_time("BDT"; week = 731, time_of_week = -14).time ==
          DateTime(2020, 1, 5) - Second(14)
    @test epoch_time("GPS"; week = 2124, time_of_week = 604800 + 1.5).time ==
          DateTime(2020, 9, 27, 0, 0, 1, 500)
    @test_throws ArgumentError epoch_time("GLO"; week = 2124, time_of_week = 0)
end
