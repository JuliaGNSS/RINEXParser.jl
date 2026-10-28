# API reference

The exported names are listed bare; the rest of the API is reached qualified,
`RINEXParser.name`. Everything else is internal and listed under
[Internals](internals.md).

## Observation files

```@docs
RinexObsHeader
PhaseShift
ObsValue
SatObs
ObsEpoch
RinexObsWriter
write_epoch!
phase_correction
loss_of_lock_indicator
signal_strength_indicator
```

## Navigation files

```@docs
RinexNavHeader
nav_satellite_system
IonosphericCorrection
TimeSystemCorrection
LeapSeconds
GPSEphemeris
GalileoEphemeris
BeiDouEphemeris
galileo_data_sources
galileo_sv_health
RinexNavWriter
write_ephemeris!
```

## Writers

```@docs
set_header!
header_written
file_path
```

## Times

```@docs
time_system
epoch_time
navigation_times
ionosphere_time_mark
```

## File names

```@docs
RinexFileName
rinex_filename
RinexDirectory
Base.parse(::Type{RinexFileName}, ::AbstractString)
```

## With GNSSDecoder and GNSSSignals

The methods of these functions come with the package extensions.

```@docs
rinex_ephemeris
has_rinex_ephemeris
add_header_records!
observation_code
observation_codes
gnss_time_system
RINEXParser.satellite_system
```
