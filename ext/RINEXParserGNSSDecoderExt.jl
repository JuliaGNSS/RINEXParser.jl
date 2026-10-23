module RINEXParserGNSSDecoderExt

# The broadcast navigation message is decoded into GNSSDecoder's per-signal
# data types; the conversions below map them onto the records of the RINEX
# 3.05 navigation files: unit scaling, the issue-of-data fields, the packed
# health words and the week counts. The decoders hold the broadcast angles in
# radians already, scaled from semicircles with the ICD's truncated π, which
# is what RINEX navigation records give: they pass through.

using GNSSDecoder:
    GNSSDecoder,
    GNSSDecoderState,
    is_decoding_completed_for_positioning,
    resolve_reference_week
import RINEXParser: rinex_ephemeris, has_rinex_ephemeris, add_header_records!
using RINEXParser:
    RINEXParser,
    BeiDouEphemeris,
    GalileoEphemeris,
    GPSEphemeris,
    IonosphericCorrection,
    LeapSeconds,
    RinexNavHeader,
    TimeSystemCorrection,
    galileo_data_sources,
    galileo_sv_health,
    ionosphere_time_mark,
    navigation_times

const GPSData = GNSSDecoder.GPSL1CAData
const GalileoData = Union{GNSSDecoder.GalileoINAVData,GNSSDecoder.GalileoE5aData}
const BeiDouData = GNSSDecoder.BeiDouDNAVData

satellite_system(::GPSData) = 'G'
satellite_system(::GalileoData) = 'E'
satellite_system(::BeiDouData) = 'C'

# The continuous week of a message on its constellation's own count: the one
# given, or the decoded one where the message broadcasts all of it.
message_week(decoder, week::Integer) = Int(week)
message_week(decoder, ::Nothing) = decoder.data.WN
message_week(::GNSSDecoderState{<:GPSData}, ::Nothing) = throw(
    ArgumentError(
        "GPS LNAV broadcasts its week in 10 bits, so the continuous week of a GPS " *
        "decoder has to be given, e.g. as week = PositionVelocityTime.get_week(" *
        "decoder; approximate_year)",
    ),
)

# The continuous week a header record of the message counts: aligned with
# the GPS week for Galileo. `nothing` before the week was decoded.
function header_week(decoder, week)
    week = message_week(decoder, week)
    isnothing(week) && return nothing
    first(RINEXParser.record_week(satellite_system(decoder.data), week))
end

# Messages RINEX 3.05 has a record for, and every other one.
has_rinex_ephemeris(::GNSSDecoderState) = false
has_rinex_ephemeris(::GNSSDecoderState{<:Union{GPSData,GalileoData,BeiDouData}}) = true

rinex_ephemeris(::GNSSDecoderState; week = nothing) = nothing

function rinex_ephemeris(decoder::GNSSDecoderState{<:GPSData}; week = nothing)
    is_decoding_completed_for_positioning(decoder) || return nothing
    data = decoder.data
    times = navigation_times(
        'G';
        week = message_week(decoder, week),
        transmission_time = data.TOW,
        toe = data.t_0e,
        toc = data.t_0c,
    )
    GPSEphemeris(;
        prn = decoder.prn,
        toc = times.toc,
        af0 = data.a_f0,
        af1 = data.a_f1,
        af2 = data.a_f2,
        iode = data.IODE_Sub_2,
        crs = data.C_rs,
        deltan = data.Δn,
        m0 = data.M_0,
        cuc = data.C_uc,
        e = data.e,
        cus = data.C_us,
        sqrt_a = data.sqrt_A,
        toe = data.t_0e,
        cic = data.C_ic,
        omega0 = data.Ω_0,
        cis = data.C_is,
        i0 = data.i_0,
        crc = data.C_rc,
        omega = data.ω,
        omegadot = data.Ω_dot,
        idot = data.i_dot,
        codes_on_l2 = something(data.code_on_L2, 0),
        week = times.week,
        l2p_data_flag = something(data.L2_P_data_flag, false) ? 1 : 0,
        sv_accuracy = ura_metres(data.URA_index),
        sv_health = data.sv_health,
        tgd = data.T_GD,
        iodc = data.IODC,
        transmission_time = times.transmission_time,
        # The broadcast curve-fit flag only distinguishes the nominal four-hour
        # interval from a longer one; six hours is the extended value the
        # constellation uses (IS-GPS-200N Table 20-XII).
        fit_interval = something(data.fit_interval, false) ? 6.0 : 4.0,
    )
end

