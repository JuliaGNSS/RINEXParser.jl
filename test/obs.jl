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

@testset "event flags that carry no observations are rejected" begin
    satellites = [SatObs('G', 1, [ObsValue(1.0)])]
    @test ObsEpoch(DateTime(2020, 1, 1), satellites; flag = 0).flag == 0
    # A power failure since the previous epoch is still an observation
    # record, so it is the one other flag this writer produces.
    @test ObsEpoch(DateTime(2020, 1, 1), satellites; flag = 1).flag == 1
    # Flags 2-5 introduce header records, which this writer does not write:
    # the satellite lines it would append are not what follows such a line.
    for flag in (2, 3, 4, 5, 6, -1)
        @test_throws ArgumentError ObsEpoch(DateTime(2020, 1, 1), satellites; flag = flag)
    end
end

@testset "the loss-of-lock indicator is three bits" begin
    @test ObsValue(1.0; lli = 7).lli == 7
    @test_throws ArgumentError ObsValue(1.0; lli = 8)
    # The signal strength keeps its own range, 0 included: it is what a
    # receiver reports for a projection it does not have yet.
    @test ObsValue(1.0; ssi = 9).ssi == 9
    @test ObsValue(1.0; ssi = 0).ssi == 0
    @test_throws ArgumentError ObsValue(1.0; ssi = 10)
end

@testset "the time of the first observation reaches the header" begin
    # Taken from the first epoch, it is assigned to the header, so that the
    # file can be named from the header once it has been written.
    header = RinexObsHeader(obs_types = ['G' => ["C1C"]], interval = 30.0)
    epoch = ObsEpoch(
        DateTime(2020, 6, 8, 10, 0, 0),
        [SatObs('G', 1, [ObsValue(1.0)])];
        fractional_second = 1.234e-4,
    )
    lines = written_lines(RinexObsWriter, header) do writer
        write_epoch!(writer, epoch)
        @test writer.header.time_of_first_obs == DateTime(2020, 6, 8, 10, 0, 0)
    end
    @test header.time_of_first_obs == DateTime(2020, 6, 8, 10, 0, 0)
    @test rinex_filename(header; station = "ROOF", country = "DEU") ==
          "ROOF00DEU_R_20201601000_00U_30S_GO.rnx"
    # The record carries the sub-millisecond part of the epoch the time came
    # from; the field is wide enough for it.
    first_obs = only(filter(l -> label(l) == "TIME OF FIRST OBS", lines))
    @test content(first_obs) == "  2020     6     8    10     0    0.0001234     GPS"

    # A time the header was given has no fractional part of its own.
    given = RinexObsHeader(
        obs_types = ['G' => ["C1C"]],
        time_of_first_obs = DateTime(2020, 6, 8, 10, 0, 0),
    )
    lines = written_lines(RinexObsWriter, given) do writer
        write_epoch!(writer, epoch)
    end
    first_obs = only(filter(l -> label(l) == "TIME OF FIRST OBS", lines))
    @test content(first_obs) == "  2020     6     8    10     0    0.0000000     GPS"
end

@testset "phase shifts say what was done to the carrier phase" begin
    # Section 5.2.12 gives the record three readings, and the file has to
    # pick one: a correction, a zero for data that arrived aligned, or a
    # blank for the reference signal of the band.
    header = RinexObsHeader(
        obs_types = ['G' => ["C1C", "L1C", "L2S", "L2W"], 'E' => ["L1C", "L8Q"]],
        phase_shifts = [
            PhaseShift('G', "L2S", -0.25),
            PhaseShift('G', "L2W", 0.0),
            PhaseShift('E', "L8Q", -0.25; satellites = [3, 5]),
        ],
    )
    lines = written_lines(RinexObsWriter, header) do writer
    end
    shifts = filter(l -> label(l) == "SYS / PHASE SHIFT", lines)
    @test content.(shifts) == [
        "G L1C",
        "G L2S -0.25000",
        "G L2W  0.00000",
        "E L1C",
        "E L8Q -0.25000  02 E03 E05",
    ]
    # The correction lands in the columns the format gives it, F8.5 after
    # the code, and the satellite count in columns 17-18.
    @test shifts[2][1:14] == "G L2S -0.25000"
    @test shifts[5][15:18] == "  02"

    # More than ten satellites continue on further records, indented past
    # the fields they repeat.
    many = RinexObsHeader(
        obs_types = ['G' => ["L2S"]],
        phase_shifts = [PhaseShift('G', "L2S", -0.25; satellites = 1:12)],
    )
    lines = written_lines(RinexObsWriter, many) do writer
    end
    shifts = filter(l -> label(l) == "SYS / PHASE SHIFT", lines)
    @test length(shifts) == 2
    @test content(shifts[1]) == "G L2S -0.25000  12 G01 G02 G03 G04 G05 G06 G07 G08 G09 G10"
    @test content(shifts[2]) == " "^18 * " G11 G12"

    # A shift naming a code the header does not declare is a typo, not a
    # record, and is caught when the writer is created.
    @test_throws ArgumentError RinexObsWriter(
        IOBuffer(),
        RinexObsHeader(
            obs_types = ['G' => ["L1C"]],
            phase_shifts = [PhaseShift('G', "L2S", -0.25)],
        ),
    )
    # The record corrects a carrier phase, not a pseudorange.
    @test_throws ArgumentError PhaseShift('G', "C1C", 0.0)
    @test_throws ArgumentError PhaseShift('X', "L1C", 0.0)
