# Ephemeris interface

`write_ephemeris!` accepts external types through multiple dispatch. No abstract
supertype or conversion to a built-in ephemeris is required.

| Method | Result | Default |
| --- | --- | --- |
| `RINEXParser.satellite_system(eph)` | RINEX constellation character | Required |
| `RINEXParser.dedupe_key(eph)` | Tuple identifying a distinct record | Required |
| `RINEXParser.orbit_lines(eph)` | Tuples of up to four values per orbit line | Required |
| `RINEXParser.clock_coefficients(eph)` | Three clock coefficients | `(eph.af0, eph.af1, eph.af2)` |

These qualified, unexported methods form the supported extension interface.
Records must also expose `prn` (the satellite number) and `toc` (a `DateTime`
in the constellation's RINEX time system) fields. The writer does not convert
time systems.

## Representation rules

Return orbit values in RINEX record order and units, as any `Real`: counters
and bit fields may be integers. Use `nothing` for blank
spare fields. Any `nothing` returned by `orbit_lines` writes a blank, even when
the field normally requires a value; the adapter must ensure required values
are present. Other values must be finite and fit their numeric columns. The
writer checks those constraints before emitting any of the record.

A deduplication key must change whenever the contents of the record change,
leaving out only what changes with every broadcast of the same record, such as
the transmission time. Section 5.4.3 asks for a new record when the contents
change, and health or data validity can change without the issue of data, so a
key of satellite, issue of data and reference time is not sufficient. The
built-in types use every field but the transmission time.

Keep constellation and unit conversions in the adapter. RINEX constellation
characters and observation codes describe the file format; signal types
and unit-aware quantities describe the receiver's measurements. An adapter can
bridge them without adding receiver dependencies to the core writer.
