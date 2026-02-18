# Copyright (c) 2018 Felipe Serrano, Miles Lubin, Robert Schwarz, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

using Libdl

# Build when user provides a custom SCIP path (SCIPOPTDIR) or SCIP-SDP path (SCIP_SDP_OPTDIR).
# SCIP_SDP_OPTDIR is a separate env var so SCIP and SCIP-SDP can be different builds.
if !haskey(ENV, "SCIPOPTDIR") && !haskey(ENV, "SCIP_SDP_OPTDIR")
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
for l in sdp_paths
    try
        d = Libdl.dlopen(l)
        write_depsfile(l, true)
        exit(0)
    catch
        continue
    end
end

# Else try standard SCIP
push!(paths_to_try, libname)
found = false
tried = String[]
for l in paths_to_try
    try
        d = Libdl.dlopen(l)
        global found = true
        write_depsfile(l, false)
        break
    catch e
        push!(tried, "$(l): $(e.msg)")
    end
end

if !found && !haskey(ENV, "SCIP_JL_SKIP_LIB_CHECK")
    error("""
Unable to locate SCIP installation. Tried SCIP_SDP_OPTDIR (libscipsdp/libscip), then:

$(join(tried, "\n\n"))

Set SCIPOPTDIR for standard SCIP or SCIP_SDP_OPTDIR for SCIP-SDP.
""")
end
