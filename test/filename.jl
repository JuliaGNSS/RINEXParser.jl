@testset "long filenames" begin
    # Every filename example of RINEX 3.05 appendix A1, read and written back.
    spec_examples = [
        "ALGO00CAN_R_20121601000_15M_01S_GO.rnx.gz",
        "ALGO00CAN_R_20121601000_01H_05Z_MO.rnx.gz",
        "ALGO00CAN_R_20121601000_01D_30S_GO.rnx.gz",
        "ALGO00CAN_R_20121601000_01D_30S_MO.rnx.gz",
        "ALGO00CAN_R_20121600000_15M_GN.rnx.gz",
        "ALGO00CAN_R_20121600000_01H_GN.rnx.gz",
        "ALGO00CAN_R_20121600000_01D_MN.rnx.gz",
        "ALGO00CAN_R_20121601000_01D_01C_GO.rnx.gz",
        "ALGO00CAN_R_20121601000_01D_05Z_RO.rnx.gz",
        "ALGO00CAN_R_20121601000_01D_01S_EO.rnx.gz",
        "ALGO00CAN_R_20121601000_01D_05M_JO.rnx.gz",
        "ALGO00CAN_R_20121601000_01D_01H_CO.rnx.gz",
        "ALGO00CAN_R_20121601000_01D_01D_SO.rnx.gz",
        "ALGO00CAN_R_20121601000_01D_00U_MO.rnx.gz",
        "ALGO00CAN_R_20121601000_15M_01S_IO.rnx.gz",
        "ALGO00CAN_R_20121600000_01H_RN.rnx.gz",
        "ALGO00CAN_R_20121600000_01H_EN.rnx.gz",
        "ALGO00CAN_R_20121600000_01H_JN.rnx.gz",
        "ALGO00CAN_R_20121600000_01H_CN.rnx.gz",
        "ALGO00CAN_R_20121600000_01H_IN.rnx.gz",
        "ALGO00CAN_R_20121600000_01H_SN.rnx.gz",
        "ALGO00CAN_R_20121600000_01H_MN.rnx.gz",
        "ALGO00CAN_R_20121600000_01D_30M_MM.rnx.gz",
    ]
    @testset "$example" for example in spec_examples
        name = parse(RinexFileName, example)
        @test string(name) == example
        @test parse(RinexFileName, string(name)) == name
    end

    @testset "fields of a parsed name" begin
        name = parse(RinexFileName, "ALGO12CAN_S_20121601530_15M_05Z_MO.crx.gz")
        @test name.station == "ALGO"
        @test name.monument == 1
        @test name.receiver == 2
        @test name.country == "CAN"
        @test name.data_source == 'S'
        # 2012 is a leap year, so day 160 is the 8th of June.
        @test name.start_time == DateTime(2012, 6, 8, 15, 30)
        @test name.period == Minute(15)
        @test name.interval == 0.2
        @test name.system == 'M'
        @test name.kind == 'O'
        @test name.format == "crx"
        @test name.compression == "gz"
        @test RINEXParser.site_identification(name) == "ALGO12CAN"
    end

    @testset "a name is read from a path and written upper case" begin
        @test rinex_filename("data/2012/algo00can_r_20121601000_01d_30s_mo.RNX.GZ") ==
              "ALGO00CAN_R_20121601000_01D_30S_MO.rnx.gz"
    end

    @testset "tryparse answers nothing where parse throws" begin
        @test isnothing(tryparse(RinexFileName, "algo1600.12o"))
        @test isnothing(tryparse(RinexFileName, "ALGO00CAN_R_20121600000_01D_MN"))
        # Well formed, but not a day of the year given.
        @test isnothing(tryparse(RinexFileName, "ALGO00CAN_R_20133660000_01D_MN.rnx"))
        @test_throws ArgumentError parse(RinexFileName, "notes.txt")
        # Stricter than an archive, as the docstring says: unix compress is
        # one character where the convention gives the field two to three,
        # and a navigation name has no data-frequency field to carry.
        @test isnothing(tryparse(RinexFileName, "ALGO00CAN_R_20121600000_01D_MN.rnx.Z"))
        @test isnothing(tryparse(RinexFileName, "ALGO00CAN_R_20121600000_01D_30S_MN.rnx"))
    end

    @testset "show is the constructor of the name" begin
        name = parse(RinexFileName, "ALGO00CAN_R_20121600000_01D_MN.rnx")
        @test repr(name) == "RinexFileName(\"ALGO00CAN_R_20121600000_01D_MN.rnx\")"
        @test RinexFileName("ALGO00CAN_R_20121600000_01D_MN.rnx") == name
    end

    @testset "file period field" begin
        periods = [
            nothing => "00U",
            Minute(15) => "15M",
            Hour(1) => "01H",
            Day(1) => "01D",
            Year(1) => "01Y",
            # Reduced to the largest unit it is an exact multiple of.
            Hour(24) => "01D",
            Minute(120) => "02H",
            Week(1) => "07D",
            Second(900) => "15M",
            # A period of any fixed length, and a sum of them - which is what
            # arithmetic on periods answers - takes the same rule.
            Millisecond(60_000) => "01M",
            Day(1) + Hour(12) => "36H",
            Hour(1) + Minute(30) => "90M",
        ]
        @testset "$(repr(period))" for (period, field) in periods
            @test RINEXParser.period_field(period) == field
        end
        # A period the three columns of the field cannot express - each an
        # ArgumentError, including the compound period and the units below a
        # second that no unit of the field has.
        @test_throws ArgumentError RINEXParser.period_field(Second(30))
        @test_throws ArgumentError RINEXParser.period_field(Millisecond(500))
        @test_throws ArgumentError RINEXParser.period_field(Microsecond(500))
        @test_throws ArgumentError RINEXParser.period_field(Month(1))
        @test_throws ArgumentError RINEXParser.period_field(Year(1) + Day(1))
        @test_throws ArgumentError RINEXParser.period_field(Day(100))
        @test_throws ArgumentError RINEXParser.period_field(Day(1) + Minute(30))
        # A compound period is summed in nanoseconds, so a part finer than a
        # millisecond reaches the checks instead of failing to convert.
        @test_throws ArgumentError RINEXParser.period_field(Day(1) + Millisecond(1))
        @test_throws ArgumentError RINEXParser.period_field(Day(1) + Microsecond(500))
        @test_throws ArgumentError RINEXParser.period_field(Day(1) + Nanosecond(1))
        # The zero count of the field belongs to its unit 'U', so a period of
        # no length is not written as one of zero days.
        @test RINEXParser.period_field(nothing) == "00U"
        for empty in
            (Day(0), Second(0), Minute(0), Year(0), Dates.CompoundPeriod(), Day(-1))
            @test_throws ArgumentError RINEXParser.period_field(empty)
        end
        @test isnothing(tryparse(RinexFileName, "ABCD00XXX_R_20200010000_00D_00U_MO.rnx"))
        # The message names the period that was given, not the sum it was
        # measured as.
        @test occursin(
            "1 day, 30 minutes",
            sprint(showerror, try
                RINEXParser.period_field(Day(1) + Minute(30))
            catch exception
                exception
            end),
        )
    end

    @testset "data frequency field" begin
        intervals = [
            nothing => "00U",
            0.01 => "01C",   # 100 Hz
            0.005 => "02C",  # 200 Hz
            0.05 => "20Z",
            0.2 => "05Z",
            1.0 => "01S",
            30 => "30S",
            300.0 => "05M",
            3600.0 => "01H",
            86400.0 => "01D",
        ]
        @testset "$(repr(interval))" for (interval, field) in intervals
            @test RINEXParser.frequency_field(interval) == field
        end
        # An interval that came out of a division is still recognised.
        @test RINEXParser.frequency_field(1 / 49) == "49Z"
        @test RINEXParser.frequency_field(1 / 30) == "30Z"
        # No unit of the field counts these in two digits.
        @test_throws ArgumentError RINEXParser.frequency_field(100.0)
        @test_throws ArgumentError RINEXParser.frequency_field(1.5)
        @test_throws ArgumentError RINEXParser.frequency_field(1 / 150)
        @test_throws ArgumentError RINEXParser.frequency_field(0.0)
        @test_throws ArgumentError RINEXParser.frequency_field(-1.0)
    end

    @testset "a field cannot hold what it was not given" begin
        name(; keywords...) =
            RinexFileName(; station = "ABCD", start_time = DateTime(2020), keywords...)
        @test string(name()) == "ABCD00XXX_R_20200010000_00U_00U_MO.rnx"
        @test_throws ArgumentError name(station = "ABC")
        @test_throws ArgumentError name(station = "ABCDE")
        @test_throws ArgumentError name(station = "AB-D")
        @test_throws ArgumentError name(monument = 10)
        @test_throws ArgumentError name(receiver = -1)
        @test_throws ArgumentError name(country = "GERMANY")
        @test_throws ArgumentError name(country = "DE1")
        @test_throws ArgumentError name(data_source = 'X')
        @test_throws ArgumentError name(system = 'X')
        @test_throws ArgumentError name(kind = 'X')
        @test_throws ArgumentError name(format = "obs")
        @test_throws ArgumentError name(compression = "Z")
        # The data frequency is a number of seconds, not a period.
        @test_throws ArgumentError name(interval = Second(30))
        # A year of more than four digits would widen the start-time field.
        @test_throws ArgumentError name(start_time = DateTime(10000))
        # The data frequency is not part of a navigation file name, and
        # Hatanaka compression applies to observation data only.
        @test_throws ArgumentError name(kind = 'N', interval = 30.0)
        @test_throws ArgumentError name(kind = 'N', format = "crx")
        # A meteorological file is MM.
        @test_throws ArgumentError name(kind = 'M', system = 'G')
        # The start time is the one field with no default.
        @test_throws ArgumentError RinexFileName(; station = "ABCD", start_time = nothing)
    end

    @testset "lower case input is upper case in the name" begin
        name = RinexFileName(;
            station = "algo",
            country = "can",
            data_source = 's',
            start_time = Date(2012, 6, 8),
            period = Day(1),
            system = 'g',
            kind = 'o',
            format = "CRX",
            compression = "GZ",
        )
        @test string(name) == "ALGO00CAN_S_20121600000_01D_00U_GO.crx.gz"
    end

    @testset "the name of an observation file comes from its header" begin
        header = RinexObsHeader(;
            marker_name = "ROOF-1",
            obs_types = ['G' => ["C1C", "L1C"]],
            interval = 1.0,
        )
        # The marker name is not a site identification, so it yields the
        # station only; the file is GPS observation data at 1 Hz.
        @test rinex_filename(header, DateTime(2020, 1, 1, 0, 0, 30)) ==
              "ROOF00XXX_R_20200010000_00U_01S_GO.rnx"
        # Fields the header does not carry are given as keywords.
        @test rinex_filename(
            header,
            DateTime(2020, 1, 1);
            country = "DEU",
            period = Day(1),
            data_source = 'S',
            compression = "gz",
        ) == "ROOF00DEU_S_20200010000_01D_01S_GO.rnx.gz"
        # A marker name that is a site identification fills every site field,
        # and several constellations make a mixed file.
        mixed = RinexObsHeader(;
            marker_name = "ROOF12DEU",
            obs_types = ['G' => ["C1C"], 'E' => ["C1C"]],
            interval = 0.1,
        )
        @test rinex_filename(mixed, DateTime(2020, 1, 1); period = Hour(1)) ==
              "ROOF12DEU_R_20200010000_01H_10Z_MO.rnx"
        # The start time defaults to the header's, which the writer fills in
        # from the first epoch - so it has to be set before the name is taken.
        @test_throws ArgumentError rinex_filename(header)
        header.time_of_first_obs = DateTime(2020, 12, 31, 23, 59, 59)
        @test rinex_filename(header) == "ROOF00XXX_R_20203662359_00U_01S_GO.rnx"
        # A header without an interval names an unspecified frequency.
        header.interval = nothing
        @test rinex_filename(header) == "ROOF00XXX_R_20203662359_00U_00U_GO.rnx"
    end

    @testset "the name of a navigation file comes from its header" begin
        # A navigation header carries no marker name and no time of its own.
        @test rinex_filename(RinexNavHeader(), DateTime(2020, 1, 1)) ==
              "UNKN00XXX_R_20200010000_00U_MN.rnx"
        # The marker name of the observation file of the same session names
        # the site, and the navigation name carries no data frequency.
        @test rinex_filename(
            RinexNavHeader(; satellite_system = 'E'),
            DateTime(2020, 1, 1);
            marker_name = "ROOF12DEU",
            period = Day(1),
        ) == "ROOF12DEU_R_20200010000_01D_EN.rnx"
        @test_throws ArgumentError rinex_filename(RinexNavHeader())
    end

    @testset "there is no way past the checks" begin
        # The positional constructor is the checked one, so a name that no
        # field can hold does not come into being - and one that exists
        # renders, which is what show and a test report need of it.
        @test_throws ArgumentError RinexFileName(
            "TOOLONG",
            42,
            0,
            "GERMANY",
            'X',
            DateTime(2020),
            Month(1),
            nothing,
            'M',
            'O',
            "rnx",
            nothing,
        )
        @test length(methods(RinexFileName, Tuple{Vararg{Any,12}})) == 1
    end

    @testset "the record says no more than the name does" begin
        # The start-time field has no seconds, so it keeps none.
        name =
            RinexFileName(; station = "ABCD", start_time = DateTime(2020, 1, 1, 0, 0, 30))
        @test name.start_time == DateTime(2020, 1, 1)
        @test parse(RinexFileName, string(name)) == name
        # The period and the interval are kept as their fields hold them, so
        # a name means what it says however it was built.
        canonical = RinexFileName(;
            station = "ABCD",
            start_time = DateTime(2020),
            period = Day(1) + Hour(12),
            interval = 30.000000001,
        )
        @test canonical.period == Hour(36)
        @test canonical.interval == 30.0
        @test parse(RinexFileName, string(canonical)) == canonical
        @test RinexFileName(;
            station = "ABCD",
            start_time = DateTime(2020),
            period = Hour(24),
        ).period == Day(1)
        # Reading a name and writing it again normalises the units of a field
        # that is legal but not canonical.
        @test rinex_filename("ABCD00XXX_R_20200010000_24H_60S_MO.rnx") ==
              "ABCD00XXX_R_20200010000_01D_01M_MO.rnx"
    end

    @testset "the data type of a name is not a keyword of its header" begin
        obs = RinexObsHeader(;
            marker_name = "ROOF00DEU",
            obs_types = ['G' => ["C1C"]],
            interval = 1.0,
        )
        nav = RinexNavHeader()
        start_time = DateTime(2020, 1, 1)
        # Silently dropping these is what the interval of a navigation name
        # is not allowed to do either.
        @test_throws ArgumentError rinex_filename(obs, start_time; kind = 'N')
        @test_throws ArgumentError rinex_filename(obs, start_time; system = 'E')
        @test_throws ArgumentError rinex_filename(nav, start_time; kind = 'O')
        @test_throws ArgumentError rinex_filename(nav, start_time; system = 'E')
        # The fields the header does not determine stay keywords.
        @test rinex_filename(obs, start_time; station = "ZZZZ", interval = 30.0) ==
              "ZZZZ00DEU_R_20200010000_00U_30S_GO.rnx"
    end

    @testset "a signature per form of the name" begin
        # Untyped forwarding would leave rinex_filename without one, and
        # would carry anything at all a level deeper before failing.
        @test hasmethod(rinex_filename, Tuple{RinexObsHeader})
        @test hasmethod(rinex_filename, Tuple{RinexObsHeader,DateTime})
        @test hasmethod(rinex_filename, Tuple{RinexNavHeader,DateTime})
        @test hasmethod(rinex_filename, Tuple{AbstractString})
        @test !hasmethod(rinex_filename, Tuple{Int})
        @test_throws MethodError rinex_filename(42)
        @test rinex_filename("data/algo00can_r_20121600000_01d_mn.rnx") ==
              "ALGO00CAN_R_20121600000_01D_MN.rnx"
    end

    @testset "a station derived from a marker name" begin
        @test RINEXParser.site_fields("ROOF-1") == ("ROOF", 0, 0, "XXX")
        @test RINEXParser.site_fields("UNKNOWN") == ("UNKN", 0, 0, "XXX")
        @test RINEXParser.site_fields("roof") == ("ROOF", 0, 0, "XXX")
        @test RINEXParser.site_fields("R2") == ("R2XX", 0, 0, "XXX")
        @test RINEXParser.site_fields("") == ("XXXX", 0, 0, "XXX")
        @test RINEXParser.site_fields("ROOF12DEU") == ("ROOF", 1, 2, "DEU")
    end

    @testset "the name a file is written to" begin
        header = RinexObsHeader(;
            marker_name = "ROOF00DEU",
            obs_types = ['G' => ["C1C"]],
            interval = 1.0,
        )
        directory = mktempdir()
        path = joinpath(
            directory,
            rinex_filename(header, DateTime(2020, 1, 1); period = Day(1)),
        )
        RinexObsWriter(path, header) do writer
            write_epoch!(
                writer,
                ObsEpoch(DateTime(2020, 1, 1), [SatObs(writer, 'G', 2, "C1C" => 2.1e7)]),
            )
        end
        @test basename(path) == "ROOF00DEU_R_20200010000_01D_01S_GO.rnx"
        @test isfile(path)
        @test label(first(readlines(path))) == "RINEX VERSION / TYPE"
    end
end

@testset "an observation name carries its data-frequency field" begin
    # `00U` is how a name says the frequency is not specified; leaving the
    # field out is not, and reading it would come back as a different name.
    @test_throws ArgumentError parse(RinexFileName, "ALGO00CAN_R_20121601000_15M_GO.rnx")
    @test tryparse(RinexFileName, "ALGO00CAN_R_20121601000_15M_MO.rnx") === nothing
    @test string(parse(RinexFileName, "ALGO00CAN_R_20121601000_15M_00U_GO.rnx")) ==
          "ALGO00CAN_R_20121601000_15M_00U_GO.rnx"
    # A navigation name has no such field and is still read without one.
    @test string(parse(RinexFileName, "ALGO00CAN_R_20121600000_15M_GN.rnx")) ==
          "ALGO00CAN_R_20121600000_15M_GN.rnx"
end
