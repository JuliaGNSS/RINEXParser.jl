const MAX_PHASE_SHIFT_SATELLITES = 99

"""
    check_phase_shift_satellites(system, code, satellites) -> satellites

Return the satellite list of a [`PhaseShift`](@ref), or throw an
`ArgumentError` if the record cannot hold it. The list is a `Vector`, so it
stays open to `push!` after the shift was constructed; the header writer
therefore checks it again, and this is what both of them call.
"""
function check_phase_shift_satellites(system::Char, code, satellites)
    foreach(prn -> check_satellite_number(system, prn), satellites)
    # The list is counted into an `I2.2` field, and the count is what tells
    # a reader how many of the identifications that follow to read.
    length(satellites) <= MAX_PHASE_SHIFT_SATELLITES || throw(
        ArgumentError(
            "The phase shift of $system $code names $(length(satellites)) " *
            "satellites, but the record counts them in two columns, which holds " *
            "$MAX_PHASE_SHIFT_SATELLITES; leave the list empty to name every " *
            "satellite of the system",
        ),
    )
    satellites
end

# The signals of RINEX 3.05 Tables 14-20: per system, each band with the
# attributes (tracking modes or channels) it is tracked with. Every signal
# carries the four observation types C, L, D and S, except the codeless
# tracking of GPS, which measures no pseudorange.
const OBSERVATION_SIGNALS = Dict(
    'G' => ('1' => "CSLXPWYMN", '2' => "CDSLXPWYMN", '5' => "IQX"),
    'R' => ('1' => "CP", '4' => "ABX", '2' => "CP", '6' => "ABX", '3' => "IQX"),
    'E' => ('1' => "ABCXZ", '5' => "IQX", '7' => "IQX", '8' => "IQX", '6' => "ABCXZ"),
    'S' => ('1' => "C", '5' => "IQX"),
    'J' => ('1' => "CSLXZB", '2' => "SLX", '5' => "IQXDPZ", '6' => "SLXEZ"),
    'C' => (
        '2' => "IQX",
        '1' => "DPXSLZ",
        '5' => "DPX",
        '7' => "IQXDPZ",
        '8' => "DPX",
        '6' => "IQXDPZ",
    ),
    'I' => ('5' => "ABCX", '9' => "ABCX"),
)

const OBSERVATION_CODE_TABLES =
    Dict('G' => 14, 'R' => 15, 'E' => 16, 'S' => 17, 'J' => 18, 'C' => 19, 'I' => 20)

"""
    check_observation_code(system, code) -> code

Return the observation code `code`, or throw an `ArgumentError` if
RINEX 3.05 does not define it for `system`. A code is a type, a band
and an attribute, and only the combinations of Tables 14-20 are known
tracking modes, which section 5.2.17 makes the only ones a file may carry:
BDS B1I is `2I` rather than `1I`, and Galileo E5b and BDS B2b share band 7
under attributes of their own. The one other code the format admits
is the receiver channel number `X`, whose attribute is blank (section
5.3.4).
"""
function check_observation_code(system::Char, code::AbstractString)
    name = SYSTEM_NAMES[system]
    table = "RINEX 3.05 Table $(OBSERVATION_CODE_TABLES[system])"
    signals = OBSERVATION_SIGNALS[system]
    bands = join(first.(signals), ", ")
    (length(code) == 3 && first(code) in "CLDSX") || throw(
        ArgumentError(
            "\"$code\" is not an observation code, which is a type C, L, D, " *
            "S or X followed by a band and an attribute, as in \"C1C\"",
        ),
    )
    type, band, attribute = code
    index = findfirst(signal -> first(signal) == band, signals)
    isnothing(index) && throw(
        ArgumentError(
            "Observation code \"$code\" names band $band, which $name does not " *
            "have; its bands in $table are $bands",
        ),
    )
    attributes = last(signals[index])
    if type == 'X'
        attribute == ' ' || throw(
            ArgumentError(
                "Observation code \"$code\" is a receiver channel number, whose " *
                "attribute is blank, as in \"X$band \"",
            ),
        )
    elseif !(attribute in attributes)
        throw(
            ArgumentError(
                "$name has no observation code \"$code\" in $table; band $band " *
                "is tracked with the attributes $(join(attributes, ", "))",
            ),
        )
    elseif type == 'C' && system == 'G' && attribute == 'N'
        throw(
            ArgumentError(
                "Observation code \"$code\" is a pseudorange of the codeless " *
                "tracking, which measures none; $table gives it L$band$attribute, " *
                "D$band$attribute and S$band$attribute",
            ),
        )
    end
    code
end

# Return the observation code `code` if it is a carrier phase of `system`,
# which is what a phase shift and the alignment of Table A23 are given for.
function check_carrier_phase_code(system::Char, code::AbstractString)
    startswith(code, "L") || throw(
        ArgumentError(
            "A phase shift corrects a carrier phase, so \"$code\" is not a code " *
            "it can be given for; carrier phase codes start with \"L\"",
        ),
    )
    check_observation_code(system, code)
end

