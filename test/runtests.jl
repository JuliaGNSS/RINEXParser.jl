using Test
using Dates
using Printf
using RINEXParser
using Aqua

include("helpers.jl")

@testset "RINEXParser" begin
    @testset "Aqua" begin
        Aqua.test_all(RINEXParser)
    end
    include("format.jl")
    include("obs.jl")
    include("nav.jl")
    include("filename.jl")
end
