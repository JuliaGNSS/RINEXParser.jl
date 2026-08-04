module RINEXParser

using Dates
using Printf

export RinexFileName, rinex_filename
export RinexObsHeader, ObsValue, SatObs, ObsEpoch, RinexObsWriter, write_epoch!
export RinexNavHeader,
    IonosphericCorrection,
    TimeSystemCorrection,
    GPSEphemeris,
    GalileoEphemeris,
    galileo_data_sources,
    galileo_sv_health,
    RinexNavWriter,
    write_ephemeris!

const RINEX_VERSION = 3.05

include("format.jl")
include("obs.jl")
include("nav.jl")
# After the headers: the filename is derived from them.
include("filename.jl")

end # module RINEXParser