# RINEX 3.05 Table A23: per system, the groups of carrier phases aligned to
# one reference signal, the reference first, each with the correction in
# cycles the table gives for the phase as the satellite issues it. "None" is
# a correction of zero; `nothing` is a phase the table says must be aligned
# to the reference without saying by how much, or whose correction depends
# on the satellite (GPS L2C on its block, QZSS L1S on Block I against II).
# A band can hold more than one group, as BDS B1C and B1A share band 1. The
# codes the table states no alignment for are left out: all of SBAS, the
# GPS Y and M and Galileo A and Z signals, QZSS L1B, the QZSS L1Z it marks
# N/A and the restricted NavIC L5B and L9B.
const PHASE_ALIGNMENT_GROUPS = Dict(
    'G' => (
        (
            "L1C" => 0.0,
            "L1S" => 0.25,
            "L1L" => 0.25,
            "L1X" => 0.25,
            "L1P" => 0.25,
            "L1W" => 0.25,
            "L1N" => 0.25,
        ),
        (
            "L2P" => 0.0,
            "L2C" => nothing,
            "L2D" => 0.0,
            "L2S" => -0.25,
            "L2L" => -0.25,
            "L2X" => -0.25,
            "L2W" => 0.0,
            "L2N" => 0.0,
        ),
        ("L5I" => 0.0, "L5Q" => -0.25, "L5X" => nothing),
    ),
    'R' => (
        ("L1C" => 0.0, "L1P" => 0.25),
        ("L4A" => 0.0, "L4B" => 0.0, "L4X" => 0.0),
        ("L2C" => 0.0, "L2P" => 0.25),
        ("L6A" => 0.0, "L6B" => 0.0, "L6X" => 0.0),
        ("L3I" => 0.0, "L3Q" => nothing, "L3X" => nothing),
    ),
    'E' => (
        ("L1B" => 0.0, "L1C" => 0.5, "L1X" => nothing),
        ("L5I" => 0.0, "L5Q" => -0.25, "L5X" => nothing),
        ("L7I" => 0.0, "L7Q" => -0.25, "L7X" => nothing),
        ("L8I" => 0.0, "L8Q" => -0.25, "L8X" => nothing),
        ("L6B" => 0.0, "L6C" => -0.5, "L6X" => nothing),
    ),
    'J' => (
        ("L1C" => 0.0, "L1S" => nothing, "L1L" => 0.25, "L1X" => 0.25),
        ("L2S" => 0.0, "L2L" => 0.0, "L2X" => 0.0),
        ("L5I" => 0.0, "L5Q" => -0.25, "L5X" => nothing),
        ("L5D" => 0.0, "L5P" => -0.25, "L5Z" => nothing),
        ("L6S" => 0.0, "L6L" => 0.0, "L6X" => 0.0, "L6E" => 0.0, "L6Z" => 0.0),
    ),
    'C' => (
        ("L2I" => 0.0, "L2Q" => nothing, "L2X" => nothing),
        ("L1D" => 0.0, "L1P" => nothing, "L1X" => nothing),
        ("L1S" => 0.0, "L1L" => nothing, "L1Z" => nothing),
        ("L5D" => 0.0, "L5P" => nothing, "L5X" => nothing),
        ("L7I" => 0.0, "L7Q" => -0.25, "L7X" => nothing),
        ("L7D" => 0.0, "L7P" => nothing, "L7Z" => nothing),
        ("L8D" => 0.0, "L8P" => nothing, "L8X" => nothing),
        ("L6I" => 0.0, "L6Q" => nothing, "L6X" => nothing),
        ("L6D" => 0.0, "L6P" => nothing, "L6Z" => nothing),
    ),
    'I' => (
        ("L5A" => 0.0, "L5C" => 0.0, "L5X" => nothing),
        ("L9A" => 0.0, "L9C" => 0.0, "L9X" => nothing),
    ),
)

# The groups above keyed by `(system, code)`, each code with the reference
# of its group and its correction.
const PHASE_ALIGNMENT = Dict{Tuple{Char,String},Tuple{String,Union{Nothing,Float64}}}(
    (system, code) => (first(first(group)), correction) for
    (system, groups) in PHASE_ALIGNMENT_GROUPS for group in groups for
    (code, correction) in group
)

# The reference and correction of the carrier phase `code` of `system`, or
# `nothing` for a code the table leaves out.
function phase_alignment_entry(system::Char, code::AbstractString)
    check_satellite_system(system)
    check_carrier_phase_code(system, code)
    get(PHASE_ALIGNMENT, (system, String(code)), nothing)
end

"""
    reference_code(system, code) -> Union{String,Nothing}

The reference signal that RINEX 3.05 Table A23 gives the band of the
carrier phase `code` of `system`. This is the signal the phase is aligned
to: `"L2P"` for GPS `L2S`, `"L1B"` for Galileo `L1C`, and `code` itself for
a reference signal. One band can hold more than one group of signals, each
with a reference of its own. BDS B1C and B1A share band 1 with the
references `L1D` and `L1S`.

`nothing` is a code the table states no alignment for. These are all of
SBAS, the restricted GPS Y and M and Galileo A and Z signals, QZSS `L1B`
and `L1Z`, and NavIC `L5B` and `L9B`.
"""
function reference_code(system::Char, code::AbstractString)
    found = phase_alignment_entry(system, code)
    isnothing(found) ? nothing : first(found)
end

"""
    phase_correction(system, code) -> Union{Float64,Nothing}

The correction in cycles that RINEX 3.05 Table A23 gives for the carrier
phase `code` of `system`, as the satellite issues it, to align it with the
reference signal of its band: `-0.25` for GPS `L2S`, `0.5` for Galileo `L1C`.
The sign follows section 5.2.12, φ_RINEX = φ_original + Δφ.

A receiver that issues its phases unaligned adds this to them and states it
as the correction of the code's [`PhaseShift`](@ref). One whose phases
arrive aligned states `0.0` instead. The correction is zero for the
reference itself and for the signals the table gives no shift ("None").

`nothing` is a code the table gives no number for. Some it says "must be
aligned" to their reference without saying by how much (GPS `L5X`, the
pilots of BDS-3, ...). Others depend on the satellite: GPS `L2C` on its
block, and QZSS `L1S` on Block I against Block II. It is also `nothing` for
the codes the table states no alignment for: all of SBAS, the restricted
GPS Y and M and Galileo A and Z signals, QZSS `L1B` and `L1Z`, and NavIC
`L5B` and `L9B`.

A header owes a code a [`PhaseShift`](@ref) unless its correction is `0.0`,
which includes the reference itself, or the table states no alignment for
it. Every other code needs one, whether `phase_correction` gives its number
or `nothing`.
"""
function phase_correction(system::Char, code::AbstractString)
    found = phase_alignment_entry(system, code)
    isnothing(found) ? nothing : last(found)
