# The RINEX long filename convention, RINEX 3.05 appendix A1 and RINEX 4.02
# section 8.1 (identical apart from wording):
#
#     XXXXMRCCC_K_YYYYDDDHHMM_PPU_FFU_DT.FMT[.gz]
#     └───┬───┘ │ └────┬────┘ └┬┘ └┬┘ └┬┘ └┬┘ └┬┘
#       site  source  start  period │  data │ compression
#                      time    data frequency│
#                                          format
#
# Every field of the main body is fixed width, zero padded and upper-case
# ASCII, the fields are separated by underscores, and the format and
# compression extensions are lower case and separated by periods. The
# data-frequency field is mandatory for observation and meteorological data
# and is not used by navigation files; the compression field is optional.

# The country code has no value for "unknown" in the spec, which expects an
# ISO 3166-1 alpha-3 code. "XXX" is unassigned in ISO 3166-1 and is what the
# archives use for a site whose country is not known.
const DEFAULT_COUNTRY = "XXX"

const DATA_SOURCES =
    ('R' => "from receiver data", 'S' => "from a data stream", 'U' => "unknown")

const FILE_KINDS = ('O' => "observation", 'N' => "navigation", 'M' => "meteorological")

const FILE_FORMATS = ("rnx" => "RINEX", "crx" => "Hatanaka compressed RINEX")

# Compression methods the spec names: gzip, bzip2 and zip.
const COMPRESSIONS = ("gz", "bz2", "zip")

# Units of the file-period field, largest first. The spec gives 15M, 01H,
# 01D, 01Y and 00U, so a period is written in the largest unit it is an exact
# multiple of. `Year` is kept out of this table because it is not a fixed
# number of seconds and so cannot take part in the divisibility search.
const PERIOD_UNITS = ('D' => Day, 'H' => Hour, 'M' => Minute)

# Units of the data-frequency field. Below one second the field counts a
# rate - 05Z is 5 Hz and 01C is 100 Hz - and from one second on it counts an
# interval: 30S, 05M, 01H, 01D. Both are searched largest unit first, which
# is what the spec's examples are written in.
const FREQUENCY_RATE_UNITS = ('C' => 100.0, 'Z' => 1.0)
const FREQUENCY_INTERVAL_UNITS = ('D' => 86400.0, 'H' => 3600.0, 'M' => 60.0, 'S' => 1.0)

# The nine-character site identification, which is also what RINEX 3 expects
# in the MARKER NAME record, so a marker name that is one is taken apart
# rather than mangled into a station name.
const SITE_IDENTIFICATION = r"^([A-Za-z0-9]{4})([0-9])([0-9])([A-Za-z]{3})$"

const LONG_FILENAME = r"""
    ^([A-Za-z0-9]{4})([0-9])([0-9])([A-Za-z]{3})   # site
    _([A-Za-z])                                    # data source
    _(\d{4})(\d{3})(\d{2})(\d{2})                  # start time
    _(\d{2})([A-Za-z])                             # file period
    (?:_(\d{2})([A-Za-z]))?                        # data frequency
    _([A-Za-z])([A-Za-z])                          # data type
    \.([A-Za-z]{3})                                # format
    (?:\.([A-Za-z0-9]{2,3}))?                      # compression
    $"""x

