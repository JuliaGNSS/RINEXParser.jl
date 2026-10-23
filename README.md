# RINEXParser.jl

Streaming writer for RINEX 3.05 GNSS files: observation files (pseudorange,
carrier phase, Doppler, signal strength) and navigation files (broadcast
ephemerides plus ionosphere and time-system corrections), plus the long
filenames the files are named by.

See the [documentation](https://JuliaGNSS.github.io/RINEXParser.jl/dev/) for
worked examples and the API reference, and [CONTRIBUTING.md](CONTRIBUTING.md)
for formatting, tests, and release conventions.

The package is receiver-agnostic: it consumes plain record types and knows
nothing about how the measurements were made. It follows the design of
RTKLIB's `rinex.c` (a standalone format library) combined with GNSS-SDR's
runtime model (headers are written lazily on the first record, observation
epochs stream as they happen, ephemerides are written event-driven and
deduplicated). Output has been cross-validated against RTKLIB's RINEX
reader.

GPS, Galileo and BeiDou are implemented (matching the constellations
supported by GNSSSignals.jl); the record types carry the satellite-system
character throughout, so further constellations can be added without
breaking the API.

## Observation files

```julia
using RINEXParser, Dates

header = RinexObsHeader(;
    marker_name = "ROOF-1",
    receiver_type = "GNSSReceiver.jl",
    antenna_type = "UNKNOWN",
    approx_position = (4141446.0, 604023.0, 4796597.6),  # ECEF, meters
    obs_codes = ['G' => ["C1C", "L1C", "D1C", "S1C"]],
    signal_strength_unit = "DBHZ",                       # unit of the S observations
    interval = 1.0,
    clock_offset_applied = false,  # epochs, code and phase still carry the clock
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

Carrier phases must reach a RINEX 3 file aligned with the reference signal
of their band (section 5.2.12), and the mandatory `SYS / PHASE SHIFT`
records say how. A phase code the header does not name in `phase_shifts` is
written as one that needed no correction, as the reference signal of its
band does. The codes Table A23 gives another correction have to be named,
and a header that leaves one out is rejected when the writer is created:

```julia
phase_shifts = [
    PhaseShift('G', "L2S", -0.25),  # the correction that was applied
    PhaseShift('G', "L5Q", 0.0),    # arrived aligned, nothing applied here
]
```

`phase_correction` looks a phase code up in Table A23 and gives the
correction the ICDs define for aligning it with the reference signal of its
band: `phase_correction('E', "L1C") == 0.5`. Where the table only says that a
code must be aligned (GPS `L5X`, ...), or where the correction depends on
the satellite (GPS `L2C`), `phase_correction` returns `nothing`. Such a
code still needs a `PhaseShift`, with the correction the receiver or
converter applied.

Observations are addressed by observation code, in any order and
without mentioning the types a satellite has no measurement for; `SatObs`
takes the alignment from the header (passed directly or through the writer)
and cannot misalign them. A value is a plain number, an `ObsValue` carrying
the loss-of-lock and signal-strength indicators, or `nothing`. The
positional form `SatObs('G', 2, [ObsValue(...), nothing, ...])`, aligned
with the header's `obs_codes` for the system, also remains available.

`loss_of_lock_indicator` sets the bits of the loss-of-lock indicator by name
- `loss_of_lock`, `half_cycle` for a phase whose polarity is not resolved
yet, and `boc_tracking` - and `signal_strength_indicator` maps a C/N0 in
dB-Hz to the 1-9 indicator by the formula of section 6.7.2. The
loss-of-lock indicator belongs to carrier phases, so a non-zero one on a
pseudorange, Doppler or signal strength is rejected.

The observation codes of `obs_codes` and `phase_shifts` are checked
against the codes RINEX 3.05 defines for each constellation (Tables 14-20),
so a code that is not a known tracking mode - BDS B1I as `C1I` rather
than `C2I`, a pseudorange of the codeless GPS tracking - is rejected when
the writer is created.

`RinexObsHeader` is mutable and the header is written when the first epoch
arrives, so `time_of_first_obs` is filled in from that epoch - and assigned
to the header, so `rinex_filename` can name the file from it afterwards -
and fields that the data provides late can be assigned until then:

```julia
writer.header.approx_position = position   # from the first PVT solution
writer.header.leap_seconds = leap_seconds  # decoded from the navigation message
```

`set_header!(writer, header)` replaces the header as a whole, checking it as
the writer checks the one it is created with, and `header_written(writer)`
says whether it is too late for that.

A GLONASS file lists the frequency channel of each slot it observes, as
`glonass_slots = [1 => 1, 2 => -4, ...]`, and the code-phase biases of
`C1C`, `C1P`, `C2C` and `C2P` as `glonass_code_phase_biases` - zeros for
aligned data, or `nothing` when they are not known. A GLONASS satellite with
no frequency channel in the header is rejected, because its carrier
frequency could not be reconstructed.

The file is written in the time system of its constellation (`GPS`, `GAL`,
`BDT`, ...), and a file carrying several constellations in GPS time, as
RINEX prescribes for mixed files.

An observation whose value is not finite is written as a blank field, the
RINEX encoding of "no measurement", instead of as `NaN` in a numeric field.
A finite value too wide for its 14 columns - or an indicator, satellite
number or clock offset too wide for its own field - is rejected with an
`ArgumentError`, because writing it would shift the rest of the record and
leave a file that parses but is silently wrong. The epoch is checked whole
before any of it is written, so the file stays as it was. A receiver that
would rather keep the epoch creates the writer with `overflow = :blank`: an
observation value or clock offset that does not fit is then written blank,
as a measurement that is not available, with a warning the first time it
happens to each field.

## Navigation files

```julia
header = RinexNavHeader(
    ionospheric_corrections = [
        IonosphericCorrection("GPSA", (α0, α1, α2, α3)),  # Klobuchar
        IonosphericCorrection("GPSB", (β0, β1, β2, β3)),
    ],
    time_system_corrections = [
        TimeSystemCorrection("GPUT", a0, a1, t_ot, week),
    ],
    leap_seconds = 18,
)

RinexNavWriter("data.nav", header) do writer
    write_ephemeris!(writer, GPSEphemeris(
        prn = 13, toc = DateTime(2020, 1, 1, 2, 0, 0),
        af0 = ..., af1 = ..., af2 = ...,
        iode = ..., crs = ..., deltan = ..., m0 = ...,
        # ... remaining Keplerian elements, see ?GPSEphemeris
    ))
end
```

Galileo I/NAV and F/NAV ephemerides are written with `GalileoEphemeris`
(RINEX Table A8: `iodnav`, `data_sources`, `sisa`, `bgd_e5a_e1`,
`bgd_e5b_e1`, ...); the Klobuchar-style NeQuick coefficients go into an
`IonosphericCorrection("GAL", (ai0, ai1, ai2))` header record, whose spare
fourth field is written blank. The two
bit fields of that record are assembled by `galileo_data_sources` and
`galileo_sv_health` rather than by hand:

```julia
data_sources = galileo_data_sources(; inav_e1b = true)    # 513, with the E5b/E1 clock
sv_health = galileo_sv_health(; e1b_dvs = 1, e1b_hs = 1)  # 3
```

BeiDou D1/D2 ephemerides are written with `BeiDouEphemeris` (RINEX Table
A14: `aode`, `aodc`, `sath1`, `tgd1_b1_b3`, `tgd2_b2_b3`, ...). Its `toc`,
`toe`, `week` and `transmission_time` are in BeiDou time - `week` is the
continuous BDT week, the GPS week minus 1356 - and the Klobuchar
coefficients go into `IonosphericCorrection("BDSA", ...)` and
`IonosphericCorrection("BDSB", ...)` header records - which for BDS carry
the mandatory `time_mark` and `sv_id` of the satellite that broadcast them:

```julia
IonosphericCorrection("BDSA", (α0, α1, α2, α3); time_mark = 'A', sv_id = 6)
```

A BDS file counts the week of a leap-second event from the BDT epoch rather
than the GPS one, which only the time system identifier of the record tells
a reader apart:

```julia
leap_seconds = LeapSeconds(4; future_count = 4, week = 730, day = 0, time_system = "BDT")
```

A navigation file containing several constellations is marked `M: Mixed`
automatically; set `satellite_system = 'G'` in `RinexNavHeader` for a
single-system file, which then rejects ephemerides of other
constellations.

`write_ephemeris!` skips ephemerides it has already written (same
satellite, issue-of-data, week, time of ephemeris, and for Galileo the
navigation message source, since I/NAV and F/NAV are separate records; a
BeiDou record is identified by its reference times instead, since its age
of data grows while the ephemeris stays the same), so it is safe to forward
every decoded navigation frame. The nav header is
also written lazily, and `set_header!(writer, header)` replaces it until the
first ephemeris is written, which is useful when ionosphere/UTC parameters
decode later than the first ephemeris.

Unlike an observation, a navigation record field has no blank encoding that
would mean "not available", so an ephemeris carrying a value that is not
finite is rejected instead of writing `NaN` into a numeric field.

`write_ephemeris!` accepts any ephemeris type, so a constellation that is
not modelled yet can be written by implementing the ephemeris interface -
`RINEXParser.satellite_system`, `RINEXParser.dedupe_key`, `RINEXParser.orbit_lines`
and optionally `RINEXParser.clock_coefficients`, see
`?write_ephemeris!`. Records must also expose `prn` and `toc` fields. See the
[ephemeris interface](docs/src/ephemeris_interface.md) for the full contract.

## File names

RINEX 3.02 and later name files by the long filename convention (RINEX 3.05
appendix A1, unchanged in RINEX 4.02), and `rinex_filename` builds one from
the header of the file, so a receiver does not have to assemble a name of
its own:

```julia
path = joinpath(directory, rinex_filename(obs_header, start_time; period = Day(1)))
# "/data/ROOF00DEU_R_20200010000_01D_01S_GO.rnx"

RinexObsWriter(path, obs_header) do writer
    write_epoch!(writer, epoch)
end
```

The header determines the site (from its marker name, which RINEX 3 expects
to be the nine-character site identification `XXXXMRCCC`), the data type
(`GO` for a GPS observation file, `MN` for a mixed navigation file) and the
data frequency (from its `interval`, which a navigation file name does not
carry). The fields it does not determine are keywords: `period`,
`data_source`, `compression`, or any site field a marker name does not
provide. `system` and `file_type` are not among them - the data type follows the
file, so a header names its own, and passing one is an error rather than a
keyword the header quietly overrules.

```julia
rinex_filename(obs_header)                       # start time from time_of_first_obs
rinex_filename(obs_header, t; country = "DEU")   # marker name gives only the station
rinex_filename(nav_header, t; marker_name = obs_header.marker_name, period = Day(1))
```

A receiver does not know the start time when it opens its files: that is
the time of the first epoch. A `RinexDirectory` target names the file when
the writer closes instead. The writer streams into a temporary file in the
directory and moves it to its long filename on `close`, and `file_path(writer)`
says where it ended up. A navigation file takes its start time and site
from the observation writer of its `session`:

```julia
obs = RinexObsWriter(RinexDirectory("/data"; country = "DEU", period = Day(1)), obs_header)
nav = RinexNavWriter(RinexDirectory("/data"; session = obs, country = "DEU"), nav_header)
# ... write_epoch!(obs, ...), write_ephemeris!(nav, ...)
close(obs); close(nav)
file_path(obs)  # "/data/ROOF00DEU_R_20200010000_01D_01S_GO.rnx"
```

Without a session, or with one that got no epoch, a navigation file is named
after the `toc` of its first ephemeris. A file whose name is taken is
replaced only for a `RinexDirectory(...; overwrite = true)`; otherwise it is
left at its temporary path with a warning, which `file_path` reports, and
`close` does not throw. A file is kept whenever it can be named, header-only
ones included; a writer that wrote no record and has no start time to be
named after leaves no file.

`RinexFileName` is the name itself, with a field per element of the
convention, and `parse(RinexFileName, name)` reads one back - `tryparse`
answers `nothing` instead of throwing, which selects the names of a directory
that conform to the convention:

```julia
name = parse(RinexFileName, "ALGO00CAN_R_20121601000_01D_30S_MO.crx.gz")
name.start_time  # 2012-06-08T10:00:00
name.interval    # 30.0 seconds, from the 30S data-frequency field
name.period      # Day(1), from 01D
name.system      # 'M', mixed
```

Every field is fixed width, so a value that would not fit it - a station
that is not four characters, a file period of 100 days, a sampling interval
of 100 seconds - is rejected when the name is built rather than written out
misaligned; a name that exists is one that renders. `nothing` is available for
the two fields that have an "unspecified" encoding: `period` and `interval`
are then written as `00U` - the zero count of those fields belongs to that
`U`, so a period of no length is rejected rather than written as one of zero
days.

A name is not a path, though. Every field is kept as the field itself holds
it: the start time floored to the minute, the period and the interval in the
one unit and count they are written in - `Day(1) + Hour(12)` as the `Hour(36)`
of its `36H`, a `24H` read from a name as `01D`. So rendering a name that was
read is not always the name on disk - keep the path if you need to open the
file. Reading is as strict as the spec, too, which is
stricter than an archive: RINEX 2 short names (`algo1600.12o`) are a different
convention and are not read, nor is a one-character compression field (`.Z`)
or a navigation name carrying a data-frequency field it should not have.

## Epoch timing conventions

RINEX itself does not mandate an observation rate or epoch alignment, but
processing tools and the IGS conventions expect epochs at "round" GPS
times (integer multiples of the interval) with the receiver clock error
kept small (conventionally below 1 ms). A software receiver does not need
hardware clock steering for this: once a PVT solution provides the clock
offset, schedule the measurement epochs at the sample instants
corresponding to integer GPS seconds and propagate code and carrier phase
to that instant. Any residual offset can be reported per epoch via
`clock_offset`, which RINEX allows only together with the `RCV CLOCK OFFS
APPL` record: set the header's `clock_offset_applied` to say whether the
epochs were corrected by it.
