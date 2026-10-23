@testset "the header is replaced through the writer until it is written" begin
    nav = RinexNavWriter(IOBuffer())
    @test !header_written(nav)
    @test set_header!(nav, RinexNavHeader(leap_seconds = 18)) === nav
    @test nav.header.leap_seconds == LeapSeconds(18)
    # Checked as on creation, so it cannot fail later inside `close`.
    @test_throws ArgumentError set_header!(nav, RinexNavHeader(satellite_system = 'X'))
    write_ephemeris!(nav, gps_eph)
    @test header_written(nav)
    @test_throws ArgumentError set_header!(nav, RinexNavHeader())
    close(nav)

    io = IOBuffer()
    obs = RinexObsWriter(io, RinexObsHeader(obs_codes = ['G' => ["C1C"]]))
    set_header!(obs, RinexObsHeader(obs_codes = ['G' => ["C1C"]], marker_name = "ROOF"))
    @test_throws ArgumentError set_header!(
        obs,
        RinexObsHeader(obs_codes = ['X' => ["C1C"]]),
    )
    close(obs)
    @test header_written(obs)
    lines = readlines(seekstart(io))
    @test content(lines[findfirst(l -> label(l) == "MARKER NAME", lines)]) == "ROOF"
    @test_throws ArgumentError set_header!(
        obs,
        RinexObsHeader(obs_codes = ['G' => ["C1C"]]),
    )
end

@testset "a value too wide for its field can be written blank" begin
    header =
        RinexObsHeader(obs_codes = ['G' => ["C1C", "L1C"]], clock_offset_applied = false)
    epoch = ObsEpoch(
        DateTime(2020, 1, 1),
        [
            SatObs(header, 'G', 1, "C1C" => 1e14, "L1C" => 2.0),
            SatObs(header, 'G', 2, "C1C" => 3.0),
        ];
        clock_offset = 1e5,
    )
    @test_throws ArgumentError RinexObsWriter(IOBuffer(), header; overflow = :skip)
    @test_throws ArgumentError written_lines(
        w -> write_epoch!(w, epoch),
        RinexObsWriter,
        header,
    )

    io = IOBuffer()
    writer = RinexObsWriter(io, header; overflow = :blank)
    # One warning per field, not one per epoch.
    @test_logs (:warn, r"clock offset") (:warn, r"G01.*1\.0e14") write_epoch!(writer, epoch)
    @test_logs write_epoch!(writer, epoch)
    close(writer)
    body = body_lines(readlines(seekstart(io)))
    # The epoch line ends with the satellite count, without the offset.
    @test body[1] == ">" * " 2020 01 01 00 00  0.0000000  0  2"
    @test body[2] == "G01" * " "^16 * @sprintf("%14.3f", 2.0) * "  "
    @test body[3] == "G02" * @sprintf("%14.3f", 3.0) * "  " * " "^16
end

@testset "a writer to a directory names its file when it closes" begin
    directory = mktempdir()
    obs_header =
        RinexObsHeader(obs_codes = ['G' => ["C1C"]], marker_name = "ROOF", interval = 1)
    epoch =
        ObsEpoch(DateTime(2020, 6, 8, 10, 0, 0), [SatObs(obs_header, 'G', 1, "C1C" => 1.0)])
    target = RinexDirectory(directory; country = "DEU", period = Day(1))

    obs = RinexObsWriter(target, obs_header)
    nav = RinexNavWriter(RinexDirectory(directory; session = obs, country = "DEU"))
    # Streamed into a file of its own until it can be named.
    temporary = file_path(obs)
    @test dirname(temporary) == directory && isfile(temporary)
    write_epoch!(obs, epoch)
    write_ephemeris!(nav, gps_eph)
    close(obs)
    close(nav)
    @test file_path(obs) == joinpath(directory, "ROOF00DEU_R_20201601000_01D_01S_GO.rnx")
    # The navigation file starts with the observations of its session.
    @test file_path(nav) == joinpath(directory, "ROOF00DEU_R_20201601000_00U_MN.rnx")
    @test sort(readdir(directory)) == basename.(sort([file_path(obs), file_path(nav)]))
    @test startswith(read(file_path(obs), String), "     3.05")

    # A name that is taken is not overwritten unless asked to; the data stays
    # where it was, and close reports it rather than failing the writer.
    again = RinexObsWriter(target, obs_header)
    temporary = file_path(again)
    write_epoch!(again, epoch)
    @test_logs (:warn, r"left at") close(again)
    @test file_path(again) == temporary && isfile(temporary)
    rm(temporary)
    replacing =
        RinexDirectory(directory; overwrite = true, country = "DEU", period = Day(1))
    again = RinexObsWriter(replacing, obs_header)
    write_epoch!(again, ObsEpoch(epoch.time, SatObs[]))
    close(again)
    @test file_path(again) == file_path(obs)
    @test count(startswith(">"), readlines(file_path(obs))) == 1
    @test !any(endswith(".part"), readdir(directory))

    # Without a record and a start time there is nothing to name or keep.
    RinexObsWriter(target, RinexObsHeader(obs_codes = ['G' => ["C1C"]])) do writer
    end
    nav = RinexNavWriter(RinexDirectory(directory))
    close(nav)
    @test isnothing(file_path(nav))
    @test length(readdir(directory)) == 2
    # One that can be named is kept, header only, as a writer to a path does.
    session = RinexObsWriter(target, RinexObsHeader(obs_codes = ['G' => ["C1C"]]))
    nav = RinexNavWriter(RinexDirectory(directory; session, overwrite = true))
    session.header.time_of_first_obs = epoch.time
    close(nav)
    @test isfile(file_path(nav))
    rm(file_path(nav))
    close(session)
    rm(file_path(session))

    # A navigation file of no session, or of one that got no epoch, starts
    # at the toc of its first record.
    for session in
        (nothing, RinexObsWriter(target, RinexObsHeader(obs_codes = ['G' => ["C1C"]])))
        nav = RinexNavWriter(RinexDirectory(directory; session))
        write_ephemeris!(nav, modify(gps_eph; toc = gps_eph.toc + Hour(2)))
        write_ephemeris!(nav, gps_eph)
        close(nav)
        @test basename(file_path(nav)) == "UNKN00XXX_R_20200010400_00U_MN.rnx"
        rm(file_path(nav))
        isnothing(session) || close(session)
    end
    @test length(readdir(directory)) == 2

    # The keywords are checked when the writer is created, before any file.
    files = length(readdir(directory))
    @test_throws ArgumentError RinexObsWriter(
        RinexDirectory(directory; country = "DE"),
        obs_header,
    )
    @test_throws ArgumentError RinexObsWriter(
        RinexDirectory(directory; system = 'E'),
        obs_header,
    )
    @test_throws ArgumentError RinexDirectory(directory; compression = "gz")
    @test_throws ArgumentError RinexObsWriter(
        RinexDirectory(directory; session = obs),
        obs_header,
    )
    @test_throws ArgumentError RinexNavWriter(
        RinexDirectory(directory; session = obs_header),
    )
    @test_throws ArgumentError RinexObsWriter(target, obs_header; overflow = :skip)
    @test_throws ArgumentError RinexDirectory(joinpath(directory, "missing"))
    @test length(readdir(directory)) == files

    # A path is where the file is, an IO has none.
    path = joinpath(directory, "data.rnx")
    writer = RinexObsWriter(path, obs_header)
    close(writer)
    @test file_path(writer) == path
    @test isnothing(file_path(RinexNavWriter(IOBuffer())))
    rm(directory; recursive = true)
