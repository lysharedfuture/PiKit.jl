@testset "schema validation" begin
    schema = Dict{String,Any}(
        "type" => "object",
        "properties" => Dict{String,Any}(
            "path" => Dict{String,Any}("type" => "string", "minLength" => 1),
            "n" => Dict{String,Any}("type" => "integer", "minimum" => 1),
            "kind" => Dict{String,Any}("enum" => ["a", "b"]),
            "any" => Dict{String,Any}("anyOf" => Any[Dict("type" => "string"), Dict("type" => "number")]),
        ),
        "required" => ["path"],
        "additionalProperties" => false,
    )
    @test AI.validate_arguments("t", schema, Dict{String,Any}("path" => "x", "n" => 2))["path"] == "x"
    @test_throws ArgumentError AI.validate_arguments("t", schema, Dict{String,Any}("path" => "x", "kind" => "c"))
    @test_throws ArgumentError AI.validate_arguments("t", schema, Dict{String,Any}("path" => "x", "n" => 0))
    @test_throws ArgumentError AI.validate_arguments("t", schema, Dict{String,Any}("path" => ""))
    @test_throws ArgumentError AI.validate_arguments("t", schema, Dict{String,Any}("path" => "x", "extra" => 1))
    @test_throws ArgumentError AI.validate_arguments("t", schema, Dict{String,Any}("path" => "x", "any" => true))
    err = try
        AI.validate_arguments("mytool", Dict{String,Any}("type" => "object", "required" => ["p"]), Dict{String,Any}())
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("mytool", err.msg) && occursin(".p", err.msg)
end
