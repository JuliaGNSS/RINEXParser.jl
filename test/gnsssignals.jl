# The signals and time systems of GNSSSignals, named through its package
# extension.

@testset "every signal has a RINEX observation code" begin
    # Enumerated from GNSSSignals rather than listed here, so a signal added
    # upstream forces the decision instead of quietly going uncovered.
    leaves(T) = isabstracttype(T) ? vcat(map(leaves, subtypes(T))...) : [T]
    signals = filter(!isnothing, map(leaves(AbstractGNSSSignal)) do T
        try
            T()
        catch
            nothing
        end
    end)
    @test length(signals) >= 20
    for signal in signals
        if get_signal_id(signal) == :GalileoE5aQP
            # A signal the format itself cannot name says so.
            error = try
                observation_code('C', signal)
            catch exception
                exception
            end
            @test error isa ArgumentError
            @test occursin("OS SIS ICD Issue 2.2", sprint(showerror, error))
            continue
        end
        system = RINEXParser.satellite_system(signal)
        @test system in ('G', 'E', 'C')
        # Every code is one RINEX 3.05 defines for its constellation, which
        # the writer checks a header against.
        for type in ('C', 'L', 'D', 'S')
            code = observation_code(type, signal)
            @test RINEXParser.check_observation_code(system, code) == code
            @test first(code) == type
        end
    end

    # The codes of the constellation code tables, spot-checked where the
    # band digit is not the obvious one: B1I is `2I`, not the `1I` RINEX 3.02
    # used, and B2b shares band 7 with Galileo's E5b while B3 shares band 6
    # with E6.
    @test observation_code('C', GPSL1CA()) == "C1C"
    @test observation_code('L', BeiDouB1I()) == "L2I"
    @test observation_code('C', BeiDouB3I()) == "C6I"
    @test observation_code('C', BeiDouB1C_P()) == "C1P"
    @test observation_code('C', BeiDouB2aQ()) == "C5P"
    @test observation_code('C', BeiDouB2bI()) == "C7D"
    @test observation_code('C', GalileoE5bQ()) == "C7Q"
    @test observation_code('C', GalileoE1C_BOC11()) == "C1C"
    @test_throws ArgumentError observation_code('X', GPSL1CA())

    # A header of the codes is one the writer takes.
    obs_codes = ['G' => [observation_code(t, GPSL1CA()) for t in ('C', 'L', 'D', 'S')]]
    @test RinexObsWriter(IOBuffer(), RinexObsHeader(; obs_codes)) isa RinexObsWriter
end

@testset "the GNSSSignals time system of a RINEX time system" begin
    @test gnss_time_system("GPS") == GNSSSignals.GPST()
    @test gnss_time_system("GAL") == GNSSSignals.GST()
    @test gnss_time_system("BDT") == GNSSSignals.BDT()
    @test_throws ArgumentError gnss_time_system("GLO")
    # Of the epochs of a file: GPS time for a mixed one.
    @test gnss_time_system(['C']) == GNSSSignals.BDT()
    @test gnss_time_system(['C', 'E']) == GNSSSignals.GPST()
    @test gnss_time_system(RinexObsHeader(obs_codes = ['E' => ["C1C"]])) ==
          GNSSSignals.GST()
    # And back, for every one.
    for code in ("GPS", "GAL", "BDT")
        @test time_system(gnss_time_system(code)) == code
    end
    # The time system of a signal's measurements has a code.
    @test time_system(get_time_system(BeiDouB1I())) == "BDT"
end

@testset "the obs_codes of a header from its signals" begin
    obs_codes = observation_codes([GPSL1CA(), GalileoE1B(), GPSL5Q()])
    @test obs_codes == [
        'G' => ["C1C", "L1C", "D1C", "S1C", "C5Q", "L5Q", "D5Q", "S5Q"],
        'E' => ["C1B", "L1B", "D1B", "S1B"],
    ]
    # A header of them is one the writer takes, phase shift given.
    header = RinexObsHeader(;
        obs_codes,
        phase_shifts = [PhaseShift('G', "L5Q", phase_correction('G', "L5Q"))],
    )
    @test RinexObsWriter(IOBuffer(), header) isa RinexObsWriter
    # A shared code is declared once.
    @test observation_codes([GalileoE1B(), GalileoE1B_BOC11()]) ==
          ['E' => ["C1B", "L1B", "D1B", "S1B"]]
    @test observation_codes([BeiDouB1I()]; types = ('C', 'S')) == ['C' => ["C2I", "S2I"]]
    @test isempty(observation_codes(AbstractGNSSSignal[]))
    @test_throws ArgumentError observation_codes([GPSL1CA()]; types = ('X',))
end

@testset "the epoch time of a GNSSSignals time system" begin
    for code in ("GPS", "GAL", "BDT")
        @test epoch_time(gnss_time_system(code); week = 730, time_of_week = 86400.25) ==
              epoch_time(code; week = 730, time_of_week = 86400.25)
    end
    @test epoch_time(GNSSSignals.BDT(); week = 730, time_of_week = 86400).time ==
          DateTime(2019, 12, 30)
end
