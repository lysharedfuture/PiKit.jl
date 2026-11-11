const LOG_TAG = "coding_tools_tools_manager"

function bin_dir(agent_dir=default_agent_dir())
    return joinpath(agent_dir, "bin")
end

function _exe(name)
    return Sys.iswindows() ? name * ".exe" : name
end

function _candidate_names(name)
    name == "fd" ? ["fd", "fdfind"] : [name]
end

function _find_existing_tool(name::String, agent_dir::String)
    dir = bin_dir(agent_dir)
    for candidate in _candidate_names(name)
        path = joinpath(dir, _exe(candidate))
        isfile(path) && return path
    end
    for candidate in _candidate_names(name)
        path = Sys.which(candidate)
        path !== nothing && return String(path)
    end
    return nothing
end

function _release_target()
    arch = Sys.ARCH == :x86_64 ? "x86_64" : Sys.ARCH == :aarch64 ? "aarch64" : nothing
    arch === nothing && throw(ErrorException("Unsupported architecture for tool downloads: $(Sys.ARCH)"))
    if Sys.isapple()
        return "$(arch)-apple-darwin.tar.gz"
    elseif Sys.iswindows()
        return "$(arch)-pc-windows-msvc.zip"
    end
    return "$(arch)-unknown-linux-musl.tar.gz"
end

function _release_url(name::String)
    target = _release_target()
    if name == "rg"
        version = "14.1.1"
        return "https://github.com/BurntSushi/ripgrep/releases/download/$(version)/ripgrep-$(version)-$(target)"
    elseif name == "fd"
        version = "10.3.0"
        return "https://github.com/sharkdp/fd/releases/download/v$(version)/fd-v$(version)-$(target)"
    end
    throw(ArgumentError("unsupported tool: $(name)"))
end

function _extract_archive(archive::String, dest::String)
    mkpath(dest)
    if endswith(archive, ".tar.gz")
        run(`tar xzf $(archive) -C $(dest)`)
    elseif endswith(archive, ".zip")
        if Sys.iswindows()
            tar_exe = joinpath(get(ENV, "SystemRoot", "C:\\Windows"), "System32", "tar.exe")
            if isfile(tar_exe)
                try
                    run(`$(tar_exe) xf $(archive) -C $(dest)`)
                    return
                catch err
                    @warn "System32 tar extract failed; trying Expand-Archive" _group=LOG_TAG exception=(err, catch_backtrace())
                end
            end
            run(pipeline(`powershell -NoProfile -NonInteractive -Command "Expand-Archive -Force -LiteralPath '$(archive)' -DestinationPath '$(dest)'"`))
        else
            if Sys.which("unzip") !== nothing
                try
                    run(`unzip -o -q $(archive) -d $(dest)`)
                    return
                catch err
                    @warn "unzip failed; trying tar" _group=LOG_TAG exception=(err, catch_backtrace())
                end
            end
            run(`tar xf $(archive) -C $(dest)`)
        end
    end
end

function _install_tool(name::String, agent_dir::String)
    dir = bin_dir(agent_dir)
    mkpath(dir)
    url = _release_url(name)
    archive = joinpath(dir, basename(url))
    tmp = mktempdir()
    @info "downloading external tool" _group=LOG_TAG tool=name url=url
    HTTP.download(url, archive; readtimeout=300_000, connect_timeout=30_000)
    _extract_archive(archive, tmp)
    target = nothing
    for (root, _, files) in walkdir(tmp)
        for file in files
            base = basename(file)
            if base == _exe(name) || base == name || (name == "fd" && base in ("fd", "fdfind"))
                target = joinpath(root, file)
                break
            end
        end
        target === nothing || break
    end
    target === nothing && throw(ErrorException("Downloaded $(name) archive did not contain the binary"))
    dest = joinpath(dir, _exe(name))
    cp(target, dest; force=true)
    chmod(dest, 0o755)
    return dest
end

function ensure_tool(name::String; agent_dir=default_agent_dir(), offline=nothing)
    existing = _find_existing_tool(name, agent_dir)
    existing !== nothing && return existing
    is_offline = offline === nothing ? get(ENV, "PIKIT_OFFLINE", "0") == "1" : offline
    if is_offline
        throw(ErrorException("$(name) is not installed and PIKIT_OFFLINE=1 forbids downloading it."))
    end
    try
        return _install_tool(name, agent_dir)
    catch err
        throw(ErrorException("Unable to install $(name): $(sprint(showerror, err))"))
    end
end
