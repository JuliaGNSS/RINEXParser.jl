# Changelog

# [4.1.0](https://github.com/JuliaGNSS/RINEXParser.jl/compare/v4.0.0...v4.1.0) (2026-10-23)


### Bug Fixes

* **nav:** check every system of nav_satellite_system, also for a mixed file ([caf276e](https://github.com/JuliaGNSS/RINEXParser.jl/commit/caf276e05cc5c3435696b438ba73e687a31233a1))


### Features

* build obs_codes from signals, the nav satellite system from systems, and epochs from a GNSSSignals time system ([cf8d9e2](https://github.com/JuliaGNSS/RINEXParser.jl/commit/cf8d9e2f672623aab8999bc48175a3f6d0dcc52e))
* complete a header field by field with set_header!(writer; fields...) ([2e55075](https://github.com/JuliaGNSS/RINEXParser.jl/commit/2e55075107e2d98ef11f1c82ed38280d77d5542f))
* convert decoded messages and signals through package extensions ([69607a0](https://github.com/JuliaGNSS/RINEXParser.jl/commit/69607a07d1f75c650dcdef92b60959f920e1cec7))
* export time_system, navigation_times and ionosphere_time_mark ([74eee9e](https://github.com/JuliaGNSS/RINEXParser.jl/commit/74eee9e5f616e445c382f1ece181a7c41cd3a2fd))
* **filename:** take a site field given as nothing from the marker name ([5726854](https://github.com/JuliaGNSS/RINEXParser.jl/commit/572685432b5a9dd84c9ba5f1a10630335fd1ffda))
* name files on close, replace headers through the writer, blank overflowing values ([b2c3aef](https://github.com/JuliaGNSS/RINEXParser.jl/commit/b2c3aefd8b3c9cc49cf4cce6f2e1ece9add396cf))
* name the epoch time, the GNSSSignals time system and the messages with a record ([3c210f3](https://github.com/JuliaGNSS/RINEXParser.jl/commit/3c210f3bf55ee00429e74e78009e96f684492a31))
* **nav:** leave out an ephemeris that does not fit with overflow = :skip ([71fb1bc](https://github.com/JuliaGNSS/RINEXParser.jl/commit/71fb1bc4aed9a3cc27b8fe67d9d9e24a2b92f5b2))

# [4.0.0](https://github.com/JuliaGNSS/RINEXParser.jl/compare/v3.0.0...v4.0.0) (2026-10-22)


* feat(obs)!: hold the carrier phases to the reference signals of Table A23 ([164fb60](https://github.com/JuliaGNSS/RINEXParser.jl/commit/164fb6049ad8cace5f5b5e461f659c58cbce4030))


### BREAKING CHANGES

* A header whose obs_codes carry a carrier phase that
Table A23 gives a correction other than "None" - GPS L2S or L5Q,
Galileo L1C, BDS L1P, ... - is rejected unless phase_shifts names it.
State the correction that aligned it, `phase_correction(system, code)`
for the ICD value, or 0.0 for data that arrived aligned. This includes
the codes the table only requires aligned (Galileo L1X, GPS L5X, the
BDS-3 pilots, ...) or whose correction depends on the satellite (GPS
L2C), for which `phase_correction` returns `nothing`; state the
correction the receiver or converter applied. A shift limited to some
satellites names its code, the others reading as having had nothing
applied, as section 5.2.12 lists the satellites a correction affects.
Codes the table states no alignment for (SBAS, the restricted signals)
are not checked. `PhaseShift` rejects a nonzero correction for a
reference signal, such as GPS L1C or Galileo L1B.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

# [3.0.0](https://github.com/JuliaGNSS/RINEXParser.jl/compare/v2.0.2...v3.0.0) (2026-10-22)


* feat(obs)!: accept only the observation codes RINEX 3.05 defines ([a781b64](https://github.com/JuliaGNSS/RINEXParser.jl/commit/a781b64773bb917bccef203b3579606c9dc2de99))
* feat(obs)!: write the GLONASS frequency channels and code-phase biases ([efe2c36](https://github.com/JuliaGNSS/RINEXParser.jl/commit/efe2c366690e50f79d7989dff62f2fdf5f685dfe))
* fix(filename)!: read an unspecified field only as 00U ([73fa2bb](https://github.com/JuliaGNSS/RINEXParser.jl/commit/73fa2bb05c0178137f307c703cb11a78a8b8beea))
* fix(nav)!: accept only the ionospheric correction types of Table A5 ([03bebbf](https://github.com/JuliaGNSS/RINEXParser.jl/commit/03bebbf5567113eca225ab402286ffbb14f1e8e7))
* fix(nav)!: derive the Galileo clock bits from the message source ([83fb72b](https://github.com/JuliaGNSS/RINEXParser.jl/commit/83fb72b9fcf1f8311ac75a7e2d12064405bac6f3))
* fix(nav)!: reject a toc with milliseconds ([efe4392](https://github.com/JuliaGNSS/RINEXParser.jl/commit/efe439267e5fae22de92fa3ccfd2a0867f32912f))
* fix(obs)!: declare each system and each observation code once ([e349974](https://github.com/JuliaGNSS/RINEXParser.jl/commit/e3499745a19b3efbe6977bee3267be72df64af8b))
* fix(obs)!: keep the loss-of-lock indicator to the carrier phase ([58d7bd8](https://github.com/JuliaGNSS/RINEXParser.jl/commit/58d7bd8264c64790a2eb320f19d21de485b1cd08))
* fix(obs)!: keep the seconds of an epoch below 60 ([3f735bc](https://github.com/JuliaGNSS/RINEXParser.jl/commit/3f735bc2a889eb406022a54e798f7c476bc45f2f))
* fix(obs)!: require RCV CLOCK OFFS APPL for a reported clock offset ([c8ebe41](https://github.com/JuliaGNSS/RINEXParser.jl/commit/c8ebe4106b3c98c058fbd338b937de0bbe17e565))
* refactor!: name the API after the terms of RINEX 3.05 ([678b6a8](https://github.com/JuliaGNSS/RINEXParser.jl/commit/678b6a8690bee0d868c21510d2bf3183951bf1a3))


### Bug Fixes

* **filename:** take the data source as a string, and name the missing start time ([4fc9e67](https://github.com/JuliaGNSS/RINEXParser.jl/commit/4fc9e674e687312e012eacafe925fea711b96af4))
* **nav:** write a new record when the contents change under the same issue of data ([330771f](https://github.com/JuliaGNSS/RINEXParser.jl/commit/330771fe2a2f5bab242a3cdb3b48d5701454ce56))


### Features

* **obs:** name the indicator bits and add the clock and signal-strength records ([12e653c](https://github.com/JuliaGNSS/RINEXParser.jl/commit/12e653ca3adb2ed5ac7d55c924bef51eeb58feef))


### BREAKING CHANGES

* Rename `RinexObsHeader(; obs_types)` to `obs_codes`,
`RinexFileName`'s `kind` (field and keyword) to `file_type`, and the
ephemeris extension method `RINEXParser.system` to
`RINEXParser.satellite_system`. The integer ephemeris fields listed above
and the results of `galileo_data_sources` and `galileo_sv_health` are
`Int`; a whole-number float still converts on construction, a fraction
throws an `InexactError`. The RINEX VERSION / TYPE record writes
`M: Mixed` and `E: Galileo` instead of `M: MIXED` and `E: GALILEO`.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
* `parse(RinexFileName, name)` rejects a non-zero count with
the unit `U`, and `tryparse` returns `nothing` for it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
* `write_ephemeris!` rejects an ephemeris whose `toc` has
milliseconds with an `ArgumentError`.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
* An `IonosphericCorrection` type outside Table A5, a GAL
correction with a non-zero fourth value, and a non-GAL one without four
values are rejected with an `ArgumentError`.
`IonosphericCorrection("GAL", ...).parameters` is a 3-tuple.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
* `galileo_data_sources` no longer takes `clock_e5a_e1` or
`clock_e5b_e1`; drop them, the bit follows from `fnav_e5a` or from
`inav_e1b`/`inav_e5b`. A source mixing `fnav_e5a` with `inav_e1b` or
`inav_e5b` is rejected with an `ArgumentError`.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
* An epoch with observations of a GLONASS satellite whose
slot is not in the header's `glonass_slots` is rejected with an
`ArgumentError`.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
* An epoch with a `clock_offset` is rejected while
`clock_offset_applied` is `nothing`; set it to `false` (or `true`) to keep
writing offsets.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
* A header listing a system twice in `obs_types`, or a code
twice in one system's list, is rejected with an `ArgumentError` when the
writer is created.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
* An `ObsEpoch` with `abs(fractional_second) >= 0.001` is
rejected with an `ArgumentError`; the fraction carries only what lies
below the milliseconds of the `DateTime`.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
* An epoch giving a non-zero `lli` to an observation other
than a carrier phase is rejected by `write_epoch!`; set the indicator on
the `L` observation only.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
* A header declaring an observation code RINEX 3.05 does
not define for its constellation - such as `C1I` or `C1C` for BDS, `C1N`
for GPS, or a lowercase or incomplete descriptor - is now rejected with an
`ArgumentError` when the writer is created, and a `PhaseShift` naming one
when it is constructed. Use the code of Tables 14-20 for the signal, for
BDS B1I `C2I`/`L2I`/`D2I`/`S2I`.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

## [2.0.2](https://github.com/JuliaGNSS/RINEXParser.jl/compare/v2.0.1...v2.0.2) (2026-09-30)

No changes to the package. Replaces the accidental 3.0.0 release.

## [2.0.1](https://github.com/JuliaGNSS/RINEXParser.jl/compare/v2.0.0...v2.0.1) (2026-09-11)


### Bug Fixes

* attach the `PhaseShift` docstring to its own type ([78babce](https://github.com/JuliaGNSS/RINEXParser.jl/commit/78babce7a54dde9618a8725cf31d6a89281f6180))


# [2.0.0](https://github.com/JuliaGNSS/RINEXParser.jl/compare/v1.1.0...v2.0.0) (2026-09-10)


* feat!: act on the RINEX 3.05 conformance review ([9e24bc8](https://github.com/JuliaGNSS/RINEXParser.jl/commit/9e24bc8dd3bf1444eee11869f8e8c17516dfb180))


### BREAKING CHANGES

* `header.leap_seconds` reads back as a `LeapSeconds` rather
than as the `Int` or `NTuple{4,Int}` it was assigned; both still convert on
assignment, so headers are written the same way. Input the format cannot
represent is now rejected where it used to be written: an epoch flag of
2-6, a loss-of-lock indicator of 8 or 9, a navigation value needing a
three-digit exponent, a header field wider than its columns, all three
Galileo message sources at once, and an observation file name that leaves
out its data-frequency field.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>

# [1.1.0](https://github.com/JuliaGNSS/RINEXParser.jl/compare/v1.0.0...v1.1.0) (2026-09-10)


### Bug Fixes

* follow the RINEX 3.05 spec for spare fields and table numbers ([729b637](https://github.com/JuliaGNSS/RINEXParser.jl/commit/729b637e193c77c47f5c74dc7ad3c263852663c5))


### Features

* add BeiDou ephemeris support ([bc9392a](https://github.com/JuliaGNSS/RINEXParser.jl/commit/bc9392aafd65bac9b348d074a3383cf78f2f6a69))

# [1.0.0](https://github.com/JuliaGNSS/RINEXParser.jl/compare/v0.4.0...v1.0.0) (2026-08-04)

Same as v0.4.0. No breaking changes.

This release only declares the public API stable, so that from now on version
numbers follow semantic versioning against a 1.x baseline.

# [0.4.0](https://github.com/JuliaGNSS/RINEXParser.jl/compare/v0.3.0...v0.4.0) (2026-08-04)


### Features

* build and parse the RINEX long filenames ([d904008](https://github.com/JuliaGNSS/RINEXParser.jl/commit/d90400827850ba76e968bc95d7be1352648493e4))

# [0.3.0](https://github.com/JuliaGNSS/RINEXParser.jl/compare/v0.2.1...v0.3.0) (2026-08-03)


### Features

* address observations by code and guard the fixed-column writers ([6acf6ad](https://github.com/JuliaGNSS/RINEXParser.jl/commit/6acf6addef50d8c6ec9dc7be4f795c5dd5d6e08e))

## [0.2.1](https://github.com/JuliaGNSS/RINEXParser.jl/compare/v0.2.0...v0.2.1) (2026-08-03)


### Bug Fixes

* write Galileo F/NAV and I/NAV as separate records ([274d03b](https://github.com/JuliaGNSS/RINEXParser.jl/commit/274d03bca3ede77ef5e2a07ef0a51bdc860b56da)), closes [#143](https://github.com/JuliaGNSS/RINEXParser.jl/issues/143)

# [0.2.0](https://github.com/JuliaGNSS/RINEXParser.jl/compare/v0.1.0...v0.2.0) (2026-08-03)

### Features

  - add Galileo ephemeris support and mixed navigation files ([0c00209](https://github.com/JuliaGNSS/RINEXParser.jl/commit/0c002094556e9cc62447e29637f028f370408380))