"""
    RinexFileName(; station, start_time, kwargs...)
    RinexFileName(name::AbstractString)
    RinexFileName(header, start_time; kwargs...)

A RINEX long filename (RINEX 3.05 appendix A1), the naming convention of
RINEX 3.02 and later:

    ALGO00CAN_R_20121601000_01D_30S_MO.rnx

The fields are

  - `station`, `monument`, `receiver`, `country`: the nine-character site
    identification `XXXXMRCCC` - the four-character site designation, the
    monument and receiver number `0-9` at that site, and the ISO 3166-1
    alpha-3 country or region code.
  - `data_source`: `'R'` for a file written from receiver data, `'S'` for one
    written from a data stream, `'U'` if that is unknown.
  - `start_time`: the nominal start time of the first record, in the time
    system of the file. The field holds the day of year and the hour and
    minute of the day and has no seconds, so the start time is kept floored
    to the minute - the record says no more than the name does.
  - `period`: the intended collection period as a `Dates.Period` - `Day(1)`,
    `Hour(1)`, `Minute(15)`, `Year(1)`, or any sum of periods of a fixed
    length - or `nothing` for the `00U` of a period that is not specified. It
    is kept as the single period its field holds, `Day(1) + Hour(12)` as the
    `Hour(36)` the name says.
  - `interval`: the sampling interval in seconds, written as the data
    frequency (`30S`, `01S`, `05M`, `05Z` for 5 Hz, `01C` for 100 Hz), or
    `nothing` for `00U`. Navigation file names have no such field and require
    `nothing`.
  - `system`, `kind`: the two-character data type, e.g. `'G'` and `'O'` for
    `GO` (GPS observation), `'M'` and `'N'` for `MN` (mixed navigation).
    `system` is a constellation character or `'M'` for a mixed file; `kind`
    is `'O'`, `'N'` or `'M'` (meteorological).
  - `format`: `"rnx"` for RINEX, `"crx"` for Hatanaka compressed RINEX.
  - `compression`: `"gz"`, `"bz2"`, `"zip"`, or `nothing` for a file that is
    not compressed.

Every field is checked when the name is constructed - there is no way to
build one that holds a value its field has no room for - so a name that
exists is a name that renders, whether that is into a path or into the report
of a failing test.

`print` and `string` render the name, so it goes straight into a path:

    joinpath(directory, string(name))

The forms taking a [`RinexObsHeader`](@ref) or [`RinexNavHeader`](@ref) fill
the fields the header knows - the site from its marker name, the data type
from its constellations, the data frequency from its interval - so that a
writer does not have to assemble a name of its own; see
[`rinex_filename`](@ref). A name is read back with `parse(RinexFileName, name)`.
"""
struct RinexFileName
    station::String
    monument::Int
    receiver::Int
    country::String
    data_source::Char
    start_time::DateTime
    period::Union{Nothing,Dates.Period}
    interval::Union{Nothing,Float64}
    system::Char
    kind::Char
    format::String
    compression::Union{Nothing,String}

    # Every field is checked here, in the only constructor there is: a name
    # that exists is a name that can be written out, so rendering one - which
    # `show` does too - cannot fail on a value a field never had room for.
    function RinexFileName(
        station,
        monument,
        receiver,
        country,
        data_source,
        start_time,
        period,
        interval,
        system,
        kind,
        format,
        compression,
    )
        file_kind = check_file_kind(kind)
        # The field is absent from a navigation file name, so an interval
        # given for one would be dropped without a trace of it in the name.
        (file_kind != 'N' || isnothing(interval)) || throw(
            ArgumentError(
                "A navigation file name has no data-frequency field, so it cannot " *
                "carry the sampling interval $interval; pass interval = nothing",
            ),
        )
        seconds = check_interval(interval)
        new(
            check_station(station),
            check_site_digit(monument, "monument"),
            check_site_digit(receiver, "receiver"),
            check_country(country),
            check_data_source(data_source),
            # The field holds no seconds, so a start time that carries them
            # would make the name say less than the record does. The period and
            # the interval are kept as their own fields hold them for the same
            # reason - and encoding them is what rejects a value no unit of
            # those fields can express.
            floor(check_start_time(start_time), Minute),
            field_period(period),
            field_interval(seconds),
            check_file_system(system, file_kind),
            file_kind,
            check_format(format, file_kind),
            check_compression(compression),
        )
    end
end

RinexFileName(;
    station,
    monument = 0,
    receiver = 0,
    country = DEFAULT_COUNTRY,
    data_source = 'R',
    start_time,
    period = nothing,
    interval = nothing,
    system = 'M',
    kind = 'O',
    format = "rnx",
    compression = nothing,
) = RinexFileName(
    station,
    monument,
    receiver,
    country,
    data_source,
    start_time,
    period,
    interval,
    system,
    kind,
    format,
    compression,
)

RinexFileName(name::AbstractString) = parse(RinexFileName, name)