end

"""
    PhaseShift(system, code, correction; satellites = Int[])

One `SYS / PHASE SHIFT` header record: the correction in cycles that was
applied to the carrier phase `code` of `system` to align it with the
reference signal of its band (RINEX 3.05 Table A23). `satellites` names the
satellite numbers the correction applies to; an empty list means every
satellite of the system, which is the usual case.

RINEX 3.05 section 5.2.12 gives the record three distinct readings, and the
one a file makes is a statement about its data:

  - a **correction** (`-0.25`) says the phase was not aligned as it came out
    of the receiver and this is what was added to align it,
  - **zero** says the phase arrived aligned - from the receiver or from a
    stream such as RTCM-MSM - and nothing was applied,
  - a **blank** correction says the code needed none: it is the reference
    signal of its band, or a code Table A23 aligns to it with "None". This
    is what a code no `PhaseShift` names is written as.

The default is therefore a claim that no carrier phase in the file needed a
correction. That holds for the reference signals and for the codes Table
A23 aligns without one (GPS `L2W`, ...). A file carrying any other code (GPS
`L2S`, Galileo `L1C`, ...) has to say which of the first two applies to it,
or a reader cannot reconstruct what the receiver measured. So the writer
rejects a header that has no shift for a code whose
[`phase_correction`](@ref) is not zero. That function gives the correction
the ICDs define for the code:

    PhaseShift('E', "L1C", phase_correction('E', "L1C"))  # +0.5 was applied

Where [`phase_correction`](@ref) is `nothing`, the table still requires the
phase aligned but gives no correction that holds for every receiver or
satellite, so the shift states the one the receiver or converter applied.

A reference signal takes no correction other than zero, as nothing aligns
it, and a shift naming one with any other is rejected.

A shift limited to `satellites` names its code too. Section 5.2.12 lists
the satellites a correction affects, so the others of the system read as
having had nothing applied, as with zero.
"""
struct PhaseShift
    system::Char
    code::String
    correction::Float64
    satellites::Vector{Int}
    function PhaseShift(system, code, correction, satellites)
        check_satellite_system(system)
        check_carrier_phase_code(system, code)
        correction = Float64(correction)
        fits_fixed_field(correction, 5, 8) ||
            fixed_field_error("Phase shift of $system $code", correction, 5, 8)
        # The reference is what the other phases of its band are aligned to,
        # so it cannot have been shifted against itself.
        found = get(PHASE_ALIGNMENT, (system, String(code)), nothing)
        (iszero(correction) || isnothing(found) || first(found) != code) || throw(
            ArgumentError(
                "$system $code is the reference signal of its band in RINEX 3.05 " *
                "Table A23, which section 5.2.12 leaves uncorrected, so its phase " *
                "shift cannot be $correction cycles",
            ),
        )
        new(
            system,
            String(code),
            correction,
            check_phase_shift_satellites(system, code, collect(Int, satellites)),
        )
    end
end
PhaseShift(system::Char, code::AbstractString, correction::Real; satellites = Int[]) =
    PhaseShift(system, code, correction, satellites)

"""
    RinexObsHeader(; obs_codes, kwargs...)

Header of a RINEX 3.05 observation file.

`obs_codes` maps each satellite system character to the ordered list of
observation codes (RINEX table A2, e.g. `"C1C"`, `"L1C"`, `"D1C"`,
`"S1C"`) the file carries for that system. It is given as a vector of pairs
to keep the system order deterministic:

    obs_codes = ['G' => ["C1C", "L1C", "D1C", "S1C"]]

`phase_shifts` carries the [`PhaseShift`](@ref) records of the carrier
phases that were corrected to align them with the reference signal of their
band. A phase code no entry names is written as one that needed none, so
every phase code that RINEX 3.05 Table A23 gives a correction other than
"None" needs an entry.

`signal_strength_unit` is the unit of the `S` observations, written to the
optional `SIGNAL STRENGTH UNIT` record; `"DBHZ"` is the one RINEX 3.05
defines. Left as `nothing`, the record is omitted and the unit is
receiver-dependent as far as a reader knows.

`clock_offset_applied` is the optional `RCV CLOCK OFFS APPL` record: `true`
declares that the epochs, code and phase were corrected by the receiver
clock offset - a receiver that steers its epochs onto system time does so -
and `false` that they were not. Left as `nothing`, the record is omitted,
which a reader takes as `false`. The format requires the record when the
epochs report a `clock_offset`, so an epoch that carries one is rejected
while this is `nothing`.

`glonass_slots` lists the frequency channel number (-7 to +6) of each
GLONASS slot as `slot => channel`, for the mandatory `GLONASS SLOT / FRQ #`
record; a GLONASS satellite that has observations in an epoch has to be in
the list, or a reader cannot reconstruct its carrier frequency.
`glonass_code_phase_biases` are the code-phase biases in meters of `C1C`,
`C1P`, `C2C` and `C2P` for the mandatory `GLONASS COD/PHS/BIS` record:
zeros for data that is aligned, and `nothing`, the default, for biases that
are not known, which writes the record blank.

`time_of_first_obs` may be left as `nothing`; it is then taken from the
first epoch passed to [`write_epoch!`](@ref) and assigned to the header, so
that [`rinex_filename`](@ref) can name the file from the header afterwards.

The header is mutable, and the writer only reads it when it writes the
header out on the first epoch, so fields that the data provides late - a
position solution, the leap seconds decoded from the navigation message -
can be assigned to `writer.header` any time before that:

    writer.header.approx_position = position
    writer.header.leap_seconds = leap_seconds
"""
Base.@kwdef mutable struct RinexObsHeader
    program::String = "RINEXParser.jl"
    run_by::String = ""
    marker_name::String = "UNKNOWN"
    marker_type::String = "GEODETIC"
    observer::String = ""
    agency::String = ""
    receiver_number::String = ""
    receiver_type::String = ""
    receiver_version::String = ""
    antenna_number::String = ""
    antenna_type::String = ""
    approx_position::Union{Nothing,NTuple{3,Float64}} = nothing
    antenna_delta_hen::NTuple{3,Float64} = (0.0, 0.0, 0.0)
    obs_codes::Vector{Pair{Char,Vector{String}}}
    phase_shifts::Vector{PhaseShift} = PhaseShift[]
    signal_strength_unit::Union{Nothing,String} = nothing
    interval::Union{Nothing,Float64} = nothing
    time_of_first_obs::Union{Nothing,DateTime} = nothing
    clock_offset_applied::Union{Nothing,Bool} = nothing
    glonass_slots::Vector{Pair{Int,Int}} = Pair{Int,Int}[]
    glonass_code_phase_biases::Union{Nothing,NTuple{4,Float64}} = nothing
    leap_seconds::Union{Nothing,LeapSeconds} = nothing