# The metres of a GPS URA or BDS URAI index, two geometric segments
# (IS-GPS-200N Table 20-I), and `beyond` for the top index or none.
function range_accuracy_metres(index, beyond)
    isnothing(index) && return beyond
    index <= 6 && return 2.0^(1 + index / 2)
    index <= 14 && return 2.0^(index - 2)
    beyond
end

# GPS user range accuracy. Index 15 is "no accuracy prediction available",
# which RINEX reports as a negative accuracy, as `sisa_metres` does Galileo's.
ura_metres(index) = range_accuracy_metres(index, -1.0)

# BDS user range accuracy (RINEX 3.05 Table A14). Index 15 is "use at own
# risk", which RINEX reports as 8192 m.
bds_accuracy_metres(index) = range_accuracy_metres(index, 8192.0)

# Galileo signal-in-space accuracy: the broadcast SISA index maps onto metres
# in four linear segments (Galileo OS SIS ICD Table 92). Index 255 means "no
# accuracy prediction available" (NAPA), and the spare range above 125 is
# equally meaningless; RINEX reports both as a negative accuracy.
function sisa_metres(index::Integer)
    index <= 49 && return 0.01 * index
    index <= 74 && return 0.5 + 0.02 * (index - 50)
    index <= 99 && return 1.0 + 0.04 * (index - 75)
    index <= 125 && return 2.0 + 0.16 * (index - 100)
    -1.0
end
sisa_metres(::Nothing) = -1.0

# The broadcast health and data-validity fields as the plain integers the
# RINEX bit fields are packed from. A signal whose status a message does not
# carry is reported healthy and valid, which is what a RINEX file from a
# receiver tracking only that one band says too.
status_bits(status, healthy) = Int(something(status, healthy))
signal_health_bits(status) = status_bits(status, GNSSDecoder.signal_ok)
data_validity_bits(status) = status_bits(status, GNSSDecoder.navigation_data_valid)

# An I/NAV message carries the E1-B and E5b health, an F/NAV message the E5a
# health (RINEX 3.05 Table A8).
galileo_health(data::GNSSDecoder.GalileoINAVData) = galileo_sv_health(;
    e1b_dvs = data_validity_bits(data.E1B_DVS),
    e1b_hs = signal_health_bits(data.E1B_SHS),
    e5b_dvs = data_validity_bits(data.E5b_DVS),
    e5b_hs = signal_health_bits(data.E5b_SHS),
)
galileo_health(data::GNSSDecoder.GalileoE5aData) = galileo_sv_health(;
    e5a_dvs = data_validity_bits(data.E5a_DVS),
    e5a_hs = signal_health_bits(data.E5a_SHS),
)

# E1-B and E5b both broadcast I/NAV into the same data type, so the signal a
# record was decoded from is told apart by the decoder's constants. The
# source keys a record's identity, so the I/NAV and F/NAV messages of one
# satellite stay the separate records RINEX requires.
galileo_sources(::GNSSDecoderState{<:GNSSDecoder.GalileoINAVData}) =
    galileo_data_sources(; inav_e1b = true)
galileo_sources(
    ::GNSSDecoderState{<:GNSSDecoder.GalileoINAVData,<:GNSSDecoder.GalileoE5bConstants},
) = galileo_data_sources(; inav_e5b = true)
galileo_sources(::GNSSDecoderState{<:GNSSDecoder.GalileoE5aData}) =
    galileo_data_sources(; fnav_e5a = true)

# I/NAV broadcasts the group delay of both Galileo band pairs, F/NAV only the
# E5a/E1 one; RINEX leaves the term a message does not carry at zero.
galileo_bgd_e5b_e1(data::GNSSDecoder.GalileoINAVData) = data.BGD_E1_E5b
galileo_bgd_e5b_e1(::GNSSDecoder.GalileoE5aData) = 0.0

galileo_sisa(data::GNSSDecoder.GalileoINAVData) = sisa_metres(data.SISA_E1_E5b)
galileo_sisa(data::GNSSDecoder.GalileoE5aData) = sisa_metres(data.SISA_E1_E5a)