"""
    rinex_filename(; station, start_time, kwargs...) -> String
    rinex_filename(name::AbstractString) -> String
    rinex_filename(header::RinexObsHeader, start_time = header.time_of_first_obs; kwargs...) -> String
    rinex_filename(header::RinexNavHeader, start_time; kwargs...) -> String

The [`RinexFileName`](@ref) of the same arguments, rendered as a string - the
form a file is opened with:

    path = joinpath(directory, rinex_filename(header, start_time))
    RinexObsWriter(path, header) do writer
        write_epoch!(writer, epoch)
    end

The form taking a name renders it again, which normalises it: a path is cut
down to its last component, and the fields come out as the convention writes
them (see [`parse`](@ref)).
"""
rinex_filename(; keywords...) = string(RinexFileName(; keywords...))
rinex_filename(name::AbstractString) = string(RinexFileName(name))
rinex_filename(header::RinexObsHeader, start_time = header.time_of_first_obs; keywords...) =
    string(RinexFileName(header, start_time; keywords...))
rinex_filename(header::RinexNavHeader, start_time = nothing; keywords...) =
    string(RinexFileName(header, start_time; keywords...))

# Anything that reaches a field of the main body of the name has to be an
# upper-case ASCII letter or a digit.
is_name_character(character::AbstractChar) =
    isascii(character) && (isletter(character) || isdigit(character))

function check_station(station)
    name = uppercase(String(station))
    (length(name) == 4 && all(is_name_character, name)) || throw(
        ArgumentError(
            "A station is the four letters and digits of a RINEX site designation, " *
            "not \"$station\"; the RinexFileName(header, ...) forms derive one from " *
            "a marker name",
        ),
    )
    name
end

function check_site_digit(value::Integer, description)
    0 <= value <= 9 || throw(
        ArgumentError(
            "The $description number is $value, but the site identification of a " *
            "filename holds a single digit, 0 to 9",
        ),
    )
    value
end

function check_country(country)
    code = uppercase(String(country))
    (length(code) == 3 && all(c -> isascii(c) && isletter(c), code)) || throw(
        ArgumentError(
            "A country or region code is the three letters of an ISO 3166-1 alpha-3 " *
            "code, not \"$country\"",
        ),
    )
    code
end

function check_data_source(source::AbstractChar)
    data_source = uppercase(Char(source))
    any(first(pair) == data_source for pair in DATA_SOURCES) || throw(
        ArgumentError("A data source is $(describe_options(DATA_SOURCES)), not '$source'"),
    )
    data_source
end

check_start_time(::Nothing) = throw(
    ArgumentError(
        "A RINEX filename needs the start time of the file, which is not known here; " *
        "pass it as RinexFileName(header, start_time), or set the observation " *
        "header's time_of_first_obs before the name is derived from it",
    ),
)
function check_start_time(time)
    start_time = convert(DateTime, time)
    0 <= year(start_time) <= 9999 || throw(
        ArgumentError(
            "The start time $start_time does not fit the four-digit year of a RINEX " *
            "filename",
        ),
    )
    start_time
end

# The data frequency is given as the sampling interval the header carries,
# and answers a `Dates.Period` - which a reader of the field may well reach
# for - rather than leaving it to fail its conversion to seconds.
check_interval(::Nothing) = nothing
check_interval(interval::Real) = Float64(interval)
check_interval(interval) = throw(
    ArgumentError(
        "The sampling interval of the data frequency is a number of seconds, not a " *
        "$(typeof(interval)) - 30 for 30 s and 0.1 for 10 Hz, or nothing for a " *
        "frequency that is not specified",
    ),
)

function check_file_kind(kind::AbstractChar)
    file_kind = uppercase(Char(kind))
    any(first(pair) == file_kind for pair in FILE_KINDS) || throw(
        ArgumentError("A file kind is $(describe_options(FILE_KINDS)) data, not '$kind'"),
    )
    file_kind
end

function check_file_system(system::AbstractChar, kind::Char)
    file_system = uppercase(Char(system))
    # The data type of a meteorological file is MM: it carries no
    # constellation of its own.
    kind == 'M' &&
        file_system != 'M' &&
        throw(
            ArgumentError(
                "The data type of a meteorological file is MM, so its system " *
                "character is 'M', not '$system'",
            ),
        )
    file_system == 'M' || check_satellite_system(file_system)
    file_system
end

function check_format(format, kind::Char)
    file_format = lowercase(String(format))
    any(first(pair) == file_format for pair in FILE_FORMATS) || throw(
        ArgumentError(
            "A file format is $(describe_options(FILE_FORMATS)), not \"$format\"",
        ),
    )
    # Hatanaka compression differences observations of the same type and
    # satellite, so it applies to observation data only.
    file_format == "crx" &&
        kind != 'O' &&
        throw(
            ArgumentError(
                "\"crx\" is Hatanaka compressed observation data, so it cannot name " *
                "a $(kind_description(kind)) file",
            ),
        )
    file_format