end

@testset "a phase shift that does not reach every satellite" begin
    # One code carries one record per group of satellites it corrects, so
    # every entry has to be written, not just the first one found.
    header = RinexObsHeader(
        obs_types = ['G' => ["L2S"]],
        phase_shifts = [
            PhaseShift('G', "L2S", -0.25; satellites = [1, 2]),
            PhaseShift('G', "L2S", 0.0; satellites = [3]),
        ],
    )
    lines = written_lines(RinexObsWriter, header) do writer
    end
    @test content.(filter(l -> label(l) == "SYS / PHASE SHIFT", lines)) ==
          ["G L2S -0.25000  02 G01 G02", "G L2S  0.00000  01 G03"]

    # A satellite cannot be told two corrections for one carrier phase.
    overlapping = RinexObsHeader(
        obs_types = ['G' => ["L2S"]],
        phase_shifts = [
            PhaseShift('G', "L2S", -0.25; satellites = [1, 2]),
            PhaseShift('G', "L2S", 0.0; satellites = [2, 3]),
        ],
    )
    @test_throws ArgumentError RinexObsWriter(IOBuffer(), overlapping)
    # An empty list already claims every satellite of the system.
    @test_throws ArgumentError RinexObsWriter(
        IOBuffer(),
        RinexObsHeader(
            obs_types = ['G' => ["L2S"]],
            phase_shifts = [PhaseShift('G', "L2S", -0.25), PhaseShift('G', "L2S", 0.0)],
        ),
    )
    # Two codes of the same system keep their own records.
    fine = RinexObsHeader(
        obs_types = ['G' => ["L2S", "L2W"]],
        phase_shifts = [PhaseShift('G', "L2S", -0.25), PhaseShift('G', "L2W", 0.0)],
    )
    @test RinexObsWriter(IOBuffer(), fine) isa RinexObsWriter
end

@testset "a phase shift keeps to the columns of its record" begin
    # The satellite identification is three columns, and the count of the
    # list two, so neither takes a number that would overflow them.
    @test_throws ArgumentError PhaseShift('G', "L2S", 0.0; satellites = [100])
    @test_throws ArgumentError PhaseShift('G', "L2S", 0.0; satellites = [0])
    @test_throws ArgumentError PhaseShift('G', "L2S", 0.0; satellites = 1:100)
    @test length(PhaseShift('G', "L2S", 0.0; satellites = 1:99).satellites) == 99
    # The list is a `Vector` inside an immutable shift, so it stays open to
    # `push!` after the constructor checked it; the header writer checks it
    # again rather than letting a number past its columns reach the file.
    shift = PhaseShift('G', "L2S", -0.25; satellites = [1])
    header = RinexObsHeader(obs_types = ['G' => ["L2S"]], phase_shifts = [shift])
    io = IOBuffer()
    writer = RinexObsWriter(io, header)
    push!(shift.satellites, 100)
    @test_throws ArgumentError close(writer)
    @test isempty(filter(l -> occursin("PHASE SHIFT", l), readlines(seekstart(io))))
    # And the same for a list grown past the two columns that count it.
    grown = PhaseShift('G', "L2S", -0.25; satellites = [1])
    writer = RinexObsWriter(
        IOBuffer(),
        RinexObsHeader(obs_types = ['G' => ["L2S"]], phase_shifts = [grown]),
    )
    append!(grown.satellites, 2:100)
    @test_throws ArgumentError close(writer)
    # F8.5 holds the corrections the ICDs define, not an arbitrary number.
    @test_throws ArgumentError PhaseShift('G', "L2S", 1000.0)
    # The constructor takes a `Real`, so the correction is converted before
    # it is measured against its field rather than after.
    @test PhaseShift('G', "L2S", 0).correction === 0.0
    @test PhaseShift('G', "L2S", -1 // 4).correction === -0.25
    @test PhaseShift('G', "L2S", Float32(-0.25)).correction === -0.25
end