function rinex_ephemeris(decoder::GNSSDecoderState{<:GalileoData}; week = nothing)
    is_decoding_completed_for_positioning(decoder) || return nothing
    data = decoder.data
    times = navigation_times(
        'E';
        week = message_week(decoder, week),
        transmission_time = data.TOW,
        toe = data.t_0e,
        toc = data.t_0c,
    )
    GalileoEphemeris(;
        prn = decoder.prn,
        toc = times.toc,
        af0 = data.a_f0,
        af1 = data.a_f1,
        af2 = data.a_f2,
        iodnav = data.IOD_nav1,
        crs = data.C_rs,
        deltan = data.Δn,
        m0 = data.M_0,
        cuc = data.C_uc,
        e = data.e,
        cus = data.C_us,
        sqrt_a = data.sqrt_A,
        toe = data.t_0e,
        cic = data.C_ic,
        omega0 = data.Ω_0,
        cis = data.C_is,
        i0 = data.i_0,
        crc = data.C_rc,
        omega = data.ω,
        omegadot = data.Ω_dot,
        idot = data.i_dot,
        data_sources = galileo_sources(decoder),
        week = times.week,
        sisa = galileo_sisa(data),
        sv_health = galileo_health(data),
        bgd_e5a_e1 = data.BGD_E1_E5a,
        bgd_e5b_e1 = galileo_bgd_e5b_e1(data),
        transmission_time = times.transmission_time,
    )
end

function rinex_ephemeris(decoder::GNSSDecoderState{<:BeiDouData}; week = nothing)
    is_decoding_completed_for_positioning(decoder) || return nothing
    data = decoder.data
    # Every time of a BDS record is BDT: seconds of the BDT week, and the
    # calendar epoch they make with the week is BDT's too.
    times = navigation_times(
        'C';
        week = message_week(decoder, week),
        transmission_time = data.SOW,
        toe = data.t_0e,
        toc = data.t_0c,
    )
    BeiDouEphemeris(;
        prn = decoder.prn,
        toc = times.toc,
        af0 = data.a_f0,
        af1 = data.a_f1,
        af2 = data.a_f2,
        aode = data.AODE,
        crs = data.C_rs,
        deltan = data.Δn,
        m0 = data.M_0,
        cuc = data.C_uc,
        e = data.e,
        cus = data.C_us,
        sqrt_a = data.sqrt_A,
        toe = data.t_0e,
        cic = data.C_ic,
        omega0 = data.Ω_0,
        cis = data.C_is,
        i0 = data.i_0,
        crc = data.C_rc,
        omega = data.ω,
        omegadot = data.Ω_dot,
        idot = data.i_dot,
        week = times.week,
        sv_accuracy = bds_accuracy_metres(data.URAI),
        sath1 = data.SatH1,
        tgd1_b1_b3 = data.T_GD1,
        tgd2_b2_b3 = data.T_GD2,
        transmission_time = times.transmission_time,
        aodc = data.AODC,
    )
end

# ─────────────────────────────────────────────────────────────────────────
# Navigation-file header

# Messages that carry no header records, and the ones that do.
add_header_records!(header::RinexNavHeader, ::GNSSDecoderState; week = nothing) = header

function add_header_records!(
    header::RinexNavHeader,
    decoder::GNSSDecoderState{<:Union{GPSData,GalileoData,BeiDouData}};
    week = nothing,
)
    for correction in ionospheric_corrections(decoder.data, decoder.prn)
        replace_record!(header.ionospheric_corrections, correction, ionospheric_key)
    end
    corrections = time_system_corrections(decoder.data, () -> header_week(decoder, week))
    for correction in corrections
        replace_record!(header.time_system_corrections, correction, c -> c.type)
    end
    leap_seconds = broadcast_leap_seconds(decoder.data, () -> header_week(decoder, week))
    preferred_leap_seconds(header.leap_seconds, leap_seconds) &&
        (header.leap_seconds = leap_seconds)
    header
end

# A record replaces the one of the same `key`, so the latest broadcast is the
# one written.
function replace_record!(records, record, key)
    index = findfirst(r -> key(r) == key(record), records)
    isnothing(index) ? push!(records, record) : (records[index] = record)
    records
end

# BDS broadcasts several sets a day, told apart by when and by which
# satellite they were transmitted.
ionospheric_key(correction) = (correction.type, correction.time_mark, correction.sv_id)

# Klobuchar (GPS, BDS) and NeQuick (Galileo) coefficients the satellite has
# broadcast.
function klobuchar_corrections(data, alpha, beta; kwargs...)
    corrections = IonosphericCorrection[]
    isnothing(data.α_0) || push!(
        corrections,
        IonosphericCorrection(alpha, (data.α_0, data.α_1, data.α_2, data.α_3); kwargs...),
    )
    isnothing(data.β_0) || push!(
        corrections,
        IonosphericCorrection(beta, (data.β_0, data.β_1, data.β_2, data.β_3); kwargs...),
    )
    corrections
