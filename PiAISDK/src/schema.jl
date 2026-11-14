const LOG_TAG = "ai_schema"

function _json_type_matches(x, t)
    t == "null" && return x === nothing
    t == "boolean" && return x isa Bool
    t == "string" && return x isa AbstractString
    t == "number" && return x isa Number && !(x isa Bool)
    t == "integer" && return x isa Integer && !(x isa Bool)
    t == "object" && return x isa AbstractDict
    t == "array" && return x isa AbstractVector
    return true
end

function _schema_error(tool_name, path, reason)
    throw(ArgumentError("Invalid arguments for tool $(tool_name): $(path): $(reason)"))
end

function _validate_type(tool_name, schema, x, path)
    t = get(schema, "type", nothing)
    t === nothing && return
    types = t isa AbstractVector ? String[string(v) for v in t] : [String(t)]
    any(_json_type_matches(x, ty) for ty in types) ||
        _schema_error(tool_name, path, "expected type $(join(types, " | ")), got $(typeof(x))")
end

"""
    validate_arguments(tool_name, schema, args) -> Dict{String,Any}

Validate decoded tool-call `args` against the JSON Schema `schema` supported
by this package (`type`, `const`, `enum`, `anyOf`/`oneOf`/`allOf`, string and
number ranges, object properties, and array items) and return them as a plain
`Dict{String,Any}`.

# Throws
- `ArgumentError`: `args` is not an object or violates `schema`; the message
  names `tool_name` and the failing JSON path.
"""
function validate_arguments(tool_name::AbstractString, schema::Dict{String,Any}, args)
    args isa AbstractDict || _schema_error(tool_name, "\$", "arguments must be an object")
    _validate_schema(tool_name, schema, args, "\$")
    return Dict{String,Any}(String(k) => plain(v) for (k, v) in args)
end
validate_arguments(tool_name::AbstractString, schema, args) =
    validate_arguments(tool_name, Dict{String,Any}(String(k) => plain(v) for (k, v) in schema), args)

function _validate_schema(tool_name, schema, x, path)
    schema isa AbstractDict || return
    haskey(schema, "anyOf") && begin
        ok = false
        for sub in schema["anyOf"]
            try
                _validate_schema(tool_name, sub, x, path)
                ok = true
                break
            catch err
                err isa ArgumentError || rethrow()
            end
        end
        ok || _schema_error(tool_name, path, "does not match anyOf")
    end
    haskey(schema, "oneOf") && begin
        matches = 0
        for sub in schema["oneOf"]
            try
                _validate_schema(tool_name, sub, x, path)
                matches += 1
            catch err
                err isa ArgumentError || rethrow()
            end
        end
        matches == 1 || _schema_error(tool_name, path, "must match exactly one oneOf schema")
    end
    haskey(schema, "allOf") && begin
        for sub in schema["allOf"]
            _validate_schema(tool_name, sub, x, path)
        end
    end
    haskey(schema, "const") && !isequal(x, schema["const"]) &&
        _schema_error(tool_name, path, "must equal $(schema["const"])")
    if haskey(schema, "enum")
        any(isequal(x, v) for v in schema["enum"]) ||
            _schema_error(tool_name, path, "must be one of $(schema["enum"])")
    end
    _validate_type(tool_name, schema, x, path)
    if x isa AbstractString
        haskey(schema, "minLength") && length(x) < schema["minLength"] &&
            _schema_error(tool_name, path, "length must be >= $(schema["minLength"])")
        haskey(schema, "maxLength") && length(x) > schema["maxLength"] &&
            _schema_error(tool_name, path, "length must be <= $(schema["maxLength"])")
        if haskey(schema, "pattern")
            occursin(Regex(String(schema["pattern"])), x) ||
                _schema_error(tool_name, path, "does not match pattern $(schema["pattern"])")
        end
    elseif x isa Number && !(x isa Bool)
        haskey(schema, "minimum") && x < schema["minimum"] &&
            _schema_error(tool_name, path, "must be >= $(schema["minimum"])")
        haskey(schema, "maximum") && x > schema["maximum"] &&
            _schema_error(tool_name, path, "must be <= $(schema["maximum"])")
    elseif x isa AbstractDict
        props = get(schema, "properties", Dict{String,Any}())
        for req in get(schema, "required", String[])
            haskey(x, req) || _schema_error(tool_name, "$(path).$(req)", "is required")
        end
        additional = get(schema, "additionalProperties", true)
        for (k, v) in x
            key = String(k)
            if haskey(props, key)
                _validate_schema(tool_name, props[key], v, "$(path).$(key)")
            elseif additional === false
                _schema_error(tool_name, "$(path).$(key)", "additional property is not allowed")
            elseif additional isa AbstractDict
                _validate_schema(tool_name, additional, v, "$(path).$(key)")
            end
        end
    elseif x isa AbstractVector
        haskey(schema, "minItems") && length(x) < schema["minItems"] &&
            _schema_error(tool_name, path, "must contain at least $(schema["minItems"]) items")
        haskey(schema, "maxItems") && length(x) > schema["maxItems"] &&
            _schema_error(tool_name, path, "must contain at most $(schema["maxItems"]) items")
        if haskey(schema, "items")
            for (i, v) in enumerate(x)
                _validate_schema(tool_name, schema["items"], v, "$(path)[$(i-1)]")
            end
        end
    end
    return nothing
end
