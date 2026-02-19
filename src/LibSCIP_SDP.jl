# Copyright (c) 2018 Felipe Serrano, Miles Lubin, Robert Schwarz, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.
#
# SCIP-SDP–specific C API. Only used when have_scip_sdp and libscip is SCIP-SDP.

using Libdl

# SCIPSDPincludeDefaultPlugins(scip) – include SDP relaxator, cons handler, etc.
function SCIPSDPincludeDefaultPlugins(scip::Ptr{Cvoid})
    ccall((:SCIPSDPincludeDefaultPlugins, libscip), SCIP_RETCODE, (Ptr{Cvoid},), scip)
end

# Optional: get total SDP solver iterations (B&B mode). Returns nothing if symbol not in library.
# SCIP-SDP: SCIPrelaxSdpGetNIterations(SCIP_RELAX *relax) takes the SDP relaxator pointer, not scip.
function SCIPrelaxSDPgetNIterations(scip::Ptr{Cvoid})
    relax = SCIPfindRelax(scip, "SDP")
    (relax === C_NULL || relax === nothing) && return nothing
    handle = Libdl.dlopen(libscip; throw_error=false)
    (handle === C_NULL || handle === nothing) && return nothing
    # C symbol is SCIPrelaxSdpGetNIterations (capital G, "Sdp"); returns int
    for sym in ("SCIPrelaxSdpGetNIterations", "SCIPrelaxSDPgetNIterations")
        ptr = Libdl.dlsym(handle, sym; throw_error=false)
        if ptr isa Ptr && ptr != C_NULL
            return Int(ccall(ptr, Cint, (Ptr{Cvoid},), relax))
        end
    end
    return nothing
end

# SCIPcreateConsSdp: creates SDP constraint ∑_j A_j x_j - A_0 ⪰ 0 (symmetric matrices, sparse).
# nvarnonz: number of nonzeros per variable; col, row, val: pointers to arrays of length nvars.
function SCIPcreateConsSdp(
    scip::Ptr{Cvoid},
    cons::Ref{Ptr{Cvoid}},
    name::Cstring,
    nvars::Cint,
    nnonz::Cint,
    blocksize::Cint,
    nvarnonz::Ptr{Cint},
    col::Ptr{Ptr{Cint}},
    row::Ptr{Ptr{Cint}},
    val::Ptr{Ptr{Cdouble}},
    vars::Ptr{Ptr{Cvoid}},
    constnnonz::Cint,
    constcol::Ptr{Cint},
    constrow::Ptr{Cint},
    constval::Ptr{Cdouble},
)
    ccall(
        (:SCIPcreateConsSdp, libscip),
        SCIP_RETCODE,
        (
            Ptr{Cvoid},
            Ref{Ptr{Cvoid}},
            Cstring,
            Cint,
            Cint,
            Cint,
            Ptr{Cint},
            Ptr{Ptr{Cint}},
            Ptr{Ptr{Cint}},
            Ptr{Ptr{Cdouble}},
            Ptr{Ptr{Cvoid}},
            Cint,
            Ptr{Cint},
            Ptr{Cint},
            Ptr{Cdouble},
        ),
        scip,
        cons,
        name,
        nvars,
        nnonz,
        blocksize,
        nvarnonz,
        col,
        row,
        val,
        vars,
        constnnonz,
        constcol,
        constrow,
        constval,
    )
end
