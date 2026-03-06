# Copyright (c) 2018 Felipe Serrano, Miles Lubin, Robert Schwarz, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

using Libdl

# Build when user provides a custom SCIP path (SCIPOPTDIR) or SCIP-SDP path (SCIP_SDP_OPTDIR).
# SCIP_SDP_OPTDIR is a separate env var so SCIP and SCIP-SDP can be different builds.
# Print diagnostics so users see why custom build was skipped or what was tried.
const BUILD_VERBOSE = get(ENV, "JULIA_SCIP_BUILD_VERBOSE", "1") != "0"

if !haskey(ENV, "SCIPOPTDIR") && !haskey(ENV, "SCIP_SDP_OPTDIR")
    if BUILD_VERBOSE
        println("SCIP build: Neither SCIPOPTDIR nor SCIP_SDP_OPTDIR is set.")
        println("  Skipping custom build; SCIP will use the default JLL binary (no SCIP-SDP).")
        println("  To use your SCIP-SDP installation, set SCIP_SDP_OPTDIR in the same process that runs the build:")
        println("    In the shell before starting Julia:  export SCIP_SDP_OPTDIR=\"/path/to/SCIP-SDP/build\"")
        println("    Or in Julia before Pkg.build():       ENV[\"SCIP_SDP_OPTDIR\"] = \"/path/to/SCIP-SDP/build\"")
    end
    exit()
end

depsfile = joinpath(dirname(@__FILE__), "deps.jl")
if isfile(depsfile)
    rm(depsfile)
end

libname = if Sys.islinux()
    "libscip.so"
elseif Sys.isapple()
    "libscip.dylib"
elseif Sys.iswindows()
    "libscip.dll"
else
    error("SCIP is currently not supported on \"$(Sys.KERNEL)\"")
end

# SCIP-SDP may ship as libscipsdp or libscip
libsdpname = if Sys.islinux()
    "libscipsdp.so"
elseif Sys.isapple()
    "libscipsdp.dylib"
elseif Sys.iswindows()
    "libscipsdp.dll"
else
    libname
end

function write_depsfile(path, have_sdp::Bool)
    open(depsfile, "w") do f
        print(f, "const libscip = ")
        show(f, path)
        println(f)
        println(f, "const have_scip_sdp = ", have_sdp)
    end
end

paths_to_try = []
sdp_paths = []

# SCIP_SDP_OPTDIR: path to SCIP-SDP installation (for mixed integer conic / PSD)
if haskey(ENV, "SCIP_SDP_OPTDIR")
    sdp_base = ENV["SCIP_SDP_OPTDIR"]
    if BUILD_VERBOSE
        println("SCIP build: SCIP_SDP_OPTDIR = ", repr(sdp_base))
    end
    push!(sdp_paths, joinpath(sdp_base, "lib", libsdpname))
    push!(sdp_paths, joinpath(sdp_base, "bin", libsdpname))
    push!(sdp_paths, joinpath(sdp_base, "lib", libname))
    push!(sdp_paths, joinpath(sdp_base, "bin", libname))
end

# SCIPOPTDIR: standard SCIP installation
if haskey(ENV, "SCIPOPTDIR")
    push!(paths_to_try, joinpath(ENV["SCIPOPTDIR"], "bin", libname))
    push!(paths_to_try, joinpath(ENV["SCIPOPTDIR"], "lib", libname))
end

# Try SCIP-SDP first if requested (so one build can target SDP)
sdp_tried = String[]
for l in sdp_paths
    try
        d = Libdl.dlopen(l)
        write_depsfile(l, true)
        if BUILD_VERBOSE
            println("SCIP build: Loaded SCIP-SDP from ", l)
            println("SCIP build: have_scip_sdp = true")
        end
        exit(0)
    catch e
        msg = sprint(showerror, e)
        exists = isfile(l) ? " (file exists)" : " (file not found)"
        push!(sdp_tried, "  $l$exists\n    $msg")
        if BUILD_VERBOSE
            println("SCIP build: Failed to load ", l, exists, ": ", e.msg)
        end
    end
end

# If user set SCIP_SDP_OPTDIR but all SDP paths failed, error with clear diagnostics
if haskey(ENV, "SCIP_SDP_OPTDIR") && !isempty(sdp_paths)
    sdp_base = ENV["SCIP_SDP_OPTDIR"]
    error("""
SCIP_SDP_OPTDIR is set to $(repr(sdp_base)) but the SCIP-SDP library could not be loaded.

Paths tried:
$(join(sdp_tried, "\n"))

Check:
  • SCIP_SDP_OPTDIR should be the install prefix (e.g. where 'lib/' or 'bin/' contains libscipsdp).
  • If you built from source, use the install prefix (e.g. CMAKE_INSTALL_PREFIX), not the build dir, unless the library was built in-place.
  • On macOS, ensure the .dylib exists and 'otool -L' shows dependencies that are findable (e.g. run: otool -L $(repr(joinpath(sdp_base, "lib", libsdpname)))).
  • Unset SCIP_SDP_OPTDIR to build with standard SCIP only, or fix the path and run: ] build SCIP
""")
end

# Else try standard SCIP
if BUILD_VERBOSE && haskey(ENV, "SCIP_SDP_OPTDIR")
    println("SCIP build: All SCIP-SDP paths failed; trying standard SCIP fallback.")
end
push!(paths_to_try, libname)
found = false
tried = String[]
for l in paths_to_try
    try
        d = Libdl.dlopen(l)
        global found = true
        write_depsfile(l, false)
        if BUILD_VERBOSE
            println("SCIP build: Loaded standard SCIP from ", l, " (have_scip_sdp = false)")
        end
        break
    catch e
        push!(tried, "$(l): $(e.msg)")
    end
end

if !found && !haskey(ENV, "SCIP_JL_SKIP_LIB_CHECK")
    error("""
Unable to locate SCIP installation. Tried:

$(join(tried, "\n\n"))

Set SCIPOPTDIR for standard SCIP or SCIP_SDP_OPTDIR for SCIP-SDP (install prefix containing lib/libscipsdp or lib/libscip).
""")
end
