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
    get_broadcast_time_of_week,
    get_broadcast_week,
    get_ggto_parameters,
    get_klobuchar_parameters,
    get_leap_second_parameters,
    get_nequick_g_parameters,
    get_range_accuracy,
    get_signal_type,
    get_utc_parameters,
    is_decoding_completed_for_positioning
using GNSSSignals: GalileoE5bI
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

# The messages of each constellation, and those of them RINEX 3.05 has an
# ephemeris record for.
const GPSMessage = GNSSDecoder.AbstractGPSData
const GalileoMessage = GNSSDecoder.AbstractGalileoData
const BeiDouMessage = GNSSDecoder.AbstractBeiDouData
const GPSData = GNSSDecoder.GPSL1CAData
const GalileoData = Union{GNSSDecoder.GalileoINAVData,GNSSDecoder.GalileoE5aData}
const BeiDouData = GNSSDecoder.BeiDouDNAVData

satellite_system(::GPSMessage) = 'G'
satellite_system(::GalileoMessage) = 'E'
satellite_system(::BeiDouMessage) = 'C'

# Messages RINEX 3.05 has a record for, and every other one.
has_rinex_ephemeris(::GNSSDecoderState) = false
has_rinex_ephemeris(::GNSSDecoderState{<:Union{GPSData,GalileoData,BeiDouData}}) = true

rinex_ephemeris(::GNSSDecoderState; approximate_year::Integer) = nothing

# The week, transmission time and reference times of a record, or `nothing`
# before the message has dated itself with a week.
function record_times(decoder, approximate_year)
    week = get_broadcast_week(decoder; approximate_year)
    isnothing(week) && return nothing
    data = decoder.data
    navigation_times(
        satellite_system(data);
        week,
        transmission_time = get_broadcast_time_of_week(decoder),
        toe = data.t_0e,
        toc = data.t_0c,
    )
end

function rinex_ephemeris(decoder::GNSSDecoderState{<:GPSData}; approximate_year::Integer)
    is_decoding_completed_for_positioning(decoder) || return nothing
    times = record_times(decoder, approximate_year)
    isnothing(times) && return nothing
    data = decoder.data
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
        sv_accuracy = accuracy_metres(decoder, USE_AT_OWN_RISK),
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

# The broadcast range accuracy in metres, GNSSDecoder's nominal value of the
# index, with GPS's roundings to 2.8, 5.7 and 11.3 m, which RINEX asks for too.
# Where the satellite predicts none, GNSSDecoder reports `Inf` and RINEX a
# value of its own: for GPS and BDS 8192 m, "use at own risk", the 2^(N-2) of
# index 15 (Tables A6 and A14); for Galileo -1, "NAPA / unknown" (Table A8).
const USE_AT_OWN_RISK = 8192.0
const NO_ACCURACY_PREDICTION = -1.0
function accuracy_metres(decoder, no_prediction)
    accuracy = get_range_accuracy(decoder)
    isnothing(accuracy) || isinf(accuracy) ? no_prediction : accuracy
end

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
# record was decoded from is told apart by the decoder's signal. The source
# keys a record's identity, so the I/NAV and F/NAV messages of one satellite
# stay the separate records RINEX requires.
galileo_sources(decoder::GNSSDecoderState{<:GNSSDecoder.GalileoINAVData}) =
    get_signal_type(decoder) <: GalileoE5bI ? galileo_data_sources(; inav_e5b = true) :
    galileo_data_sources(; inav_e1b = true)
galileo_sources(::GNSSDecoderState{<:GNSSDecoder.GalileoE5aData}) =
    galileo_data_sources(; fnav_e5a = true)

# I/NAV broadcasts the group delay of both Galileo band pairs, F/NAV only the
# E5a/E1 one; RINEX leaves the term a message does not carry at zero.
galileo_bgd_e5b_e1(data::GNSSDecoder.GalileoINAVData) = data.BGD_E1_E5b
galileo_bgd_e5b_e1(::GNSSDecoder.GalileoE5aData) = 0.0

function rinex_ephemeris(
    decoder::GNSSDecoderState{<:GalileoData};
    approximate_year::Integer,
)
    is_decoding_completed_for_positioning(decoder) || return nothing
    times = record_times(decoder, approximate_year)
    isnothing(times) && return nothing
    data = decoder.data
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
        # The SISA of the band pair the message states its clock for: E1-E5b
        # on I/NAV, E1-E5a on F/NAV.
        sisa = accuracy_metres(decoder, NO_ACCURACY_PREDICTION),
        sv_health = galileo_health(data),
        bgd_e5a_e1 = data.BGD_E1_E5a,
        bgd_e5b_e1 = galileo_bgd_e5b_e1(data),
        transmission_time = times.transmission_time,
    )
end

function rinex_ephemeris(decoder::GNSSDecoderState{<:BeiDouData}; approximate_year::Integer)
    is_decoding_completed_for_positioning(decoder) || return nothing
    # Every time of a BDS record is BDT: seconds of the BDT week, and the
    # calendar epoch they make with the week is BDT's too.
    times = record_times(decoder, approximate_year)
    isnothing(times) && return nothing
    data = decoder.data
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
        sv_accuracy = accuracy_metres(decoder, USE_AT_OWN_RISK),
        sath1 = data.SatH1,
        tgd1_b1_b3 = data.T_GD1,
        tgd2_b2_b3 = data.T_GD2,
        transmission_time = times.transmission_time,
        aodc = data.AODC,
    )
