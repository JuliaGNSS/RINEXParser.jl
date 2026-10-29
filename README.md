# RINEXParser.jl

Streaming writer for RINEX 3.05 GNSS files: observation files (pseudorange,
carrier phase, Doppler, signal strength) and navigation files (broadcast
ephemerides plus ionosphere and time-system corrections), plus the long
filenames the files are named by.

The package is receiver-agnostic: it consumes plain record types and depends
on the standard library only. It follows the design of RTKLIB's `rinex.c` (a
standalone format library) combined with GNSS-SDR's runtime model: headers
are written lazily with the first record, observation epochs stream as they
happen, and ephemerides are deduplicated. Output has been cross-validated
against RTKLIB's RINEX reader. GPS, Galileo and BeiDou are implemented; the
record types carry the satellite-system character throughout, so further
constellations can be added without breaking the API.

See the [documentation](https://JuliaGNSS.github.io/RINEXParser.jl/dev/) for
the API reference, and [CONTRIBUTING.md](CONTRIBUTING.md) for formatting,
tests, and release conventions.

## Observation files

```julia
using RINEXParser, Dates

header = RinexObsHeader(;
    marker_name = "ROOF-1",
    receiver_type = "GNSSReceiver.jl",
    approx_position = (4141446.0, 604023.0, 4796597.6),  # ECEF, meters
    obs_codes = ['G' => ["C1C", "L1C", "D1C", "S1C"]],
    signal_strength_unit = "DBHZ",
    interval = 1.0,
    clock_offset_applied = false,
    leap_seconds = 18,
)

RinexObsWriter("data.obs", header) do writer
    write_epoch!(
        writer,
        ObsEpoch(
            DateTime(2020, 1, 1, 0, 0, 30),                   # epoch in GPS time
            [
                SatObs(
                    writer,
                    'G',
                    2,
                    "C1C" => 21234567.890,                        # pseudorange [m]
                    "L1C" => ObsValue(                            # carrier [cycles]
                        111583948.752;
                        lli = loss_of_lock_indicator(half_cycle = true),
                        ssi = signal_strength_indicator(45.2),
                    ),
                    "D1C" => -1234.567,                           # Doppler [Hz]
                    "S1C" => 45.2,                                # C/N0 [dB-Hz]
                ),
            ];
            clock_offset = -1.2e-4,                           # receiver clock [s]
        ),
    )
end
```

- `SatObs` places observations by the header's `obs_codes`, so they are
  given by code in any order. A value is a number, an `ObsValue` with the
  loss-of-lock and signal-strength indicators, or `nothing`; a value that is
  not finite is written blank.
- Carrier phases must be aligned with the reference signal of their band
  (Table A23). Name every phase code whose `phase_correction` is not zero in
  the header's `phase_shifts`, e.g. `PhaseShift('G', "L2S", -0.25)`, or the
  writer rejects the header; see `?PhaseShift`.
- Observation codes are checked against the codes RINEX 3.05 defines (Tables
  14-20): BDS B1I is `C2I`, not `C1I`.
- The header is written with the first epoch, which also fills in
  `time_of_first_obs`. Until then `set_header!(writer; approx_position,
  leap_seconds)` completes it, and `header_written(writer)` says whether it
  is too late.
- A file is in the time system of its constellation, GPS time for a mixed
  one (`time_system(header)`).
- A value too wide for its field is rejected with an `ArgumentError`, and the
  epoch is checked whole first, so the file stays as it was. A writer created
  with `overflow = :blank` writes such a value blank instead.

## Navigation files

```julia
header = RinexNavHeader(
    ionospheric_corrections = [
        IonosphericCorrection("GPSA", (α0, α1, α2, α3)),  # Klobuchar
        IonosphericCorrection("GPSB", (β0, β1, β2, β3)),
    ],
    time_system_corrections = [TimeSystemCorrection("GPUT", a0, a1, t_ot, week)],
    leap_seconds = 18,
)

RinexNavWriter("data.nav", header) do writer
    write_ephemeris!(writer, GPSEphemeris(;
        prn = 13,
        af0 = ..., af1 = ..., af2 = ...,
        iode = ..., crs = ..., deltan = ..., m0 = ...,
        # ... remaining Keplerian elements, see ?GPSEphemeris
        navigation_times('G'; week, transmission_time, toe, toc)...,
    ))
end
```

- `GalileoEphemeris` and `BeiDouEphemeris` write Galileo I/NAV and F/NAV and
  BDS D1/D2. `galileo_data_sources` and `galileo_sv_health` assemble the
  Galileo bit fields. BDS records are in BDT, and their ionospheric records
  carry the mandatory `time_mark` and `sv_id`.
- `navigation_times` derives a record's week, `toc` and transmission time
  from the broadcast week and seconds of week, across a week boundary too.
- An ephemeris that repeats a written record is skipped, so every decoded
  frame can be forwarded. The header can be replaced with
  `set_header!(writer, header)` until the first ephemeris is written, for
  ionosphere and UTC parameters that decode later.
- `satellite_system = 'G'` pins the file to one constellation; without it the
  file is mixed. `nav_satellite_system(systems)` gives the one for a file of
  `systems`.
- A value that does not fit its field, or is not finite, is rejected; a
  writer created with `overflow = :skip` leaves the record out instead.
- Other constellations can be written by implementing the
  [ephemeris interface](docs/src/ephemeris_interface.md).

## From GNSSDecoder and GNSSSignals

With GNSSDecoder.jl and GNSSSignals.jl loaded,
`rinex_ephemeris(decoder; approximate_year)` converts a decoded navigation
message into its record, and `add_header_records!(header, decoder;
approximate_year)` collects the corrections and leap seconds it carries.
`approximate_year`, the year of the observation, resolves the 1024-week
rollover of the GPS L1 C/A week through GNSSDecoder's `get_broadcast_week`;
it is required for every decoder, as there.

```julia
using GNSSDecoder, GNSSSignals, RINEXParser

header = RinexNavHeader(; satellite_system = 'G')
RinexNavWriter("data.nav"; overflow = :skip) do writer
    for decoder in decoders
        add_header_records!(header, decoder; approximate_year = 2026)
        header_written(writer) || set_header!(writer, header)
        eph = rinex_ephemeris(decoder; approximate_year = 2026)
        isnothing(eph) || write_ephemeris!(writer, eph)
    end
end
```

With GNSSSignals.jl loaded, `observation_code('L', BeiDouB1I()) == "L2I"`
names the observables of a signal, `observation_codes(signals)` the
`obs_codes` of a header for them, and `gnss_time_system(time_system(header))`
gives the GNSSSignals time system of a file's epochs; `epoch_time` takes it
too.

## File names

`rinex_filename` builds the long filename (RINEX 3.05 appendix A1) from the
header of the file; the fields the header does not determine are keywords:

```julia
rinex_filename(obs_header, start_time; country = "DEU", period = Day(1))
# "ROOF00DEU_R_20200010000_01D_01S_GO.rnx"
```

A receiver does not know the start time when it opens its files, so a
`RinexDirectory` target names the file when the writer closes. A navigation
file takes its start time and site from the observation writer of its
`session`:

```julia
obs = RinexObsWriter(RinexDirectory("/data"; country = "DEU", period = Day(1)), obs_header)
nav = RinexNavWriter(RinexDirectory("/data"; session = obs, country = "DEU"), nav_header)
# ... write_epoch!(obs, ...), write_ephemeris!(nav, ...)
close(obs); close(nav)
file_path(obs)  # "/data/ROOF00DEU_R_20200010000_01D_01S_GO.rnx"
```

`parse(RinexFileName, name)` reads a name back, and `tryparse` answers
`nothing` for one that does not follow the convention:

```julia
name = parse(RinexFileName, "ALGO00CAN_R_20121601000_01D_30S_MO.crx.gz")
name.interval  # 30.0 seconds
name.period    # Day(1)
```

## Epoch timing conventions

RINEX does not mandate an observation rate, but processing tools and the IGS
conventions expect epochs at integer multiples of the interval with the
receiver clock error kept small. A software receiver needs no hardware clock
steering for this: once a PVT solution gives the clock offset, schedule the
epochs at the sample instants of those times and propagate code and carrier
phase there. `epoch_time(time_system(header); week, time_of_week)` gives the
`time` and `fractional_second` of such an epoch. A residual offset can be
reported per epoch as `clock_offset`, which requires the header's
`clock_offset_applied`.
