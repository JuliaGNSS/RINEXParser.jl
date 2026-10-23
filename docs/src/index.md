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
    obs_codes = ['G' => ["C1C", "L1C"]],
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

With GNSSDecoder loaded, [`rinex_ephemeris`](@ref) converts a decoded
navigation message into its record, [`has_rinex_ephemeris`](@ref) says
whether RINEX 3.05 has one for it, and [`add_header_records!`](@ref) collects
the header records it carries; with GNSSSignals loaded,
[`observation_code`](@ref) names the observables of a signal,
[`observation_codes`](@ref) the `obs_codes` of a header for a set of signals,
and [`gnss_time_system`](@ref) the time system of a file's epochs.
[`nav_satellite_system`](@ref) settles the `satellite_system` of a
navigation file from the constellations it may carry. A record built by
hand takes its week, `toc` and transmission time from
[`navigation_times`](@ref), and an observation epoch its time from
[`epoch_time`](@ref), given the time system as a RINEX code or, with
GNSSSignals loaded, as a GNSSSignals time system.
See the [API reference](@ref) for headers, correction records, and writer options.
