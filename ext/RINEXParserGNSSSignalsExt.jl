module RINEXParserGNSSSignalsExt

using GNSSSignals: AbstractGNSSSignal, TimeSystem, get_constellation_id, get_signal_id
using GNSSSignals: GNSSSignals
import RINEXParser:
    observation_code, satellite_system, time_system, gnss_time_system, epoch_time
using RINEXParser: OBSERVATION_TYPES

# RINEX satellite system character per GNSSSignals constellation.
const SYSTEM_CHARACTERS = Dict(:GPS => 'G', :Galileo => 'E', :BeiDou => 'C')

# Band and attribute of the observation code of every signal GNSSSignals
# defines, keyed by `get_signal_id`, from the code tables of the
# constellations: Table 14 (GPS), 16 (Galileo) and 19 (BDS).
const SIGNAL_CODES = Dict(
    :GPSL1CA => "1C",
    :GPSL1C_D => "1S",
    :GPSL1C_P => "1L",
    :GPSL2CM => "2S",
    :GPSL2CL => "2L",
    :GPSL5I => "5I",
    :GPSL5Q => "5Q",
    :GalileoE1B => "1B",
    :GalileoE1C => "1C",
    # The modulation approximation is a detail of the tracking, not another
    # broadcast signal.
    :GalileoE1B_BOC11 => "1B",
    :GalileoE1C_BOC11 => "1C",
    :GalileoE5aI => "5I",
    :GalileoE5aQ => "5Q",
    :GalileoE5bI => "7I",
    :GalileoE5bQ => "7Q",
    :GalileoE6B => "6B",
    :GalileoE6C => "6C",
    # B1I is `2I` rather than the `1I` of RINEX 3.02, which 3.05 keeps only
    # as a form to accept when reading (Table 19 note). The BDS-3 signals are
    # named by component: data `D`, pilot `P`, which is what GNSSSignals'
    # I/Q suffixes are for B2a and B2b.
    :BeiDouB1I => "2I",
    :BeiDouB3I => "6I",
    :BeiDouB1C_D => "1D",
    :BeiDouB1C_P => "1P",
    :BeiDouB2aI => "5D",
    :BeiDouB2aQ => "5P",
    :BeiDouB2bI => "7D",
)

# Signals RINEX 3.05 has no observation code for, with the reason, so that
# being unable to name one reads as a property of the format rather than as
# an omission here.
const UNCODED_SIGNALS = Dict(
    :GalileoE5aQP =>
        "Galileo E5a-QP is new in OS SIS ICD Issue 2.2, published after RINEX " *
        "3.05, whose Galileo codes (Table 16) cover only E5a I, Q and I+Q",
)

function satellite_system(signal::AbstractGNSSSignal)
    constellation = get_constellation_id(signal)
    get(SYSTEM_CHARACTERS, constellation) do
        throw(
            ArgumentError(
                "Constellation $constellation has no RINEX satellite system character " *
                "here; the systems known are " *
                join(sort!(string.(collect(keys(SYSTEM_CHARACTERS)))), ", "),
            ),
        )
    end
end

function observation_code(type::Char, signal::AbstractGNSSSignal)
    type in OBSERVATION_TYPES || throw(
        ArgumentError(
            "The observation type is one of $(join(OBSERVATION_TYPES, ", ")), not '$type'",
        ),
    )
    signal_id = get_signal_id(signal)
    haskey(UNCODED_SIGNALS, signal_id) && throw(
        ArgumentError(
            "Signal $signal_id has no RINEX 3.05 observation code: " *
            UNCODED_SIGNALS[signal_id],
        ),
    )
    code = get(SIGNAL_CODES, signal_id, nothing)
    isnothing(code) && throw(
        ArgumentError(
            "Signal $signal_id has no RINEX 3.05 observation code in RINEXParser; " *
            "add it to the table of RINEXParserGNSSSignalsExt",
        ),
    )
    type * code
end

# The GNSSSignals time system of each RINEX time-system code.
const TIME_SYSTEMS = Dict(
    "GPS" => GNSSSignals.GPST(),
    "GAL" => GNSSSignals.GST(),
    "BDT" => GNSSSignals.BDT(),
)

function gnss_time_system(code::AbstractString)
    get(TIME_SYSTEMS, code) do
        throw(
            ArgumentError(
                "GNSSSignals has no time system for the RINEX time system \"$code\"; " *
                "the ones it has are " *
                join(sort!(collect(keys(TIME_SYSTEMS))), ", "),
            ),
        )
    end
end
# Satellite systems or a header: the time system of their epochs.
gnss_time_system(systems) = gnss_time_system(time_system(systems))

function time_system(system::TimeSystem)
    for (code, candidate) in TIME_SYSTEMS
        candidate == system && return code
    end
    throw(ArgumentError("The time system $system has no RINEX time-system code here"))
end

epoch_time(system::TimeSystem; week::Integer, time_of_week::Real) =
    epoch_time(time_system(system); week, time_of_week)

end # module RINEXParserGNSSSignalsExt
