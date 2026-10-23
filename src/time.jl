# The week counts of the navigation records, and the calendar times they
# make: what a broadcast message's week and seconds of week become in a
# RINEX 3.05 record.

const SECONDS_PER_WEEK = 604800

# The calendar origins RINEX counts weeks from: GPS and Galileo records the
# GPS week, BDS records the BDT week.
const GPS_EPOCH = DateTime(1980, 1, 6)
const BDT_EPOCH = DateTime(2006, 1, 1)

# Galileo counts its weeks from the start of GPS week 1024, and RINEX writes
# them aligned with the GPS week (Table A8).
const GALILEO_WEEK_OFFSET = 1024

# The week of a record of `system`, from the week its constellation counts,
# and the calendar origin that week counts from.
function record_week(system::Char, week::Integer)
    system == 'G' && return Int(week), GPS_EPOCH
    system == 'E' && return Int(week) + GALILEO_WEEK_OFFSET, GPS_EPOCH
    system == 'C' && return Int(week), BDT_EPOCH
    throw(
        ArgumentError(
            "The navigation record times are known for GPS ('G'), Galileo ('E') and " *
            "BDS ('C'), not for system '$system'",
        ),
    )
end

"""
    navigation_times(system; week, transmission_time, toe, toc)
        -> (; week, toc, transmission_time)

The `week`, `toc` and `transmission_time` fields of a navigation record of
`system` - `'G'`, `'E'` or `'C'` - from a broadcast message: `week` and
`transmission_time` are the continuous week and the seconds of week it was
broadcast at, and `toe` and `toc` its reference times of ephemeris and
clock in seconds of week, all on the count of the constellation's own time:
the GPS week, the Galileo (GST) week, the BDT week. Splatted into the
keywords of an ephemeris:

    GPSEphemeris(; prn, ..., navigation_times('G'; week, transmission_time, toe, toc)...)

A message is broadcast within hours of its reference times, but not always
in the same week: late on a Saturday the next week's ephemeris is often on
the air already with a `toe` near zero, and just after the rollover the last
one of the old week may still be. Each reference time is placed in the week
that puts it within half a week of the broadcast, as RTKLIB's `adjweek`
does. The record carries

  - `week`: the week of `toe` (Tables A6, A8 and A14), aligned
    with the GPS week for Galileo - the GST week plus 1024 - and the BDT
    week for BDS,
  - `toc`: the calendar time of `toc` in the week it falls in, in the time
    system of the constellation - BDT for BDS,
  - `transmission_time`: the seconds of the record's own week, so a message
    broadcast in the week before reads negative and one broadcast in the
    week after reads past the end of the week.
"""
function navigation_times(
    system::Char;
    week::Integer,
    transmission_time::Real,
    toe::Real,
    toc::Real,
)
    broadcast_week, origin = record_week(system, week)
    toe_week = reference_week(broadcast_week, transmission_time, toe)
    toc_week = reference_week(broadcast_week, transmission_time, toc)
    (;
        week = toe_week,
        toc = origin + Week(toc_week) + Millisecond(round(Int, toc * 1000)),
        transmission_time = Float64(
            transmission_time + (broadcast_week - toe_week) * SECONDS_PER_WEEK,
        ),
    )
end

# The week a reference time of week falls in, from the week and seconds of
# week it was broadcast at.
reference_week(week, transmission_time, reference_time) =
    week + round(Int, (transmission_time - reference_time) / SECONDS_PER_WEEK)

"""
    ionosphere_time_mark(seconds) -> Char

The time mark of an [`IonosphericCorrection`](@ref): the hour of the day of
its transmission time as a letter, `'A'` for 00h-01h through `'X'` for
23h-24h. `seconds` is the transmission time in seconds of the week or of the
day, in the time system of the message - a week starts at midnight, so both
give the same hour.
"""
ionosphere_time_mark(seconds::Real) = 'A' + (mod(floor(Int, seconds), 86400) ÷ 3600)
