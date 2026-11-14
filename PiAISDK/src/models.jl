const LOG_TAG = "ai_models"

const _MODELS_CACHE = Ref{Union{Nothing,Vector{Model}}}(nothing)
const _DEFAULT_MODEL_WARNED = Ref(false)

function _cost_from_json(d)
    d === nothing && return ModelCost(0, 0, 0, 0)
    tiers = Dict{String,Any}[Dict{String,Any}(String(k) => plain(v) for (k, v) in t) for t in get(d, "tiers", [])]
    return ModelCost(Float64(get(d, "input", 0.0)), Float64(get(d, "output", 0.0)),
                     Float64(get(d, "cacheRead", 0.0)), Float64(get(d, "cacheWrite", 0.0)), tiers)
end

function _model_from_json(provider, provider_conf, id, d)
    tlm = get(d, "thinkingLevelMap", Dict{String,Any}())
    return Model(
        String(id),
        String(get(d, "name", id)),
        String(get(d, "api", get(provider_conf, "api", ""))),
        String(provider),
        String(get(d, "baseUrl", get(provider_conf, "baseUrl", ""))),
        Bool(get(d, "reasoning", false)),
        String[String(x) for x in get(d, "input", ["text"])],
        Int(get(d, "contextWindow", 128_000)),
        Int(get(d, "maxTokens", 16_384)),
        _cost_from_json(get(d, "cost", nothing)),
        Dict{String,Union{String,Nothing}}(String(k) => (v === nothing ? nothing : String(v)) for (k, v) in tlm),
        Dict{String,Any}(String(k) => plain(v) for (k, v) in get(d, "compat", get(provider_conf, "compat", Dict{String,Any}()))),
    )
end

function _load_catalog(path)
    isfile(path) || return Model[]
    raw = json_parse(read(path, String))
    models = Model[]
    providers = get(raw, "providers", raw)
    for (provider, conf) in providers
        conf isa AbstractDict || continue
        for (id, d) in get(conf, "models", Dict{String,Any}())
            d isa AbstractDict || continue
            push!(models, _model_from_json(provider, conf, id, d))
        end
    end
    return models
end

"""
    load_models() -> Vector{Model}

Return the bundled model catalog from `src/models.json`, parsed once and
cached; the returned vector is a copy.
"""
function load_models()
    _MODELS_CACHE[] !== nothing && return copy(_MODELS_CACHE[])
    path = joinpath(@__DIR__, "models.json")
    models = _load_catalog(path)
    _MODELS_CACHE[] = models
    return copy(models)
end

"""
    load_user_models(agent_dir=homedir()) -> Vector{Model}

Load the user model catalog from the first existing `models.json` under
`agent_dir`, its parent, or `~/.pikit`. Returns an empty vector when none
exists.
"""
function load_user_models(agent_dir=homedir())
    candidates = [joinpath(agent_dir, "models.json"),
                  joinpath(dirname(agent_dir), "models.json"),
                  joinpath(homedir(), ".pikit", "models.json")]
    for path in unique(candidates)
        isfile(path) || continue
        return _load_catalog(path)
    end
    return Model[]
end

"""
    all_models(agent_dir=homedir()) -> Vector{Model}

Return the bundled catalog merged with the user catalog loaded from
`agent_dir`; a user model with the same `(provider, id)` replaces the bundled
one.
"""
function all_models(agent_dir=homedir())
    base = load_models()
    user = load_user_models(agent_dir)
    merged = Dict{Tuple{String,String},Model}()
    for m in base
        merged[(m.provider, m.id)] = m
    end
    for m in user
        merged[(m.provider, m.id)] = m
    end
    return collect(values(merged))
end

function _default_model(provider, id)
    if !_DEFAULT_MODEL_WARNED[]
        _DEFAULT_MODEL_WARNED[] = true
        println(stderr, "Warning: model $(provider)/$(id) is not in the catalog; using default capabilities.")
    end
    api = provider == "anthropic" ? "anthropic-messages" : "openai-completions"
    base = provider == "anthropic" ? "https://api.anthropic.com" :
           provider == "openai" ? "https://api.openai.com/v1" :
           provider == "deepseek" ? "https://api.deepseek.com/v1" : ""
    return Model(id, id, api, provider, base; context_window=128_000, max_tokens=16_384)
end

"""
    find_model(pattern; provider=nothing, models=nothing) -> Union{Model,Nothing}

Look up a model by exact `"provider/id"` or by a case-insensitive id fragment.
With `provider` given, only that provider is searched. A `"provider/id"` miss
returns a default-capability `Model` for that provider; a bare-id miss returns
`nothing`. `models` overrides the catalog used for the search.
"""
function find_model(pattern::AbstractString; provider=nothing, models=nothing)
    catalog = models === nothing ? all_models() : models
    pat = String(pattern)
    if provider !== nothing
        p = String(provider)
        idx = findfirst(m -> m.provider == p && m.id == pat, catalog)
        idx !== nothing && return catalog[idx]
        idx = findfirst(m -> m.provider == p && occursin(lowercase(pat), lowercase(m.id)), catalog)
        idx !== nothing && return catalog[idx]
        return _default_model(p, pat)
    end
    slash = findfirst('/', pat)
    if slash !== nothing
        p = pat[1:slash-1]
        id = pat[slash+1:end]
        idx = findfirst(m -> m.provider == p && m.id == id, catalog)
        idx !== nothing && return catalog[idx]
        idx = findfirst(m -> m.provider == p && occursin(lowercase(id), lowercase(m.id)), catalog)
        idx !== nothing && return catalog[idx]
        return _default_model(p, id)
    end
    idx = findfirst(m -> m.id == pat, catalog)
    idx !== nothing && return catalog[idx]
    idx = findfirst(m -> occursin(lowercase(pat), lowercase(m.id)), catalog)
    idx !== nothing && return catalog[idx]
    return nothing
end

function provider_api_key_hint(provider)
    return get(Dict("anthropic" => "ANTHROPIC_API_KEY", "openai" => "OPENAI_API_KEY",
                    "deepseek" => "DEEPSEEK_API_KEY"), provider, uppercase(provider) * "_API_KEY")
end