end

@testset "closing after an error does not replace it" begin
    # A header assigned past `set_header!` fails only when it is written.
    @test_logs (:error, r"Closing the writer") @test_throws ErrorException RinexNavWriter(
        IOBuffer(),
    ) do writer
        writer.header = RinexNavHeader(satellite_system = 'X')
        error("the error of the body")
    end
    # Without an error of its own, the body's result is returned and the
    # error of close propagates.
    @test RinexNavWriter(w -> 42, IOBuffer()) == 42
    @test_throws ArgumentError RinexNavWriter(IOBuffer()) do writer
        writer.header = RinexNavHeader(satellite_system = 'X')
    end
end

@testset "the header is completed field by field through the writer" begin
    header = RinexObsHeader(obs_codes = ['G' => ["C1C"]])
    io = IOBuffer()
    obs = RinexObsWriter(io, header)
    @test set_header!(obs; approx_position = (1.0, 2.0, 3.0), leap_seconds = 18) === obs
    @test obs.header.approx_position == (1.0, 2.0, 3.0)
    @test obs.header.leap_seconds == LeapSeconds(18)
    # A copy is completed, so the header the writer was created with - which
    # its caller may still be reading - is not changed under it.
    @test isnothing(header.approx_position)
    @test obs.header !== header
    @test_throws ArgumentError set_header!(obs; antenna = "UNKNOWN")
    # Checked as a whole header is, and left as it was.
    @test_throws ArgumentError set_header!(obs; marker_type = "X"^21)
    @test obs.header.marker_type == "GEODETIC"
    close(obs)
    lines = readlines(seekstart(io))
    @test any(l -> label(l) == "LEAP SECONDS", lines)
    @test_throws ArgumentError set_header!(obs; leap_seconds = 18)

    nav = RinexNavWriter(IOBuffer())
    set_header!(nav; leap_seconds = 18)
    @test nav.header.leap_seconds == LeapSeconds(18)
    close(nav)
end

@testset "an ephemeris that does not fit its fields can be left out" begin
    @test_throws ArgumentError RinexNavWriter(IOBuffer(); overflow = :blank)
    bad = modify(gps_eph; af1 = NaN)
    @test_throws ArgumentError write_ephemeris!(RinexNavWriter(IOBuffer()), bad)

    io = IOBuffer()
    RinexNavWriter(io; overflow = :skip) do writer
        # Warned about once, however often the record is offered again.
        @test !(@test_logs (:warn, r"G13 is NaN.*left out") write_ephemeris!(writer, bad))
        @test !(@test_logs write_ephemeris!(writer, bad))
        @test write_ephemeris!(writer, gps_eph)
        # Only the values are checked this way; the record epoch and the
        # constellation of a pinned header are still errors of the caller.
        @test_throws ArgumentError write_ephemeris!(
            writer,
            modify(gps_eph; toc = DateTime(2020, 1, 1, 2, 0, 0, 500)),
        )
    end
    body = body_lines(readlines(seekstart(io)))
    @test length(body) == 8
    @test startswith(body[1], "G13 2020 01 01 02 00 00")
end