end

"""
    ObsValue(value; lli = nothing, ssi = nothing)

A single observation: the measurement `value` plus the optional loss-of-lock
indicator `lli` and signal-strength indicator `ssi`. Units follow RINEX
conventions: pseudorange in meters, carrier phase in whole cycles, Doppler
in Hz, signal strength in dB-Hz.

The loss-of-lock indicator is a bit field of three bits, so it holds 0-7
(section 6.7.1); [`loss_of_lock_indicator`](@ref) sets its bits by name. The
signal strength is documented as 1-9, and `ssi = 0` is accepted next to
those: it is what a receiver reports for a projected signal strength it does
not have yet. [`signal_strength_indicator`](@ref) derives it from a C/N₀ in
dB-Hz.

A non-finite `value` is written as a blank field, which is how RINEX
records that an observation code carries no measurement for a satellite.
"""
struct ObsValue
    value::Float64
    lli::Union{Nothing,Int}
    ssi::Union{Nothing,Int}
    function ObsValue(value, lli, ssi)
        new(value, check_indicator(lli, "lli", 7), check_indicator(ssi, "ssi", 9))
    end
end
ObsValue(value; lli = nothing, ssi = nothing) = ObsValue(value, lli, ssi)

# Both indicators occupy a single column, so neither can hold more than one
# digit; the loss-of-lock indicator is narrower still, being three bits.
check_indicator(::Nothing, name, largest) = nothing
check_indicator(indicator::Integer, name, largest) =
    0 <= indicator <= largest ? Int(indicator) :
    throw(
        ArgumentError("Observation indicator $name is $indicator, but it holds 0-$largest"),
    )

"""
    loss_of_lock_indicator(; loss_of_lock = false, half_cycle = false, boc_tracking = false) -> Int

The loss-of-lock indicator of an [`ObsValue`](@ref), assembled from the
bits RINEX 3.05 section 6.7.1 gives it, so that none of them is set by its
number:

  - `loss_of_lock` (bit 0): lock was lost between the previous and this
    observation, so a cycle slip is possible.
  - `half_cycle` (bit 1): a half-cycle ambiguity or slip is possible, as it
    is for a phase tracked before the bit or pilot synchronisation resolved
    the polarity of the carrier. Software that cannot handle half cycles
    skips the observation. It holds for this epoch only.
  - `boc_tracking` (bit 2): an MBOC-modulated signal was tracked as BOC,
    which may make it noisier.

The indicator is defined for carrier phase observations only - all of it,
the BOC bit included: section 6.7.1 opens with "For phase observations
only", and Table A3 associates the LLI with the phase observation alone. So
[`write_epoch!`](@ref) rejects a non-zero one on any other observation code,
and a BOC-tracked signal sets `boc_tracking` on its `L` observation.

    ObsValue(phase; lli = loss_of_lock_indicator(half_cycle = !polarity_known))
"""
loss_of_lock_indicator(; loss_of_lock = false, half_cycle = false, boc_tracking = false) =
    Int(loss_of_lock) | Int(half_cycle) << 1 | Int(boc_tracking) << 2

"""
    signal_strength_indicator(cn0) -> Union{Int,Nothing}

The signal-strength indicator of an [`ObsValue`](@ref) for the carrier to
noise density `cn0` in dB-Hz, by the mapping RINEX 3.05 section 6.7.2
standardises: `min(max(floor(cn0 / 6), 1), 9)`, which puts the threshold of
good tracking, 5, at 30 dB-Hz. A value that is not finite is a signal
strength that is not known and returns `nothing`, which is written as a
blank indicator.

    ObsValue(pseudorange; ssi = signal_strength_indicator(cn0))
"""
signal_strength_indicator(cn0::Real) =
    isfinite(cn0) ? floor(Int, clamp(cn0, 6, 54) / 6) : nothing