end

check_compression(::Nothing) = nothing
function check_compression(compression)
    method = lowercase(String(compression))
    method in COMPRESSIONS || throw(
        ArgumentError(
            "A compression method is one of $(join(map(m -> "\"$m\"", COMPRESSIONS), ", ", " or ")), " *
            "not \"$compression\"; pass nothing for a file that is not compressed",
        ),
    )
    method
end

describe_options(options) =
    join(("'$key' ($description)" for (key, description) in options), ", ", " or ")

kind_description(kind::Char) =
    last(FILE_KINDS[findfirst(p -> first(p) == kind, FILE_KINDS)])

"""
    field_period(period) -> Union{Nothing,Dates.Period}
    field_interval(interval) -> Union{Nothing,Float64}

The period and the interval as their three-column fields hold them: the one
unit and count each is written in, read back. `Day(1) + Hour(12)` is kept as
the `Hour(36)` of its `36H`, so that the record of a name says no more and no
less than the name itself, and encoding them is at the same time what rejects
a value neither field can express.
"""
field_period(period) = period_of_field(period_field(period))
field_interval(interval) = interval_of_field(frequency_field(interval))

# Both fields are two digits and a unit character.
period_of_field(field::String) = parse_period(parse(Int, field[1:2]), field[3])
interval_of_field(field::String) = parse_interval(parse(Int, field[1:2]), field[3])

"""
    field_digits(count, unit, description) -> String

One three-column period or frequency field: `count` in two zero-padded
digits followed by the `unit` character. A count of more than two digits is
rejected, because the field is fixed width and a wider one would shift the
rest of the name.
"""
function field_digits(count::Integer, unit::Char, description)
    0 <= count <= 99 || throw(
        ArgumentError(
            "$description is $count of the unit '$unit', which does not fit the two " *
            "digits of the field, holding 0 to 99",
        ),
    )
    string(lpad(count, 2, '0'), unit)
end

"""
    period_field(period) -> String

The file-period field of a long filename, written in the largest of the
units minutes, hours, days and years that `period` is an exact multiple of:
`Day(1)` becomes `01D` and `Minute(15)` becomes `15M`. `nothing` becomes the
`00U` the spec provides for a file whose intended collection period is not
specified.

Any period of a fixed length is measured the same way, whichever unit it is
given in, and so is a sum of them: `Millisecond(60_000)` is `01M` and
`Day(1) + Hour(12)` is `36H`. A period of no length is not one of collection
and is rejected: the zero count of the field belongs to its `00U`.
"""
period_field(::Nothing) = "00U"
function period_field(period::Year)
    Dates.value(period) > 0 || period_positive_error(period)
    field_digits(Dates.value(period), 'Y', "The file period $period")
end
# `Dates.FixedPeriod` is Week down to Nanosecond: every period of a fixed
# length takes the same rule, rather than only the units the field itself has.
# `given` is the period as it was passed, which a compound one was summed from
# and which the messages name rather than the sum.
function period_field(period::Dates.FixedPeriod, given = period)
    # The zero count of the field belongs to its unit 'U': 00D would read as a
    # collection period of zero days, where the field has an encoding for a
    # period that is not specified. The data-frequency field rejects a zero
    # sampling interval for the same reason.
    Dates.value(period) > 0 || period_positive_error(given)
    # A period finer than a second has no unit here - the smallest unit of the
    # field is a minute - and could not be converted to seconds exactly either.
    iszero(period % Second(1)) || period_unit_error(given)
    seconds = Dates.value(Second(period))
    for (unit, unit_period) in PERIOD_UNITS
        scale = Dates.value(Second(unit_period(1)))
        seconds % scale == 0 &&
            return field_digits(seconds ÷ scale, unit, "The file period $given")
    end
    period_unit_error(given)
