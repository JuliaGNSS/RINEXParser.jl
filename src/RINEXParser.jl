module RINEXParser

using Dates
using Printf

export RinexObsHeader, ObsValue, SatObs, ObsEpoch, RinexObsWriter, write_epoch!
export RinexNavHeader, IonosphericCorrection, TimeSystemCorrection, GPSEphemeris,
    GalileoEphemeris, RinexNavWriter, write_ephemeris!

const RINEX_VERSION = 3.05

include("format.jl")
include("obs.jl")
include("nav.jl")

end # module RINEXParser
