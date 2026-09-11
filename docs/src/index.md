# RINEXParser.jl

RINEXParser writes RINEX 3.05 observation and navigation files and builds
and parses RINEX long filenames. The core package depends only on Julia's
standard libraries.

## Write observations

Create a header declaring the observation codes, then pass epochs to a writer.
The writer accepts a path or an `IO`; the do-block form closes the writer even
if writing throws. The header is written with the first epoch, allowing metadata
to be filled in beforehand.

```@example observations
using RINEXParser, Dates

header = RinexObsHeader(;
    marker_name = "ROOF00DEU",
    obs_types = ['G' => ["C1C", "L1C"]],
    interval = 1.0,
)
epoch = ObsEpoch(
    DateTime(2020, 1, 1),
    [SatObs(header, 'G', 2, "C1C" => 21234567.890, "L1C" => 111583948.752)],
)
io = IOBuffer()
RinexObsWriter(io, header) do writer
    write_epoch!(writer, epoch)
end
println(String(take!(io)))
```

Pseudorange is in meters, carrier phase in cycles, Doppler in Hz, and signal
strength in dB-Hz. An absent or non-finite observation is written as a blank.
The caller supplies times in the file's time system; no automatic time-system
conversion is performed.

## File names

```@example observations
rinex_filename(header; period = Day(1))
```

[`RinexFileName`](@ref) validates and normalizes each field. Keep the original
path when opening an existing file: a normalized name need not match its spelling
on disk.

## Navigation

Construct a [`GPSEphemeris`](@ref), [`GalileoEphemeris`](@ref), or
[`BeiDouEphemeris`](@ref), and pass it to [`write_ephemeris!`](@ref).
The writer suppresses duplicate records. The type documentation specifies
units and time conventions for each constellation.

External record types can implement the [Ephemeris interface](@ref).
See the [API reference](@ref) for headers, correction records, and writer options.