"""
    SatObs(system, prn, observations)
    SatObs(header, system, prn, "C1C" => value, "L1C" => value, ...)

Observations of one satellite in one epoch.

The first form takes the observations aligned with the header's `obs_codes`
list for `system`, using `nothing` for observation codes without a
measurement. The second form addresses them by observation code
instead and derives the alignment from `header` (a [`RinexObsHeader`](@ref)
or a [`RinexObsWriter`](@ref)), which cannot be misaligned:

    SatObs(writer, 'G', 2, "C1C" => 21234567.890, "L1C" => ObsValue(111583948.752; ssi = 7))

A value is a plain number, an [`ObsValue`](@ref) carrying the loss-of-lock
and signal-strength indicators, or `nothing` for a measurement that is not
available in this epoch. Observation codes the header declares but the call
does not mention are left blank. Codes may also be given as symbols
(`:C1C`), and as any iterable of pairs instead of separate arguments.
"""
struct SatObs
    system::Char
    prn::Int
    observations::Vector{Union{Nothing,ObsValue}}
end
SatObs(system::Char, prn::Integer, observations::AbstractVector) =
    SatObs(system, Int(prn), Vector{Union{Nothing,ObsValue}}(observations))

SatObs(header::RinexObsHeader, system::Char, prn::Integer, observations::Pair...) =
    SatObs(header, system, prn, observations)

function SatObs(header::RinexObsHeader, system::Char, prn::Integer, observations)
    codes = obs_codes_for(header, system)
    values = Vector{Union{Nothing,ObsValue}}(nothing, length(codes))
    given = falses(length(codes))
    for observation in observations
        observation isa Pair || throw(
            ArgumentError(
                "Observations addressed by observation code are given as " *
                "\"C1C\" => value pairs, not as $(typeof(observation)); the form " *
                "taking a vector aligned with the header's obs_codes is " *
                "SatObs(system, prn, observations)",
            ),
        )
        code, value = observation
        code = obs_code(code)
        index = findfirst(==(code), codes)
        isnothing(index) && throw(
            ArgumentError(
                "Observation code \"$code\" is not declared for system '$system' in " *
                "the header, which carries $(join(codes, ", "))",
            ),
        )
        given[index] &&
            throw(ArgumentError("Observation code \"$code\" is given more than once"))
        given[index] = true
        values[index] = obs_value(value)
    end
    SatObs(system, Int(prn), values)
end

# The two halves of an observation pair, each answering what it does not
# accept instead of failing to convert it.
obs_code(code::AbstractString) = String(code)
obs_code(code::Symbol) = String(code)
obs_code(code) = throw(
    ArgumentError(
        "An observation code is named by a string or a symbol, like \"C1C\" or " *
        ":C1C, not by a $(typeof(code))",
    ),
)

obs_value(value::ObsValue) = value
obs_value(value::Real) = ObsValue(value)
obs_value(::Nothing) = nothing
obs_value(value) = throw(
    ArgumentError(
        "An observation is a number, an ObsValue or nothing for a measurement that " *
        "is not available, not a $(typeof(value))",
    ),
)

"""
    ObsEpoch(time, satellites; fractional_second = 0.0, flag = 0, clock_offset = nothing)

One observation epoch. `time` is the epoch in the file's time system (GPS
time for a GPS file); `fractional_second` carries sub-millisecond precision
beyond `DateTime`, so it is less than a millisecond in magnitude. `clock_offset` is the optional receiver clock offset in
seconds written at the end of the epoch record.

`flag` is 0 for an ordinary epoch and 1 to mark a power failure between the
previous epoch and this one. The remaining flags of RINEX 3.05 Table A3
(2-5) introduce event records, whose epoch line counts header records rather
than satellites and is followed by those instead of by observations; this
writer does not produce them, so it rejects those flags rather than write
observations under a record type that does not carry them.
"""
struct ObsEpoch
    time::DateTime
    fractional_second::Float64
    flag::Int
    clock_offset::Union{Nothing,Float64}
    satellites::Vector{SatObs}
    function ObsEpoch(time, fractional_second, flag, clock_offset, satellites)
        flag in (0, 1) || throw(
            ArgumentError(
                "The epoch flag is $flag, but this writer records observations, " *
                "which is flag 0 or - for a power failure since the previous epoch " *
                "- flag 1; the event records of flags 2-5 are not written",
            ),
        )
        # A negative fraction is the floating-point remainder of splitting a
        # time into milliseconds and the rest, which can land a hair below
        # zero.
        abs(fractional_second) < 1e-3 || throw(
            ArgumentError(
                "The fractional second of an epoch is $fractional_second, but it " *
                "carries the part of the time below the milliseconds of the " *
                "DateTime, which is less than 0.001 in magnitude",
            ),
        )
        new(time, fractional_second, flag, clock_offset, satellites)
    end
end
ObsEpoch(
    time::DateTime,
    satellites::AbstractVector{SatObs};
    fractional_second = 0.0,
    flag = 0,
    clock_offset = nothing,
) = ObsEpoch(time, fractional_second, flag, clock_offset, collect(satellites))

"""
    RinexObsWriter(target, header::RinexObsHeader)

Streaming writer for a RINEX 3.05 observation file. `target` is a path or
an `IO`. The header is written lazily on the first [`write_epoch!`](@ref),
so `time_of_first_obs` can be filled in from the data, and the mutable
[`RinexObsHeader`](@ref) in `writer.header` can be completed until then.
Close the writer (or use the do-block form) to flush the file.

    RinexObsWriter("data.obs", header) do writer
        write_epoch!(writer, epoch)
    end
"""
mutable struct RinexObsWriter{T<:IO}
    io::T
    header::RinexObsHeader
    header_written::Bool
    owns_io::Bool
    record::RecordBuffer
end
function RinexObsWriter(io::IO, header::RinexObsHeader)
    check_obs_header(header)
    RinexObsWriter(io, header, false, false, RecordBuffer())
