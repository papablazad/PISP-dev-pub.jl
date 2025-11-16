using PISP
using PISP.ISPTraceDownloader
using PISP.ISPFileDownloader
using PISP.PISPScrapperUtils

throttle_env = get(ENV, "ISP_DOWNLOAD_THROTTLE", "")
traces_options = FileDownloadOptions(outdir            = normpath(@__DIR__, "..", "..", "data-new", "traces"),
                        confirm_overwrite = true,
                        skip_existing     = false,
                        throttle_seconds  = isempty(throttle_env) ? nothing : parse(Float64, throttle_env));

files_options = FileDownloadOptions(outdir = normpath(@__DIR__, "..", "..", "data-new"),
                        confirm_overwrite = false,
                        skip_existing     = true);

downloaded_files  = download_all_isp_files(options = files_options)
downloaded_traces = download_isp24_traces(options = traces_options)

println("Downloaded $(length(downloaded_files)) ISP reference files to $(files_options.outdir)")
println("Downloaded $(length(downloaded_traces)) ISP trace archives to $(traces_options.outdir)")
