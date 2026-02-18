# Copyright (c) 2018 Felipe Serrano, Miles Lubin, Robert Schwarz, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

using Test
using SCIP
using SCIP_jll
using SCIP_PaPILO_jll

@show(@eval(SCIP, libscip) == SCIP_jll.libscip)
@show(
    SCIP_PaPILO_jll.is_available() &&
    @eval(SCIP, libscip) == SCIP_PaPILO_jll.libscip
)
@show SCIP.SCIP_versionnumber()

# new type definitions in module (needs top level)
include("conshdlr_support.jl")
include("sepa_support.jl")

@testset "SCIP" begin
    for file in [
        "conshdlr.jl",
        "cutsel.jl",
        "direct_library_calls.jl",
        "eventhdlr.jl",
        "MOI_tests.jl",
        "scip_data.jl",
        "SCIP_SDP_tests.jl",
    ]
        if file == "MOI_tests.jl" && SCIP.have_scip_sdp
            @testset "MOI_tests.jl" begin
                @test_skip "Full MOI suite skipped with SCIP-SDP (different solve path; run without SCIP_SDP_OPTDIR for full tests)"
            end
        else
            @testset "$file" begin
                include(file)
            end
        end
    end
end
