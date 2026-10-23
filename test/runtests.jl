using Test
using Dates
using Printf
using RINEXParser
using Aqua
using GNSSDecoder
using GNSSSignals
using InteractiveUtils: subtypes

include("helpers.jl")

@testset "RINEXParser" begin
    @testset "Aqua" begin
        Aqua.test_all(RINEXParser)
    end
    include("format.jl")
    include("obs.jl")
    include("nav.jl")
    include("filename.jl")
    include("writers.jl")
    include("time.jl")
    include("extensions.jl")
end