end
# Arithmetic on periods answers a compound period - `Day(1) + Hour(12)` - which
# is one period written in several units, so the fixed ones are summed back
# into one. A compound carrying a month or a year is rejected like the month or
# the year itself: it is no whole number of any single unit of the field.
function period_field(period::Dates.CompoundPeriod)
    all(part -> part isa Dates.FixedPeriod, period.periods) || period_no_unit_error(period)
    # Summed in nanoseconds, the one unit every fixed period converts to
    # exactly: a coarser one cannot hold the sub-millisecond part of a compound
    # period and would throw where the checks of the sum answer for it.
    period_field(sum(Nanosecond, period.periods; init = Nanosecond(0)), period)
end
period_field(period::Dates.Period) = period_no_unit_error(period)

@noinline period_positive_error(period) = throw(
    ArgumentError(
        "A file period of $period is not a period of collection; pass nothing for a " *
        "period that is not specified, which the field encodes as 00U",
    ),
)

@noinline period_unit_error(period) = throw(
    ArgumentError(
        "The file period $period is not a whole number of minutes, the smallest unit " *
        "of the field; its units are minutes, hours, days and years",
    ),
)

@noinline period_no_unit_error(period) = throw(
    ArgumentError(
        "A file period of $period has no unit in the field, whose units are minutes, " *
        "hours, days and years - pass a Minute, Hour, Day or Year, or nothing for a " *
        "period that is not specified",
    ),
)

"""
    frequency_field(interval) -> String

The data-frequency field of a long filename for a sampling interval of
`interval` seconds. An interval below one second is written as a rate in
Hertz or hundreds of Hertz (`05Z`, `01C`), an interval of a second or more
in the largest of the units seconds, minutes, hours and days it is an exact
multiple of (`30S`, `05M`, `01H`). `nothing` becomes `00U`, the frequency
that is not specified.
"""
frequency_field(::Nothing) = "00U"
function frequency_field(interval::Real)
    interval > 0 || throw(
        ArgumentError(
            "A data frequency needs a positive sampling interval, not $interval seconds",
        ),
    )
    units, quantity =
        interval < 1 ? (FREQUENCY_RATE_UNITS, 1 / interval) :
        (FREQUENCY_INTERVAL_UNITS, float(interval))
    for (unit, scale) in units
        count = whole_multiple(quantity, scale)
        isnothing(count) || return field_digits(
            count,
            unit,
            "The data frequency of a sampling interval of $interval seconds",
        )
    end
    throw(
        ArgumentError(
            "A sampling interval of $interval seconds is not a whole number of any " *
            "unit of the data-frequency field, which counts hundreds of Hertz, " *
            "Hertz, seconds, minutes, hours or days; pass interval = nothing for a " *
            "frequency that is not specified",
        ),
    )
end

"""
    whole_multiple(quantity, scale) -> Union{Nothing,Int}

`quantity / scale` if it is a whole positive number, `nothing` otherwise. An
interval that itself came out of a division does not always divide back
exactly - `1 / 49` seconds is 49.00000000000001 Hz in `Float64` - so the
quotient is compared with a tolerance instead of for equality.
"""
function whole_multiple(quantity::Float64, scale::Float64)
    count = quantity / scale
    (isfinite(count) && 0 < count < 1e15) || return nothing
    rounded = round(Int, count)
    rounded > 0 && isapprox(count, rounded; rtol = 1e-9) ? rounded : nothing
end

"""
    site_identification(name::RinexFileName) -> String

The nine-character site identification `XXXXMRCCC` the filename opens with.
"""
site_identification(name::RinexFileName) =
    string(name.station, name.monument, name.receiver, name.country)

# The day of year and the hour and minute of the day; the field has no
# seconds.
start_time_field(time::DateTime) = string(
    lpad(year(time), 4, '0'),
    lpad(dayofyear(time), 3, '0'),
    lpad(hour(time), 2, '0'),
    lpad(minute(time), 2, '0'),
)

function Base.print(io::IO, name::RinexFileName)
    fields = [
        site_identification(name),
        string(name.data_source),
        start_time_field(name.start_time),
        period_field(name.period),
    ]
    # Mandatory for observation and meteorological data, not used by
    # navigation files.
    name.kind == 'N' || push!(fields, frequency_field(name.interval))
    push!(fields, string(name.system, name.kind))
    print(io, join(fields, '_'), '.', name.format)
    isnothing(name.compression) || print(io, '.', name.compression)
    nothing
end

