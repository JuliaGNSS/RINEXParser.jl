# RINEXParser.jl

Streaming writer for RINEX 3.05 GNSS files: observation files (pseudorange,
carrier phase, Doppler, signal strength) and navigation files (broadcast
ephemerides plus ionosphere and time-system corrections).

The package is receiver-agnostic: it consumes plain record types and knows
nothing about how the measurements were made. It follows the design of
RTKLIB's `rinex.c` (a standalone format library) combined with GNSS-SDR's
runtime model (headers are written lazily on the first record, observation
epochs stream as they happen, ephemerides are written event-driven and
deduplicated). Output has been cross-validated against RTKLIB's RINEX
reader.

GPS and Galileo are implemented (matching the constellations supported by
GNSSSignals.jl); the record types carry the satellite-system character
throughout, so further constellations can be added without breaking the
API.

## Observation files

```julia
using RINEXParser, Dates

header = RinexObsHeader(;
    marker_name = "ROOF-1",
    receiver_type = "GNSSReceiver.jl",
    antenna_type = "UNKNOWN",
    approx_position = (4141446.0, 604023.0, 4796597.6),  # ECEF, meters
    obs_types = ['G' => ["C1C", "L1C", "D1C", "S1C"]],
    interval = 1.0,
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
                    "L1C" => ObsValue(111583948.752; lli = 0, ssi = 7), # carrier [cycles]
                    "D1C" => -1234.567,                           # Doppler [Hz]
                    "S1C" => 45.2,                                # C/N0 [dB-Hz]
                ),
            ];
            clock_offset = -1.2e-4,                           # receiver clock [s]
        ),
    )
end
```

Observations are addressed by observation descriptor, in any order and
without mentioning the types a satellite has no measurement for; `SatObs`
takes the alignment from the header (passed directly or through the writer)
and cannot misalign them. A value is a plain number, an `ObsValue` carrying
the loss-of-lock and signal-strength indicators, or `nothing`. The
positional form `SatObs('G', 2, [ObsValue(...), nothing, ...])`, aligned
with the header's `obs_types` for the system, also remains available.

`RinexObsHeader` is mutable and the header is written when the first epoch
arrives, so `time_of_first_obs` is filled in automatically and fields that
the data provides late can be assigned until then:

```julia
writer.header.approx_position = position   # from the first PVT solution
writer.header.leap_seconds = leap_seconds  # decoded from the navigation message
```

The file is written in the time system of its constellation (`GPS`, `GAL`,
`BDT`, ...), and a file carrying several constellations in GPS time, as
RINEX prescribes for mixed files.

An observation whose value is not finite is written as a blank field, the
RINEX encoding of "no measurement", instead of as `NaN` in a numeric field.
A finite value too wide for its 14 columns - or an indicator, satellite
number or clock offset too wide for its own field - is rejected with an
`ArgumentError`, because writing it would shift the rest of the record and
leave a file that parses but is silently wrong.

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
(RINEX Table A15: `iodnav`, `data_sources`, `sisa`, `bgd_e5a_e1`,
`bgd_e5b_e1`, ...); the Klobuchar-style NeQuick coefficients go into an
`IonosphericCorrection("GAL", (ai0, ai1, ai2, 0.0))` header record. The two
bit fields of that record are assembled by `galileo_data_sources` and
`galileo_sv_health` rather than by hand:

```julia
data_sources = galileo_data_sources(; inav_e1b = true, clock_e5b_e1 = true)  # 513
sv_health = galileo_sv_health(; e1b_dvs = 1, e1b_hs = 1)                     # 3
```

A navigation file containing several constellations is marked `M: MIXED`
automatically; set `satellite_system = 'G'` in `RinexNavHeader` for a
single-system file, which then rejects ephemerides of other
constellations.

`write_ephemeris!` skips ephemerides it has already written (same
satellite, issue-of-data, time of ephemeris, and for Galileo the
navigation message source, since I/NAV and F/NAV are separate records), so
it is safe to forward every decoded navigation frame. The nav header is
also written lazily, and `writer.header` may be updated until the first
ephemeris is written, which is useful when ionosphere/UTC parameters
decode later than the first ephemeris.

Unlike an observation, a navigation record field has no blank encoding that
would mean "not available", so an ephemeris carrying a value that is not
finite is rejected instead of writing `NaN` into a numeric field.

`write_ephemeris!` accepts any ephemeris type, so a constellation that is
not modelled yet can be written by implementing the ephemeris interface -
`RINEXParser.system`, `RINEXParser.dedupe_key`, `RINEXParser.orbit_lines`
and optionally `RINEXParser.clock_coefficients`, see
`?write_ephemeris!`.

## Epoch timing conventions

RINEX itself does not mandate an observation rate or epoch alignment, but
processing tools and the IGS conventions expect epochs at "round" GPS
times (integer multiples of the interval) with the receiver clock error
kept small (conventionally below 1 ms). A software receiver does not need
hardware clock steering for this: once a PVT solution provides the clock
offset, schedule the measurement epochs at the sample instants
corresponding to integer GPS seconds and propagate code and carrier phase
to that instant. Any residual offset can be reported per epoch via
`clock_offset`.
