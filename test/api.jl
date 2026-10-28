# The API is what the reference's `@docs` blocks list: its bare names are the exports,
# its `RINEXParser.`-qualified ones the unexported names a caller writes qualified, and
# its `Base.`-qualified ones the methods this package adds to Base's functions.
@testset "the API reference lists the exports bare and the rest qualified" begin
    bare, qualified, extended = Symbol[], Symbol[], Symbol[]
    in_docs = false
    for line in eachline(joinpath(@__DIR__, "..", "docs", "src", "api.md"))
        line == "```@docs" && (in_docs = true; continue)
        line == "```" && (in_docs = false; continue)
        in_docs || continue
        m = match(r"^(RINEXParser\.|Base\.)?([^(\s]+)", line)
        list = m[1] == "RINEXParser." ? qualified : m[1] == "Base." ? extended : bare
        push!(list, Symbol(m[2]))
    end
    documented(name) =
        haskey(Base.Docs.meta(RINEXParser), Base.Docs.Binding(RINEXParser, name))
    exported = setdiff(names(RINEXParser), [:RINEXParser])
    @test sort(bare) == sort(exported)
    @test all(documented, bare)
    @test all(name -> isdefined(RINEXParser, name) && name ∉ exported, qualified)
    @test all(documented, qualified)
    @test all(
        name -> haskey(Base.Docs.meta(RINEXParser), Base.Docs.Binding(Base, name)),
        extended,
    )
end
