module RINEXParser

using Dates
using Printf

export RinexFileName, rinex_filename, RinexDirectory
export set_header!, header_written, file_path
export RinexObsHeader, PhaseShift, ObsValue, SatObs, ObsEpoch, RinexObsWriter, write_epoch!
export phase_correction
export loss_of_lock_indicator, signal_strength_indicator
export LeapSeconds, time_system, epoch_time
export RinexNavHeader,
    nav_satellite_system,
    IonosphericCorrection,
    TimeSystemCorrection,
    GPSEphemeris,
    GalileoEphemeris,
    BeiDouEphemeris,
    galileo_data_sources,
    galileo_sv_health,
    RinexNavWriter,
    write_ephemeris!,
    navigation_times,
    ionosphere_time_mark
# Methods in the package extensions for GNSSDecoder and GNSSSignals.
export rinex_ephemeris, has_rinex_ephemeris, add_header_records!
export observation_code, observation_codes
export gnss_time_system

const RINEX_VERSION = 3.05

include("format.jl")
include("directory.jl")
include("obs.jl")
include("time.jl")
include("nav.jl")
include("extensions.jl")
# After the headers: the filename is derived from them.
include("filename.jl")

end # module RINEXParser
