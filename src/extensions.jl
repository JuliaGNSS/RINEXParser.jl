# Functions whose methods come with the package extensions: they read the
# types of GNSSDecoder and GNSSSignals, which this package does not depend
# on, and are defined here so that the extensions have something to add to.

"""
    rinex_ephemeris(decoder; week = nothing)
        -> Union{Nothing,GPSEphemeris,GalileoEphemeris,BeiDouEphemeris}

The navigation record of a GNSSDecoder `GNSSDecoderState`, for
[`write_ephemeris!`](@ref). Available with `using GNSSDecoder`.

Records exist for GPS LNAV (L1 C/A), for Galileo I/NAV (E1-B, E5b) and
F/NAV (E5a), and for BDS D1/D2 (B1I, B3I). The GPS CNAV and CNAV-2 messages
(L5, L2C, L1C), the BDS B-CNAV messages (B1C, B2a, B2b) and Galileo's E6
C/NAV broadcast a quasi-Keplerian ephemeris that RINEX 3.05 has no record
for - it arrived with RINEX 4 - so those decoders give `nothing`, as does a
decoder whose message is not complete for positioning yet: a partially
decoded message would write zeros into the record.

`week` is the continuous week of the message on its constellation's own
count - the GPS week, the Galileo (GST) week, the BDT week - which is what
`PositionVelocityTime.get_week` returns. Galileo and BDS broadcast all of
it, so it defaults to the decoded one. GPS LNAV broadcasts it in 10 bits,
which leaves the 1024-week cycle to the caller, so a GPS decoder needs it
given.

The decoded values are converted to the record's units and conventions:
the issue-of-data and health words to their numbers, the accuracy indices
to meters (IS-GPS-200 Table 20-I, Galileo OS SIS ICD Table 92), the
broadcast fit-interval flag to hours, the Galileo health and data-validity
status to the bit fields of [`galileo_sv_health`](@ref) and
[`galileo_data_sources`](@ref), and the times by
[`navigation_times`](@ref). Angles pass through: the decoders hold them in
radians already.
"""
function rinex_ephemeris end

"""
    add_header_records!(header::RinexNavHeader, decoder; week = nothing) -> header

Add the navigation-header records a GNSSDecoder `GNSSDecoderState` has
decoded to `header`: the ionospheric corrections (Klobuchar for GPS and
BDS, NeQuick for Galileo), the time-system corrections (each
constellation's offset to UTC, and Galileo's to GPS time) and the leap
seconds. Available with `using GNSSDecoder`.

These are broadcast far less often than the ephemerides - GPS sends them
once every 12.5 minutes - so a writer collects them from every decoder
until the header is written:

    header = RinexNavHeader(; satellite_system)
    foreach(decoder -> add_header_records!(header, decoder; week), decoders)
    header_written(writer) || set_header!(writer, header)

A record replaces one of the same type - for BDS, of the same type, time
mark and satellite - so the latest broadcast is the one written. Of the
leap seconds, the record counted in GPS time is kept over BDS's, which
counts BDT, and a record announcing the next leap-second event over one that
does not, as some parsers require it.

`week` is the one [`rinex_ephemeris`](@ref) takes. The reference weeks that
are broadcast truncated - the 8-bit UTC and leap-second weeks, Galileo's
6-bit GGTO week - are resolved against it into the continuous week a header
record carries, aligned with the GPS week for Galileo.
"""
function add_header_records! end

"""
    observation_code(type::Char, signal) -> String

The RINEX 3.05 observation code of the observable `type` - `'C'`
(pseudorange), `'L'` (carrier phase), `'D'` (Doppler) or `'S'` (signal
strength) - of a GNSSSignals `signal`, from the code tables of the
constellations (Tables 14, 16 and 19). Available with `using GNSSSignals`.

    observation_code('C', GPSL1CA())    # "C1C"
    observation_code('L', BeiDouB1I())  # "L2I", not the "L1I" of RINEX 3.02

The Galileo E1 signals approximated as BOC(1,1) are the same broadcast
signal as the CBOC ones, so they share their codes; the BDS-3 signals are
named by component, data `D` and pilot `P`. A signal RINEX 3.05 has no code
for is rejected with an `ArgumentError` saying why.
"""
function observation_code end

"""
    satellite_system(signal) -> Char

The RINEX satellite system character of a GNSSSignals `signal`: `'G'`,
`'E'` or `'C'`. Available with `using GNSSSignals`. The same function names
the system of a record of the [Ephemeris interface](@ref).
"""
satellite_system(signal)