Base.show(io::IO, name::RinexFileName) = print(io, "RinexFileName(\"", name, "\")")

"""
    parse(RinexFileName, name) -> RinexFileName
    tryparse(RinexFileName, name) -> Union{RinexFileName,Nothing}

Read a RINEX long filename. `name` may be a path - only its last component
is looked at - and its fields may be lower case, although a name that is
written out is upper case as the convention prescribes.

Rendering the name again is not always the name that was read, so a name is
not a path: a field that is legal but not canonical is written in the unit
the convention uses for it, `24H` coming back as `01D` and a `60S` sampling
interval as `01M`. Keep the path itself if you need to open the file.

`tryparse` answers `nothing` where `parse` throws an `ArgumentError`, which
selects the file names of a directory that conform to the convention:

    filter(!isnothing, tryparse.(RinexFileName, readdir(directory)))

The selection is as strict as the spec, which is stricter than an archive:
the RINEX 2 short names (`algo1600.12o`) are a different convention and are
not read at all, a compression field of one character (`.Z`, unix compress)
is outside the two to three the convention gives it, a count of zero in a
unit other than `U` is not the way either field encodes what it does not
specify, and a navigation name that carries a data-frequency field it should
not have is rejected rather than read into a name that would be written back
without it.
"""
function Base.parse(::Type{RinexFileName}, name::AbstractString)
    fields = match(LONG_FILENAME, basename(name))
    isnothing(fields) && throw(
        ArgumentError(
            "\"$name\" is not a RINEX long filename " *
            "(XXXXMRCCC_K_YYYYDDDHHMM_PPU[_FFU]_DT.FMT[.gz])",
        ),
    )
    RinexFileName(;
        station = fields[1],
        monument = parse(Int, fields[2]),
        receiver = parse(Int, fields[3]),
        country = fields[4],
        data_source = only(fields[5]),
        start_time = day_of_year_time(
            parse(Int, fields[6]),
            parse(Int, fields[7]),
            parse(Int, fields[8]),
            parse(Int, fields[9]),
        ),
        period = parse_period(parse(Int, fields[10]), only(uppercase(fields[11]))),
        interval = isnothing(fields[12]) ? nothing :
                   parse_interval(parse(Int, fields[12]), only(uppercase(fields[13]))),
        system = only(fields[14]),
        kind = only(fields[15]),
        format = fields[16],
        compression = fields[17],
    )
end

function Base.tryparse(::Type{RinexFileName}, name::AbstractString)
    try
        parse(RinexFileName, name)
    catch exception
        exception isa ArgumentError ? nothing : rethrow()
    end
end

function day_of_year_time(year::Int, day_of_year::Int, hour::Int, minute::Int)
    0 < day_of_year <= daysinyear(year) ||
        throw(ArgumentError("Day of year $day_of_year is not a day of $year"))
    (hour < 24 && minute < 60) || throw(
        ArgumentError(
            "The start time of the name is hour $hour and minute $minute, which is " *
            "not a time of day",
        ),
    )
    DateTime(year) + Day(day_of_year - 1) + Hour(hour) + Minute(minute)
end

function parse_period(count::Int, unit::Char)
    unit == 'U' && return nothing
    unit == 'Y' && return Year(count)
    index = findfirst(pair -> first(pair) == unit, PERIOD_UNITS)
    isnothing(index) && throw(
        ArgumentError(
            "'$unit' is not a unit of the file-period field, whose units are 'M' " *
            "(minutes), 'H' (hours), 'D' (days), 'Y' (years) and 'U' (unspecified)",
        ),
    )
    last(PERIOD_UNITS[index])(count)
end

function parse_interval(count::Int, unit::Char)
    unit == 'U' && return nothing
    count > 0 || throw(
        ArgumentError(
            "A data frequency of $count of the unit '$unit' is not a sampling rate",
        ),
    )
    rate = findfirst(pair -> first(pair) == unit, FREQUENCY_RATE_UNITS)
    isnothing(rate) || return 1 / (count * last(FREQUENCY_RATE_UNITS[rate]))
    index = findfirst(pair -> first(pair) == unit, FREQUENCY_INTERVAL_UNITS)
    isnothing(index) && throw(
        ArgumentError(
            "'$unit' is not a unit of the data-frequency field, whose units are 'C' " *
            "(hundreds of Hertz), 'Z' (Hertz), 'S' (seconds), 'M' (minutes), 'H' " *
            "(hours), 'D' (days) and 'U' (unspecified)",
        ),
    )
    count * last(FREQUENCY_INTERVAL_UNITS[index])