end
function RinexObsWriter(path::AbstractString, header::RinexObsHeader)
    check_obs_header(header)
    RinexObsWriter(open(path, "w"), header, false, true, RecordBuffer())
end

function RinexObsWriter(f::Function, target, header::RinexObsHeader)
    writer = RinexObsWriter(target, header)
    try
        f(writer)
    finally
        close(writer)
    end
end

# Checked when the writer is created, so a header the records cannot hold
# does not surface from the lazy header write inside `close`.
function check_obs_header(header::RinexObsHeader)
    # Data lines are matched to the first list of their system, so a second
    # list of a system, or a second entry of a code, would describe columns
    # no data line has.
    for (i, (system, codes)) in enumerate(header.obs_codes)
        check_satellite_system(system)
        any(p -> first(p) == system, view(header.obs_codes, 1:(i-1))) && throw(
            ArgumentError(
                "The header lists observation codes for system '$system' twice; " *
                "give all of them in one list",
            ),
        )
        for (j, code) in enumerate(codes)
            check_observation_code(system, code)
            code in view(codes, 1:(j-1)) && throw(
                ArgumentError(
                    "Observation code \"$code\" is declared twice for system '$system'",
                ),
            )
        end
    end
    check_header_field(header.program, 20, "The program of the header")
    check_header_field(header.run_by, 20, "The agency running the program")
    check_header_field(header.marker_name, 60, "The marker name")
    check_header_field(header.marker_type, 20, "The marker type")
    check_header_field(header.observer, 20, "The observer")
    check_header_field(header.agency, 40, "The agency")
    check_header_field(header.receiver_number, 20, "The receiver number")
    check_header_field(header.receiver_type, 20, "The receiver type")
    check_header_field(header.receiver_version, 20, "The receiver version")
    check_header_field(header.antenna_number, 20, "The antenna number")
    check_header_field(header.antenna_type, 20, "The antenna type")
    isnothing(header.signal_strength_unit) ||
        check_header_field(header.signal_strength_unit, 20, "The signal strength unit")
    for (i, (slot, channel)) in enumerate(header.glonass_slots)
        check_satellite_number('R', slot)
        -7 <= channel <= 6 || throw(
            ArgumentError(
                "The frequency channel of GLONASS slot $slot is $channel, but it " *
                "is -7 to +6",
            ),
        )
        any(p -> first(p) == slot, view(header.glonass_slots, 1:(i-1))) && throw(
            ArgumentError("GLONASS slot $slot is given more than one frequency channel"),
        )
    end
    for bias in something(header.glonass_code_phase_biases, ())
        fits_fixed_field(bias, 3, 8) ||
            fixed_field_error("A GLONASS code-phase bias", bias, 3, 8)
    end
    for (i, shift) in enumerate(header.phase_shifts)
        check_phase_shift_satellites(shift.system, shift.code, shift.satellites)
        codes = obs_codes_for(header, shift.system)
        shift.code in codes || throw(
            ArgumentError(
                "The phase shift of $(shift.system) $(shift.code) names an " *
                "observation code the header does not declare for system " *
                "'$(shift.system)'; it declares $(join(codes, ", "))",
            ),
        )
        # One code may carry several records, one per group of satellites,
        # but a satellite cannot be told two corrections for the same phase
        # - and an empty list already claims all of them.
        for other in view(header.phase_shifts, 1:(i-1))
            (other.system == shift.system && other.code == shift.code) || continue
            overlap = shared_satellites(shift, other)
            isempty(overlap) || throw(
                ArgumentError(
                    "Two phase shifts of $(shift.system) $(shift.code) apply to " *
                    "$overlap, which would tell it two corrections for one " *
                    "carrier phase",
                ),
            )
        end
    end
    # A phase code no shift names is written blank, which says it needed no
    # correction. A shift for some of the satellites names it as well, see
    # `PhaseShift`.
    for (system, codes) in header.obs_codes, code in codes
        # Only the carrier phases Table A23 gives "None" or states no
        # alignment for can be written blank.
        found = get(PHASE_ALIGNMENT, (system, code), nothing)
        isnothing(found) && continue
        reference, correction = found
        (!isnothing(correction) && iszero(correction)) && continue
        any(s -> s.system == system && s.code == code, header.phase_shifts) && continue
        alignment =
            isnothing(correction) ?
            "requires it aligned to $reference, without a correction that holds " *
            "for every receiver or satellite" :
            "aligns it to $reference with a correction of $correction cycles"
        throw(
            ArgumentError(
                "$(SYSTEM_NAMES[system]) carrier phase $code needs a PhaseShift: " *
                "without one its SYS / PHASE SHIFT record is blank, which says it " *
                "needed no correction, but RINEX 3.05 Table A23 $alignment. State " *
                "the correction that was applied to align it, or 0.0 if it arrived " *
                "aligned",
            ),
        )
    end
    nothing
end

# The satellites two phase shifts of one code both apply to, as text for the
# error that rejects them; an empty list means every satellite.
function shared_satellites(a::PhaseShift, b::PhaseShift)
    (isempty(a.satellites) || isempty(b.satellites)) &&
        return "every satellite of the system"
    shared = sort(intersect(a.satellites, b.satellites))
    join(map(prn -> satellite_id(a.system, prn), shared), ", ")
end

function Base.close(writer::RinexObsWriter)
    try
        # An empty file still gets its header, so it is valid RINEX.
        writer.header_written || write_obs_header(writer, nothing, 0.0)
    finally
        writer.owns_io ? close(writer.io) : flush(writer.io)
    end
    nothing
end

SatObs(writer::RinexObsWriter, args...) = SatObs(writer.header, args...)

