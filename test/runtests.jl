using Test
using Dates
using Printf
using RINEXParser
using Aqua
using GNSSSignals
# GNSSDecoder cannot be loaded on Windows: its Aff3ct dependency has no
# Windows binary, as aff3ct_jll is not built there. Its extension is tested
# on the other platforms only.
@static if !Sys.iswindows()
    using GNSSDecoder
end
using InteractiveUtils: subtypes

include("helpers.jl")

@testset "RINEXParser" begin
    @testset "Aqua" begin
        Aqua.test_all(RINEXParser)
    end
    include("api.jl")
    include("format.jl")
    include("obs.jl")
    include("nav.jl")
    include("filename.jl")
    include("writers.jl")
    include("time.jl")
    Sys.iswindows() || include("gnssdecoder.jl")
    include("gnsssignals.jl")
end
