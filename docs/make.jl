using Documenter
using RINEXParser

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
    ],
    checkdocs = :exports,
)

if get(ENV, "CI", "false") == "true"
    deploydocs(; repo = "github.com/JuliaGNSS/RINEXParser.jl.git", devbranch = "main")
end
