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

if abspath(PROGRAM_FILE) == @__FILE__
    zip_example = extract_zip("<zip-file>", "path/to/output")
    @info "Usage example" zip_example
    all_example = extract_all_zips("path/with/zips", "extracted")
    @info "Extracted folders" all_example
end
