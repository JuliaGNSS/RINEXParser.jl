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

@testset "a rejected record leaves the file as it was" begin
    # Validation used to happen as the record was written, so a value the
    # writer could not hold left a fragment of it in the file - and the next
    # record was appended behind the fragment, where nothing tells the two
    # apart.
    header = RinexObsHeader(obs_types = ['G' => ["C1C", "L1C"]])
    io = IOBuffer()
    writer = RinexObsWriter(io, header)
    good =
        ObsEpoch(DateTime(2020, 1, 1, 0, 0, 0), [SatObs('G', 1, [ObsValue(1.0), nothing])])
    write_epoch!(writer, good)
    # The second satellite of the epoch carries a value of more columns than
    # its field, which is found before the epoch line is written.
    bad = ObsEpoch(
        DateTime(2020, 1, 1, 0, 0, 30),
        [
            SatObs('G', 1, [ObsValue(1.0), nothing]),
            SatObs('G', 2, [ObsValue(1e14), nothing]),
        ],
    )
    @test_throws ArgumentError write_epoch!(writer, bad)
    # And so is a satellite carrying the wrong number of observations.
    @test_throws ArgumentError write_epoch!(
        writer,
        ObsEpoch(DateTime(2020, 1, 1, 0, 1, 0), [SatObs('G', 3, [ObsValue(1.0)])]),
    )
    write_epoch!(writer, ObsEpoch(DateTime(2020, 1, 1, 0, 1, 30), good.satellites))
    close(writer)
    body = body_lines(readlines(seekstart(io)))
    # Two epochs of one satellite each, and nothing of the rejected ones.
    @test length(body) == 4
    @test [l[1] for l in body] == ['>', 'G', '>', 'G']
    @test body[3][1:26] == "> 2020 01 01 00 01 30.0000"

    # The same for an ephemeris, whose record is eight lines long.
    io = IOBuffer()
    writer = RinexNavWriter(io, RinexNavHeader(satellite_system = 'G'))
    write_ephemeris!(writer, gps_eph)
    # Broadcast orbit line 6 of this one carries a value that is not finite.
    @test_throws ArgumentError write_ephemeris!(
        writer,
        modify(gps_eph; prn = 14, tgd = NaN),
    )
    write_ephemeris!(writer, modify(gps_eph; prn = 15))
    close(writer)
    body = body_lines(readlines(seekstart(io)))
    @test length(body) == 16
    @test [body[1][1:3], body[9][1:3]] == ["G13", "G15"]

    # A rejected epoch does not write the header either, so a writer that
    # never saw a valid record still produces a header-only file.
    io = IOBuffer()
    RinexObsWriter(io, RinexObsHeader(obs_types = ['G' => ["C1C"]])) do w
        @test_throws ArgumentError write_epoch!(
            w,
            ObsEpoch(DateTime(2020, 1, 1), [SatObs('G', 1, [ObsValue(1e14)])]),
        )
    end
    @test isempty(body_lines(readlines(seekstart(io))))
end

@testset "header fields keep to their own columns" begin
    types = ['G' => ["C1C"]]
    # A field of more columns than the record gives it does not extend the
    # record: it overwrites the field that follows, or pushes the label out
    # of columns 61-80. Checked when the writer is created, so it does not
    # surface from the lazy header write inside `close`.
    @test_throws ArgumentError RinexObsWriter(
        IOBuffer(),
        RinexObsHeader(obs_types = types, receiver_number = "X"^21),
    )
    @test_throws ArgumentError RinexObsWriter(
        IOBuffer(),
        RinexObsHeader(obs_types = types, marker_name = "X"^61),
    )
    @test_throws ArgumentError RinexObsWriter(
        IOBuffer(),
        RinexObsHeader(obs_types = types, agency = "X"^41),
    )
    @test_throws ArgumentError RinexNavWriter(IOBuffer(), RinexNavHeader(program = "X"^21))
    # The widest value each field holds is still written.
    lines = written_lines(
        RinexObsWriter,
        RinexObsHeader(
            obs_types = types,
            marker_name = "X"^60,
            receiver_number = "R"^20,
            receiver_type = "T"^20,
            receiver_version = "V"^20,
        ),
    ) do writer
    end
    @test all(length(l) <= 80 for l in lines)
    @test label(lines[3]) == "MARKER NAME"
    @test content(lines[6]) == "R"^20 * "T"^20 * "V"^20
end

@testset "a header assigned after the writer is still checked" begin
    # The header is documented as assignable until it is written, so the
    # fields have to be checked where they are used, not only where the
    # writer was created: a 21-column receiver number would otherwise reach
    # the file and push the receiver type one column out of its own.
    io = IOBuffer()
    writer = RinexObsWriter(io, RinexObsHeader(obs_types = ['G' => ["C1C"]]))
    writer.header.receiver_number = "R"^21
    epoch = ObsEpoch(DateTime(2020, 1, 1), [SatObs('G', 1, [ObsValue(1.0)])])
    @test_throws ArgumentError write_epoch!(writer, epoch)
    # And on the path that writes the header from `close`.
    io = IOBuffer()
    writer = RinexObsWriter(io, RinexObsHeader(obs_types = ['G' => ["C1C"]]))
    writer.header.marker_name = "X"^61
    @test_throws ArgumentError close(writer)

    io = IOBuffer()
    writer = RinexNavWriter(io, RinexNavHeader())
    writer.header.program = "P"^21
    @test_throws ArgumentError write_ephemeris!(writer, gps_eph)
end
