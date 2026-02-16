# Copyright (c) 2018 Felipe Serrano, Miles Lubin, Robert Schwarz, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

using Libdl

if !haskey(ENV, "SCIPOPTDIR")
    # Skip build in favor of SCIP_jll
    exit()
end

depsfile = joinpath(dirname(@__FILE__), "deps.jl")
if isfile(depsfile)
    rm(depsfile)
end

function write_depsfile(path)
    open(depsfile, "w") do f
        print(f, "const libscip = ")
        show(f, path)
        println(f)
    end
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

# SCIP-SDP builds may ship the library as libscipsdp
libname_sdp = if Sys.islinux()
    "libscipsdp.so"
elseif Sys.isapple()
    "libscipsdp.dylib"
elseif Sys.iswindows()
    "libscipsdp.dll"
else
    libname
end

paths_to_try = String[]

if haskey(ENV, "SCIPOPTDIR")
    scipoptdir = ENV["SCIPOPTDIR"]
    # If SCIPOPTDIR is a path to the library file itself, use it directly
    if isfile(scipoptdir)
        push!(paths_to_try, scipoptdir)
    elseif isdir(scipoptdir)
        # Otherwise treat as installation directory: try bin/ and lib/ with both library names
        for name in (libname, libname_sdp)
            push!(paths_to_try, joinpath(scipoptdir, "bin", name))
            push!(paths_to_try, joinpath(scipoptdir, "lib", name))
        end
    end
end

# fallback: search by library name in default locations
push!(paths_to_try, libname)

found = false
tried = String[]
for l in paths_to_try
    try
        d = Libdl.dlopen(l)
        global found = true
        write_depsfile(l)
        break
    catch e
        push!(tried, "$(l): $(e.msg)")
    end
end

if !found && !haskey(ENV, "SCIP_JL_SKIP_LIB_CHECK")
    error("""
Unable to locate SCIP installation. Tried:

$(join(tried, "\n\n"))

Set SCIPOPTDIR to either:
  - the installation directory (e.g. /path/to/SCIP-SDP/build), or
  - the full path to the library file (e.g. .../build/lib/libscip.dylib or .../libscipsdp.dylib).
""")
end
