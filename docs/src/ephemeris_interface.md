# Ephemeris interface

`write_ephemeris!` accepts external types through multiple dispatch. No abstract
supertype or conversion to a built-in ephemeris is required.

| Method | Result | Default |
| --- | --- | --- |
| `RINEXParser.system(eph)` | RINEX constellation character | Required |
| `RINEXParser.dedupe_key(eph)` | Tuple identifying a distinct record | Required |
| `RINEXParser.orbit_lines(eph)` | Tuples of up to four values per orbit line | Required |
| `RINEXParser.clock_coefficients(eph)` | Three clock coefficients | `(eph.af0, eph.af1, eph.af2)` |

These qualified, unexported methods form the supported extension interface.
Records must also expose `prn` (the satellite number) and `toc` (a `DateTime`
in the constellation's RINEX time system) fields. The writer does not convert
time systems.

## Representation rules

Return orbit values in RINEX record order and units. Use `nothing` for blank
spare fields. Any `nothing` returned by `orbit_lines` writes a blank, even when
the field normally requires a value; the adapter must ensure required values
are present. Other values must be finite and fit their numeric columns. The
writer checks those constraints before emitting any of the record.

A deduplication key must distinguish satellites, reference times (including the
week where needed), issues of data, and independent navigation message sources.
An issue counter alone can wrap and is not a sufficient key.

Keep constellation and unit conversions in the adapter. RINEX constellation
characters and observation descriptors describe the file format; signal types
and unit-aware quantities describe the receiver's measurements. An adapter can
bridge them without adding receiver dependencies to the core writer.
