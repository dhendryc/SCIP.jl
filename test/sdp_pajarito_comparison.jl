# Copyright (c) 2018 Felipe Serrano, Miles Lubin, Robert Schwarz, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

# SDP test: simple problem max x s.t. [1 x; x 1] ⪰ 0 (equivalent to -1 ≤ x ≤ 1, optimal x = 1).
# Compares SCIP-SDP (when available) with Pajarito + Hypatia.
# Pajarito, Hypatia, HiGHS are assumed to be loaded (e.g. by the test runner or global env).

using Test
using SCIP
import MathOptInterface as MOI
using Pajarito
using Hypatia
using HiGHS

function _build_sdp_max_x_model(optimizer_constructor)
    # Use CachingOptimizer so solvers that don't support incremental building (e.g. Pajarito) work
    model = MOI.instantiate(optimizer_constructor; with_cache_type = Float64)
    MOI.set(model, MOI.Silent(), true)
    x = MOI.add_variable(model)
    # Constraint: [1 x; x 1] in PSD (lower triangle column-wise: (1,1)=1, (2,1)=x, (2,2)=1)
    # VectorAffineFunction: output indices 1, 2, 3 -> (1,1), (2,1), (2,2); only (2,1) has variable x
    terms = [MOI.VectorAffineTerm(2, MOI.ScalarAffineTerm(1.0, x))]
    constants = [1.0, 0.0, 1.0]  # (1,1)=1, (2,1)=0, (2,2)=1 => matrix [1 x; x 1]
    func = MOI.VectorAffineFunction(terms, constants)
    set = MOI.PositiveSemidefiniteConeTriangle(2)
    MOI.add_constraint(model, func, set)
    MOI.set(model, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    MOI.set(model, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(), MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1.0, x)], 0.0))
    return model, x
end

@testset "SDP: max x s.t. [1 x; x 1] ⪰ 0" begin
    # Without allow_sdp, SCIP does not support SDP constraints
    @test !MOI.supports_constraint(SCIP.Optimizer(), MOI.VectorAffineFunction{Float64}, MOI.PositiveSemidefiniteConeTriangle)

    # 1) SCIP with SCIP-SDP when available
    scip_sdp_ok = false
    scip_obj = NaN
    try
        model, _ = _build_sdp_max_x_model(() -> SCIP.Optimizer(allow_sdp=true))
        MOI.optimize!(model)
        if MOI.get(model, MOI.TerminationStatus()) in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED)
            scip_obj = MOI.get(model, MOI.ObjectiveValue())
            scip_sdp_ok = true
        end
    catch
        # SCIP-SDP not linked or other failure; skip SCIP-SDP checks
    end
    if scip_sdp_ok
        @test scip_obj ≈ 1.0 atol = 1e-4
    end

    # 2) Pajarito + Hypatia as reference (assumes Pajarito, Hypatia, HiGHS are loaded)
    oa_solver = MOI.OptimizerWithAttributes(HiGHS.Optimizer, MOI.Silent() => true)
    conic_solver = MOI.OptimizerWithAttributes(Hypatia.Optimizer, MOI.Silent() => true)
    optimizer_constructor = () -> Pajarito.Optimizer(
        false, 1e-7, 1e-5, 1e-4, 1e6, 1000,
        nothing, true, true, true, true,
        oa_solver, conic_solver, nothing,
    )
    model_paj, _ = _build_sdp_max_x_model(optimizer_constructor)
    MOI.optimize!(model_paj)
    @test MOI.get(model_paj, MOI.TerminationStatus()) in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED)
    pajarito_obj = MOI.get(model_paj, MOI.ObjectiveValue())
    @test pajarito_obj ≈ 1.0 atol = 1e-4
    if scip_sdp_ok
        @test scip_obj ≈ pajarito_obj atol = 1e-3
    end
end