end

# ─────────────────────────────────────────────────────────────────────────
# Navigation-file header

# Every GPS, Galileo and BDS message carries header records, whether RINEX
# 3.05 has a record for its ephemeris or not: the records are the same
# whichever message broadcast them.
add_header_records!(header::RinexNavHeader, ::GNSSDecoderState; approximate_year::Integer) =
    header

function add_header_records!(
    header::RinexNavHeader,
    decoder::GNSSDecoderState{<:Union{GPSMessage,GalileoMessage,BeiDouMessage}};
    approximate_year::Integer,
)
    for correction in ionospheric_corrections(decoder)
        replace_record!(header.ionospheric_corrections, correction, ionospheric_key)
    end
    for correction in time_system_corrections(decoder, approximate_year)
        replace_record!(header.time_system_corrections, correction, c -> c.type)
    end
    leap_seconds = broadcast_leap_seconds(decoder, approximate_year)
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

# Klobuchar (GPS, BDS D1/D2) and NeQuick-G (Galileo) coefficients the satellite
# has broadcast, as GNSSDecoder reads them: a whole set or none. RINEX 3.05 has
# no record for the BDGIM coefficients of the BDS B-CNAV messages.
function klobuchar_corrections(decoder, alpha, beta; kwargs...)
    parameters = get_klobuchar_parameters(decoder)
    isnothing(parameters) && return IonosphericCorrection[]
    (; α_0, α_1, α_2, α_3, β_0, β_1, β_2, β_3) = parameters
    [
        IonosphericCorrection(alpha, (α_0, α_1, α_2, α_3); kwargs...),
        IonosphericCorrection(beta, (β_0, β_1, β_2, β_3); kwargs...),
    ]
end
ionospheric_corrections(decoder::GNSSDecoderState{<:GPSMessage}) =
    klobuchar_corrections(decoder, "GPSA", "GPSB")
function ionospheric_corrections(decoder::GNSSDecoderState{<:BeiDouMessage})
    # RINEX 3.05 Table A5 makes the time mark and the satellite mandatory for
    # BDS. Both describe the transmission, so a message that has not reported
    # its second of week yet cannot carry them.
    time_of_week = get_broadcast_time_of_week(decoder)
    isnothing(time_of_week) && return IonosphericCorrection[]
    klobuchar_corrections(
        decoder,
        "BDSA",
        "BDSB";
        time_mark = ionosphere_time_mark(time_of_week),
        sv_id = decoder.prn,
    )
end
function ionospheric_corrections(decoder::GNSSDecoderState{<:GalileoMessage})
    parameters = get_nequick_g_parameters(decoder)
    isnothing(parameters) && return IonosphericCorrection[]
    [IonosphericCorrection("GAL", (parameters.a_i0, parameters.a_i1, parameters.a_i2))]
end

# GNSSDecoder resolves every truncated reference week onto the continuous week
# of the message's own count; a header record counts Galileo's aligned with the
# GPS week.
header_week(decoder, week) =
    first(RINEXParser.record_week(satellite_system(decoder.data), week))

utc_correction_type(::GPSMessage) = "GPUT"
utc_correction_type(::GalileoMessage) = "GAUT"
utc_correction_type(::BeiDouMessage) = "BDUT"

# The system's offset from UTC, and Galileo's from GPS time. RINEX 3.05 records
# the linear polynomial only, so the A_2 of the CNAV-family messages, a drift
# rate of at most 2^-53 s/s², is left out.
function time_system_corrections(decoder, approximate_year)
    corrections = TimeSystemCorrection[]
    utc = get_utc_parameters(decoder; approximate_year)
    if !isnothing(utc)
        # BDS D1/D2 broadcasts no reference epoch for its UTC offset, so the
        # record's reference time is zero of the current BDT week.
        reference_time, reference_week = if isnothing(utc.WN_0t)
            0, something(get_broadcast_week(decoder; approximate_year))
        else
            something(utc.t_0t), utc.WN_0t
        end
        push!(
            corrections,
            TimeSystemCorrection(
                utc_correction_type(decoder.data),
                utc.A_0,
                utc.A_1,
                reference_time,
                header_week(decoder, reference_week),
            ),
        )
    end
    ggto = get_ggto_parameters(decoder)
    isnothing(ggto) || push!(
        corrections,
        TimeSystemCorrection(
            "GPGA",
            ggto.A_0G,
            ggto.A_1G,
            ggto.t_0G,
            header_week(decoder, ggto.WN_0G),
        ),
    )
    corrections
end

# The broadcast leap seconds: the current count, the count after the next
# event, and the week and day it falls on. GPS and Galileo count them alike,
# as a blank time system is read. BDS counts BDT - UTC, 14 s fewer, and its
# week and day from the BDT epoch, so its record names `"BDT"`.
function broadcast_leap_seconds(decoder, approximate_year)
    parameters = get_leap_second_parameters(decoder; approximate_year)
    isnothing(parameters) && return nothing
    LeapSeconds(
        parameters.Δt_LS;
        future_count = parameters.Δt_LSF,
        week = header_week(decoder, parameters.WN_LSF),
        day = parameters.DN,
        time_system = decoder.data isa BeiDouMessage ? "BDT" : "",
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
