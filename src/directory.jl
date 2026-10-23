"""
    RinexDirectory(directory; session = nothing, overwrite = false, kwargs...)

A writer target that names its file by the long filename convention
(RINEX 3.05 appendix A1) in `directory`, from what the file holds when it is
closed rather than from what is known when it is opened:

    RinexObsWriter(RinexDirectory("/data"; country = "DEU", period = Day(1)), header) do writer
        write_epoch!(writer, epoch)
    end
    # /data/ROOF00DEU_R_20200010000_01D_01S_GO.rnx

The writer streams into a temporary file in `directory` and renames it to
its [`rinex_filename`](@ref) on `close`. An observation file takes its start
time from its header's `time_of_first_obs`, which the first epoch fills in.

A navigation header carries neither a time nor a marker name, so a
navigation file is named after `session`, the [`RinexObsWriter`](@ref) of
the same session: its start time is that writer's first epoch, and its site
is that writer's marker name, as they are when the navigation writer closes.

    obs = RinexObsWriter(RinexDirectory("/data"), obs_header)
    nav = RinexNavWriter(RinexDirectory("/data"; session = obs), nav_header)

Without a session, or with one that got no epoch, a navigation file starts
at the `toc` of the first ephemeris it wrote - the reference time of the
clock parameters, in the time system of that ephemeris, which the receiver
need not have reached yet when it decoded it.

`kwargs` are the keywords of [`RinexFileName`](@ref) for the fields the
header does not determine - `monument`, `receiver`, `country`,
`data_source`, `period`, `marker_name` and `start_time` - and are checked
when the writer is created. The file is written uncompressed RINEX, so
`format` and `compression` cannot be given.

A file of the name that already exists is replaced only with `overwrite = true`. Otherwise, or if the file cannot be moved, it is left at its
temporary path with a warning rather than an exception, so that `close`
neither loses the data nor fails a writer that wrote it.
[`file_path`](@ref) answers where the file ended up.

A file is kept whenever it can be named, a header-only one included, as a
writer to a path keeps it. A writer that wrote no record and has no start
time - an observation writer that got no epoch, a navigation writer whose
session got none either - cannot be named, holds no data, and is removed.
"""
struct RinexDirectory
    directory::String
    # A `RinexObsWriter`, which is defined after this target.
    session::Any
    overwrite::Bool
    keywords::Base.Pairs
    function RinexDirectory(directory::AbstractString, session, overwrite, keywords)
        isdir(directory) ||
            throw(ArgumentError("\"$directory\" is not a directory to write a file into"))
        for keyword in (:format, :compression)
            haskey(keywords, keyword) && throw(
                ArgumentError(
                    "A writer writes uncompressed RINEX, so the $keyword of its file " *
                    "name cannot be given",
                ),
            )
        end
        new(String(directory), session, overwrite, keywords)
    end
end
RinexDirectory(
    directory::AbstractString;
    session = nothing,
    overwrite::Bool = false,
    keywords...,
) = RinexDirectory(directory, session, overwrite, keywords)

# The file a writer to a `RinexDirectory` streams into until it is named.
function open_temporary(target::RinexDirectory)
    path = tempname(target.directory; cleanup = false) * ".rnx.part"
    path, open(path, "w")
end

"""
    name_file!(writer, had_records, start_time = nothing) -> Union{Nothing,String}

Move the closed file of a writer to a [`RinexDirectory`](@ref) from its
temporary path to its long filename and return that path. `start_time` is
the one the file falls back on when neither the target nor the header gives
one. A file that holds no record and cannot be named is removed, and
`nothing` returned. One that cannot be moved stays where it is, with a
warning, and its temporary path is returned: this runs inside `close`,
where an exception would fail the writer after its data was written.
"""
function name_file!(writer, had_records::Bool, start_time = nothing)
    target = writer.directory
    temporary = writer.path
    name = try
        file_name(writer.header, target; fallback = start_time)
    catch exception
        exception isa ArgumentError || rethrow()
        had_records || (rm(temporary; force = true); return nothing)
        return keep_temporary(temporary, exception)
    end
    path = joinpath(target.directory, name)
    try
        (ispath(path) && !target.overwrite) && throw(
            ArgumentError(
                "\"$path\" already exists; create the RinexDirectory with " *
                "overwrite = true to replace it",
            ),
        )
        mv(temporary, path; force = target.overwrite)
    catch exception
        exception isa InterruptException && rethrow()
        return keep_temporary(temporary, exception)
    end
    path
end

function keep_temporary(temporary, exception)
    @warn "The file was not named and is left at \"$temporary\"" exception
    temporary
end