function obs_codes_for(header::RinexObsHeader, system::Char)
    index = findfirst(p -> first(p) == system, header.obs_codes)
    isnothing(index) && throw(
        ArgumentError(
            "The header declares no observation codes for system '$system'; it " *
            "carries the systems " *
            join(map(p -> "'$(first(p))'", header.obs_codes), ", "),
        ),
    )
    last(header.obs_codes[index])
end

function write_obs_header(writer::RinexObsWriter, first_epoch_time, first_epoch_fraction)
    io = writer.io
    header = writer.header
    # Checked again here, not only where the writer was created: the header
    # is documented as assignable until this runs, so this is the first
    # point at which what is written out is known.
    check_obs_header(header)
    version_type_line(io, "OBSERVATION DATA", first.(header.obs_codes))
    program_line(io, header.program, header.run_by)
    header_line(io, header.marker_name, "MARKER NAME")
    header_line(io, header.marker_type, "MARKER TYPE")
    header_line(io, rpad(header.observer, 20) * header.agency, "OBSERVER / AGENCY")
    header_line(
        io,
        rpad(header.receiver_number, 20) *
        rpad(header.receiver_type, 20) *
        header.receiver_version,
        "REC # / TYPE / VERS",
    )
    header_line(io, rpad(header.antenna_number, 20) * header.antenna_type, "ANT # / TYPE")
    if !isnothing(header.approx_position)
        content = join(Printf.format(FMT_F14_4, x) for x in header.approx_position)
        header_line(io, content, "APPROX POSITION XYZ")
    end
    content = join(Printf.format(FMT_F14_4, x) for x in header.antenna_delta_hen)
    header_line(io, content, "ANTENNA: DELTA H/E/N")
    for (system, codes) in header.obs_codes
        for (i, chunk) in enumerate(Iterators.partition(codes, 13))
            lead = i == 1 ? string(system, "  ", lpad(length(codes), 3)) : " "^6
            header_line(io, lead * join(" " .* chunk), "SYS / # / OBS TYPES")
        end
    end
    if !isnothing(header.signal_strength_unit)
        header_line(io, header.signal_strength_unit, "SIGNAL STRENGTH UNIT")
    end
    if !isnothing(header.interval)
        header_line(io, Printf.format(FMT_F10_3, header.interval), "INTERVAL")
    end
    # The epoch the record is taken from carries the sub-millisecond part of
    # its seconds, which the header field is wide enough to hold; a time the
    # header itself was given has none. Taking it from the data also fills
    # the header field in, so that `rinex_filename` can name the file from
    # the header once the first epoch has been written.
    if isnothing(header.time_of_first_obs) && !isnothing(first_epoch_time)
        header.time_of_first_obs = first_epoch_time
        fraction = first_epoch_fraction
    else
        fraction = 0.0
    end
    if !isnothing(header.time_of_first_obs)
        t, seconds = epoch_minute_seconds(header.time_of_first_obs, fraction)
        content =
            lpad(year(t), 6) *
            lpad(month(t), 6) *
            lpad(day(t), 6) *
            lpad(hour(t), 6) *
            lpad(minute(t), 6) *
            Printf.format(FMT_F13_7, seconds) *
            " "^5 *
            time_system(first.(header.obs_codes))
        header_line(io, content, "TIME OF FIRST OBS")
    end
    if !isnothing(header.clock_offset_applied)
        header_line(io, lpad(Int(header.clock_offset_applied), 6), "RCV CLOCK OFFS APPL")
    end
    # One record per carrier phase, which the format makes mandatory: the
    # correction that aligned it, or a blank saying it needed none. See
    # `PhaseShift` for what each of them claims.
    for (system, codes) in header.obs_codes, code in codes
        startswith(code, "L") || continue
        stated = false
        # A code may carry more than one record, because a correction need
        # not apply to every satellite of the system.
        for shift in header.phase_shifts
            (shift.system == system && shift.code == code) || continue
            phase_shift_lines(io, system, code, shift)
            stated = true
        end
        stated || phase_shift_lines(io, system, code, nothing)
    end
    glonass_slot_lines(io, header.glonass_slots)
    glonass_bias_line(io, header.glonass_code_phase_biases)
    if !isnothing(header.leap_seconds)
        header_line(io, leap_seconds_content(header.leap_seconds), "LEAP SECONDS")
    end
    header_line(io, "", "END OF HEADER")
    writer.header_written = true
end

# `I3,1X,8(A1,I2.2,1X,I2,1X)`, continued past the count for more than
# eight slots. An empty list still writes the record, which is mandatory.
function glonass_slot_lines(io::IO, slots)
    lead = lpad(length(slots), 3) * " "
    entries = [
        string('R', lpad(slot, 2, '0'), ' ', lpad(channel, 2), ' ') for
        (slot, channel) in slots
    ]
    isempty(entries) && return header_line(io, lead, "GLONASS SLOT / FRQ #")
    for (i, chunk) in enumerate(Iterators.partition(entries, 8))
        header_line(io, (i == 1 ? lead : " "^4) * join(chunk), "GLONASS SLOT / FRQ #")
    end
end

# `4(1X,A3,1X,F8.3)`, blank throughout when the biases are not known.
glonass_bias_line(io::IO, ::Nothing) = header_line(io, "", "GLONASS COD/PHS/BIS")
glonass_bias_line(io::IO, biases::NTuple{4,Float64}) = header_line(
    io,
    join(
        string(' ', code, ' ', Printf.format(FMT_F8_3, bias)) for
        (code, bias) in zip(("C1C", "C1P", "C2C", "C2P"), biases)
    ),
    "GLONASS COD/PHS/BIS",
)

