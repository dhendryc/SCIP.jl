# Copyright (c) 2018 Felipe Serrano, Miles Lubin, Robert Schwarz, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

import Libdl

const depsjl_path = joinpath(@__DIR__, "..", "deps", "deps.jl")
if isfile(depsjl_path)
    # User-provided SCIP or SCIP-SDP library
    include(depsjl_path)
    if !isdefined(@__MODULE__, :have_scip_sdp)
        const have_scip_sdp = false
    end
else
    # Artifact from BinaryBuilder package (no SDP)
    const have_scip_sdp = false
    import SCIP_PaPILO_jll
    if SCIP_PaPILO_jll.is_available()
        using SCIP_PaPILO_jll: libscip
    else
        using SCIP_jll: libscip
    end
end

function __init__()
    config = LinearAlgebra.BLAS.lbt_get_config()
    if !any(lib -> lib.interface == :lp64, config.loaded_libs)
        LinearAlgebra.BLAS.lbt_forward(OpenBLAS32_jll.libopenblas_path)
    end
    major = SCIPmajorVersion()
    minor = SCIPminorVersion()
    patch = SCIPtechVersion()
    current = VersionNumber("$major.$minor.$patch")
    required = VersionNumber("9")
    upperbound = VersionNumber("11")
    if current < required || current >= upperbound
        @error(
            "SCIP is installed at version $current, " *
            "supported are $required up to (excluding) $upperbound."
        )
    end
    return
end
