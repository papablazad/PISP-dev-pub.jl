module PISPScrapperUtils

    using HTTP
    using Downloads

    export DEFAULT_FILE_HEADERS,
        FileDownloadOptions,
        download_file,
        interactive_overwrite_prompt,
        prompt_skip_existing,
        ask_yes_no,
        extract_zip,
        extract_all_zips

    const DEFAULT_FILE_HEADERS = Pair{String,String}[
        "User-Agent"      => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        "Accept"          => "*/*",
        "Referer"         => "https://aemo.com.au/",
        "Accept-Language" => "en-AU,en;q=0.9",
        "Connection"      => "keep-alive",
    ]

    struct FileDownloadOptions
        outdir::String
        confirm_overwrite::Bool
        skip_existing::Bool
        throttle_seconds::Union{Nothing,Real}
        file_headers::Vector{Pair{String,String}}
    end

    function FileDownloadOptions(; outdir::AbstractString,
                                confirm_overwrite::Bool = true,
                                skip_existing::Bool = false,
                                throttle_seconds::Union{Nothing,Real} = nothing,
                                file_headers::Vector{Pair{String,String}} = DEFAULT_FILE_HEADERS)
        return FileDownloadOptions(String(outdir), confirm_overwrite, skip_existing,
                                    throttle_seconds, file_headers)
    end

    function download_file(url::AbstractString, dest::AbstractString;
                            headers::Vector{Pair{String,String}} = DEFAULT_FILE_HEADERS)
        resp = HTTP.get(url; headers = headers)
        if resp.status == 200
            open(dest, "w") do io
                write(io, resp.body)
            end
            return dest
        end
        @warn "HTTP.get failed with status $(resp.status); trying Downloads.download" url
        Downloads.download(url, dest)
        return dest
    end

    function interactive_overwrite_prompt(path::AbstractString)
        println("⚠️  File already exists: $(path)")
        return ask_yes_no("Replace it?"; default = false)
    end

    function prompt_skip_existing()
        println("⚠️  Multiple files have been kept so far.")
        return ask_yes_no("Skip replacing any existing files for the rest of this run?"; default = false)
    end

    function ask_yes_no(prompt::AbstractString; default::Bool = false)
        suffix = default ? " [Y/n]: " : " [y/N]: "
        while true
            print(prompt, suffix)
            flush(stdout)
            resp = try
                readline()
            catch err
                err isa EOFError && return default
                rethrow(err)
            end
            resp = lowercase(strip(resp))
            isempty(resp) && return default
            resp in ("y", "yes") && return true
            resp in ("n", "no") && return false
            println("    Please answer 'y' or 'n'.")
        end
    end

    """
    extract_zip(zip_path::AbstractString, dest_dir::AbstractString;
                overwrite::Bool = true, quiet::Bool = true)

    Extracts the contents of `zip_path` into the directory `dest_dir`. Creates
    `dest_dir` if it does not exist and returns the normalized destination path.

    `overwrite = true` replaces existing files. When `quiet = true` the underlying
    system command suppresses its standard output where possible.
    """
    function extract_zip(zip_path::AbstractString, dest_dir::AbstractString;
                        overwrite::Bool = true, quiet::Bool = true)
        abs_zip = normpath(zip_path)
        abs_dest = normpath(dest_dir)
        isfile(abs_zip) || error("Zip file not found: $(abs_zip)")
        mkpath(abs_dest)

        if Sys.iswindows()
            force_flag = overwrite ? "-Force" : ""
            quiet_flag = quiet ? "-Verbose:\$false" : ""
            cmd = `powershell -NoLogo -NoProfile -Command Expand-Archive -LiteralPath $(abs_zip) -DestinationPath $(abs_dest) $force_flag $quiet_flag`
            run(cmd)
        else
            args = ["unzip"]
            quiet && push!(args, "-q")
            push!(args, overwrite ? "-o" : "-n")
            append!(args, [abs_zip, "-d", abs_dest])
            run(Cmd(args))
        end

        return abs_dest
    end

    """
        extract_all_zips(src_dir::AbstractString, dest_root::AbstractString; kwargs...)

    Finds every `.zip` file within `src_dir` (non-recursive) and extracts each archive
    into `dest_root/<zip-basename>/`. Any keyword arguments are forwarded to
    `extract_zip`. Returns a vector with the destination paths for each extracted zip.
    """
    function extract_all_zips(src_dir::AbstractString, dest_root::AbstractString; kwargs...)
        abs_src = normpath(src_dir)
        abs_dest_root = normpath(dest_root)
        isdir(abs_src) || error("Source directory not found: $(abs_src)")
        mkpath(abs_dest_root)

        zip_files = filter(f -> endswith(lowercase(f), ".zip"),
                        sort(readdir(abs_src; join = true)))
        isempty(zip_files) && return String[]

        extracted_paths = String[]
        for zip_path in zip_files
            base = splitext(basename(zip_path))[1]
            target_dir = joinpath(abs_dest_root, base)
            extract_zip(zip_path, target_dir; kwargs...)
            push!(extracted_paths, target_dir)
        end

        return extracted_paths
    end

end