end
ionospheric_corrections(data::GPSData, prn) = klobuchar_corrections(data, "GPSA", "GPSB")
function ionospheric_corrections(data::BeiDouData, prn)
    # RINEX 3.05 Table A5 makes the time mark and the satellite mandatory for
    # BDS. Both describe the transmission, so a message that has not reported
    # its second of week yet cannot carry them.
    isnothing(data.SOW) && return IonosphericCorrection[]
    klobuchar_corrections(
        data,
        "BDSA",
        "BDSB";
        time_mark = ionosphere_time_mark(data.SOW),
        sv_id = prn,
    )
end
function ionospheric_corrections(data::GalileoData, prn)
    isnothing(data.a_i0) && return IonosphericCorrection[]
    [IonosphericCorrection("GAL", (data.a_i0, data.a_i1, data.a_i2))]
end

# Broadcast reference weeks arrive truncated - the UTC and leap-second weeks
# to 8 bits, Galileo's GGTO week to 6 - while a header record wants the
# continuous week. Each is lifted to the representative nearest the
# message's own continuous week, which `week()` gives: it is asked only for a
# record that needs it, as a GPS decoder cannot give one without help.
const UTC_WN_MODULUS = 256
const GGTO_WN_MODULUS = 64

function time_system_correction(type, a0, a1, t_0, WN_0, week, modulus)
    any(isnothing, (a0, a1, t_0, WN_0)) && return nothing
    continuous = week()
    isnothing(continuous) && return nothing
    TimeSystemCorrection(
        type,
        a0,
        a1,
        t_0,
        resolve_reference_week(WN_0, continuous, modulus),
    )
end

time_system_corrections(data::GPSData, week) = filter(
    !isnothing,
    [
        time_system_correction(
            "GPUT",
            data.A_0UTC,
            data.A_1UTC,
            data.t_0t,
            data.WN_0t,
            week,
            UTC_WN_MODULUS,
        ),
    ],
)
time_system_corrections(data::GalileoData, week) = filter(
    !isnothing,
    [
        time_system_correction(
            "GAUT",
            data.A_0UTC,
            data.A_1UTC,
            data.t_0t,
            data.WN_0t,
            week,
            UTC_WN_MODULUS,
        ),
        time_system_correction(
            "GPGA",
            data.A_0G,
            data.A_1G,
            data.t_0G,
            data.WN_0G,
            week,
            GGTO_WN_MODULUS,
        ),
    ],
)
function time_system_corrections(data::BeiDouData, week)
    isnothing(data.A_0UTC) && return TimeSystemCorrection[]
    continuous = week()
    isnothing(continuous) && return TimeSystemCorrection[]
    # D1/D2 broadcasts no reference epoch for its UTC offset, so the record's
    # reference time is zero of the current BDT week.
    [TimeSystemCorrection("BDUT", data.A_0UTC, data.A_1UTC, 0, continuous)]
end

# The broadcast leap seconds, as the full record RINEX prefers (current
# count, count after the next event, and the week and day it falls on) where
# the satellite sent all of it. GPS and Galileo count them alike, as a blank
# time system is read. BDS counts BDT - UTC, 14 s fewer, and its week and day
# from the BDT epoch, so its record names `"BDT"`.
function broadcast_leap_seconds(data, week)
    isnothing(data.Δt_LS) && return nothing
    time_system = data isa BeiDouData ? "BDT" : ""
    any(isnothing, (data.Δt_LSF, data.WN_LSF, data.DN)) &&
        return LeapSeconds(Int(data.Δt_LS); time_system)
    continuous = week()
    isnothing(continuous) && return LeapSeconds(Int(data.Δt_LS); time_system)
    LeapSeconds(
        Int(data.Δt_LS);
        future_count = Int(data.Δt_LSF),
        week = resolve_reference_week(data.WN_LSF, continuous, UTC_WN_MODULUS),
        day = Int(data.DN),
        time_system,
    )
end

# Whether the leap seconds `new` are to be written over `current`: a count of
# GPS time over one of BDT, and then one announcing the next event over one
# that does not.
preferred_leap_seconds(current, ::Nothing) = false
preferred_leap_seconds(::Nothing, new::LeapSeconds) = true
preferred_leap_seconds(current::LeapSeconds, new::LeapSeconds) =
    leap_seconds_rank(new) > leap_seconds_rank(current)
leap_seconds_rank(leap_seconds::LeapSeconds) =
    (isempty(leap_seconds.time_system), !isnothing(leap_seconds.future_count))

end # module RINEXParserGNSSDecoderExt