end

"""
    check_data_type_keywords(keywords, description, source, kind)

Reject `system` and `kind` where a header determines them. The data type of a
name follows from the file, and a keyword the header overrules afterwards
would be dropped without a trace of it in the name - the same reason a
navigation file name rejects an interval instead of ignoring it.
"""
function check_data_type_keywords(keywords, description, source, kind::Char)
    for keyword in (:system, :kind)
        haskey(keywords, keyword) && throw(
            ArgumentError(
                "The data type of $description file name follows from its header, " *
                "where the system is $source and the kind is '$kind', so $keyword " *
                "cannot be given as a keyword: the name follows the file, not the " *
                "other way round",
            ),
        )
    end
    nothing
end

"""
    site_fields(marker_name) -> (station, monument, receiver, country)

The site fields of a filename derived from a marker name. RINEX 3 expects
the nine-character site identification in the `MARKER NAME` record, so a
marker name that is one is taken apart into its fields. Any other marker
name yields its letters and digits in upper case, cut to the four characters
of a station and padded with `'X'` if it is shorter - `"ROOF-1"` becomes
`"ROOF"` - at monument and receiver number 0 and the country code
`"$DEFAULT_COUNTRY"`, which are the fields a marker name does not carry.
"""
function site_fields(marker_name::AbstractString)
    site = match(SITE_IDENTIFICATION, marker_name)
    isnothing(site) || return (site[1], parse(Int, site[2]), parse(Int, site[3]), site[4])
    characters = filter(is_name_character, uppercase(marker_name))
    (rpad(first(characters, 4), 4, 'X'), 0, 0, DEFAULT_COUNTRY)
end

"""
    RinexFileName(header::RinexObsHeader, start_time = header.time_of_first_obs; kwargs...)

The name of the observation file `header` describes. The site fields come
from the header's marker name (see [`site_fields`](@ref)), the data type
from the constellations of its `obs_types` - a single one names its
constellation, several name a mixed file - and the data frequency from its
`interval`. `start_time` defaults to the header's `time_of_first_obs`, which
a lazily written header may not carry yet.

Any of the fields the header does not determine can be given as a keyword,
as can `marker_name` to derive the site from a name other than the header's;
`system` and `kind` are the header's own and are rejected as keywords rather
than dropped:

    rinex_filename(header, start_time; country = "DEU", period = Day(1))
"""
function RinexFileName(
    header::RinexObsHeader,
    start_time = header.time_of_first_obs;
    marker_name = header.marker_name,
    keywords...,
)
    check_data_type_keywords(
        keywords,
        "an observation",
        "the constellations of its obs_types",
        'O',
    )
    station, monument, receiver, country = site_fields(marker_name)
    RinexFileName(;
        station,
        monument,
        receiver,
        country,
        start_time,
        interval = header.interval,
        keywords...,
        system = system_character(first.(header.obs_types)),
        kind = 'O',
    )
end

"""
    RinexFileName(header::RinexNavHeader, start_time; kwargs...)

The name of the navigation file `header` describes: `MN` for a mixed
navigation file, or the constellation of its `satellite_system` if it is
pinned to one. A navigation header carries neither a marker name nor a time,
so `start_time` is required and the site fields default to the station
`UNKN` of an unknown marker; pass `marker_name` (the marker name of the
observation file of the same session) or the site fields themselves to name
the site:

    rinex_filename(nav_header, start_time; marker_name = obs_header.marker_name)

`system` and `kind` are the header's own here too: a navigation file of one
constellation is named by pinning the header's `satellite_system`, not by
naming the file something the file is not.
"""
function RinexFileName(
    header::RinexNavHeader,
    start_time = nothing;
    marker_name = "UNKNOWN",
    keywords...,
)
    check_data_type_keywords(keywords, "a navigation", "its satellite_system", 'N')
    station, monument, receiver, country = site_fields(marker_name)
    RinexFileName(;
        station,
        monument,
        receiver,
        country,
        start_time,
        keywords...,
        system = something(header.satellite_system, 'M'),
        kind = 'N',
    )
end