# `A1,1X,A3,1X,F8.5,2X,I2.2` and then the satellite numbers as `10(1X,A3)`,
# continued on further records - indented past the fields they repeat - when
# more than ten of them are named.
const PHASE_SHIFT_SATELLITES_PER_LINE = 10

function phase_shift_lines(io::IO, system::Char, code::AbstractString, ::Nothing)
    header_line(io, string(system, ' ', code), "SYS / PHASE SHIFT")
end
function phase_shift_lines(io::IO, system::Char, code::AbstractString, shift::PhaseShift)
    lead = string(system, ' ', code, ' ') * Printf.format(FMT_F8_5, shift.correction)
    if isempty(shift.satellites)
        return header_line(io, lead, "SYS / PHASE SHIFT")
    end
    # A count of zero already means "every satellite of the system", so the
    # field carries the length of a list that is written out.
    lead *= " "^2 * lpad(length(shift.satellites), 2, '0')
    for (i, chunk) in
        enumerate(Iterators.partition(shift.satellites, PHASE_SHIFT_SATELLITES_PER_LINE))
        content =
            (i == 1 ? lead : " "^18) *
            join(' ' * satellite_id(system, prn) for prn in chunk)
        header_line(io, content, "SYS / PHASE SHIFT")
    end
    nothing
end

add_indicator!(record::RecordBuffer, ::Nothing) = add_char!(record, ' ')
add_indicator!(record::RecordBuffer, indicator::Int) =
    add_char!(record, Char('0' + indicator))

# An observation field is 14 columns of value plus one column each for the
# loss-of-lock and signal-strength indicator. A measurement that is not
# available - `nothing`, or a value that is not finite - leaves the whole
# field blank, which is what RINEX reads as "no observation"; a finite value
# too large for its columns is an error rather than a shifted record.
#
# The loss-of-lock indicator is defined for carrier phases only (section
# 6.7.1), so a lost lock flagged on a pseudorange, a Doppler or a signal
# strength is an error rather than a flag no reader looks for there; a zero
# is "OK or not known" and stays valid on any of them.
add_observation!(record::RecordBuffer, ::Nothing, sat::SatObs, code) =
    add_blanks!(record, 16)
function add_observation!(record::RecordBuffer, obs::ObsValue, sat::SatObs, code)
    (something(obs.lli, 0) == 0 || first(code) == 'L') || throw(
        ArgumentError(
            "Observation $code of satellite $(satellite_id(sat.system, sat.prn)) " *
            "carries the loss-of-lock indicator $(obs.lli), but the indicator is " *
            "defined for carrier phase observations only",
        ),
    )
    isfinite(obs.value) || return add_blanks!(record, 16)
    fits_fixed_field(obs.value, 3, 14) || fixed_field_error(
        "Observation $code of satellite $(satellite_id(sat.system, sat.prn))",
        obs.value,
        3,
        14,
    )
    add_field!(record, FMT_F14_3, obs.value)
    add_indicator!(record, obs.lli)
    add_indicator!(record, obs.ssi)
end

"""
    write_epoch!(writer::RinexObsWriter, epoch::ObsEpoch)

Append one epoch record. Writes the file header first if it has not been
written yet. The whole epoch is checked before its first line is written, so
an epoch this rejects leaves the file as it was.
"""
function write_epoch!(writer::RinexObsWriter, epoch::ObsEpoch)
    # Assembled whole before it is written, so a rejected epoch leaves the
    # file as it was.
    record = start_record!(writer.record)
    t, seconds = epoch_minute_seconds(epoch.time, epoch.fractional_second)
    add_char!(record, '>')
    add_char!(record, ' ')
    add_epoch_date!(record, t)
    add_field!(record, FMT_F11_7, seconds)
    add_blanks!(record, 2)
    add_integer!(record, epoch.flag, 1)
    add_integer!(record, length(epoch.satellites), 3)
    if !isnothing(epoch.clock_offset)
        offset = epoch.clock_offset
        fits_fixed_field(offset, 12, 15) ||
            fixed_field_error("Receiver clock offset of the epoch", offset, 12, 15)
        add_blanks!(record, 6)
        add_field!(record, FMT_F15_12, offset)
    end
    end_line!(record)
    if !isnothing(epoch.clock_offset) && isnothing(writer.header.clock_offset_applied)
        throw(
            ArgumentError(
                "The epoch reports a receiver clock offset, which RINEX 3.05 only " *
                "allows with the RCV CLOCK OFFS APPL record; set the header's " *
                "clock_offset_applied to say whether the offset was applied",
            ),
        )
    end
    for sat in epoch.satellites
        sat.system != 'R' ||
            any(p -> first(p) == sat.prn, writer.header.glonass_slots) ||
            throw(
                ArgumentError(
                    "GLONASS satellite $(satellite_id('R', sat.prn)) has observations, " *
                    "but the header's glonass_slots gives no frequency channel for it",
                ),
            )
        codes = obs_codes_for(writer.header, sat.system)
        length(sat.observations) == length(codes) || throw(
            ArgumentError(
                "Satellite $(satellite_id(sat.system, sat.prn)) carries " *
                "$(length(sat.observations)) observations, but the header declares " *
                "$(length(codes)) observation codes for system '$(sat.system)'",
            ),
        )
        # Full-width lines (no trailing-blank trimming) for the benefit of
        # fixed-column parsers, matching RTKLIB and GNSS-SDR output.
        add_satellite_id!(record, sat.system, sat.prn)
        for (code, obs) in zip(codes, sat.observations)
            add_observation!(record, obs, sat, code)
        end
        end_line!(record)
    end
    writer.header_written || write_obs_header(writer, epoch.time, epoch.fractional_second)
    flush_record!(writer.io, record)
    nothing
end
