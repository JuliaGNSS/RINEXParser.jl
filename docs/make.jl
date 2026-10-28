using Documenter
using RINEXParser

# The API is what the reference's `@docs` blocks list: an export bare, any other name
# qualified, `RINEXParser.name`, and a method of a Base function by its signature,
# `Base.name(…)`. The internals page documents everything else.
function listed_objects(page)
    objects = Any[]
    in_docs = false
    for line in eachline(joinpath(@__DIR__, "src", page))
        line == "```@docs" && (in_docs = true; continue)
        line == "```" && (in_docs = false; continue)
        in_docs || continue
        m = match(r"^(RINEXParser\.|Base\.)?([^(\s]+)", line)
        push!(objects, getfield(m[1] == "Base." ? Base : RINEXParser, Symbol(m[2])))
    end
    objects
end

const LISTED = listed_objects("api.md")
listed(x) = any(y -> y === x, LISTED)

makedocs(;
    sitename = "RINEXParser.jl",
    modules = [RINEXParser],
    authors = "JuliaGNSS",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://JuliaGNSS.github.io/RINEXParser.jl",
    ),
    pages = [
        "Home" => "index.md",
        "Ephemeris interface" => "ephemeris_interface.md",
        "API reference" => "api.md",
        "Internals" => "internals.md",
    ],
    checkdocs = :exports,
)

if get(ENV, "CI", "false") == "true"
    deploydocs(; repo = "github.com/JuliaGNSS/RINEXParser.jl.git", devbranch = "main")
end
