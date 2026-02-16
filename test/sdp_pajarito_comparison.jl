# Copyright (c) 2018 Felipe Serrano, Miles Lubin, Robert Schwarz, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

# SDP test: max x s.t. [1 x; x 1] ⪰ 0 (continuous SDP, optimal x = 1).
# SCIP-SDP targets MISDP; Pajarito's MI support varies by version. We use continuous SDP so both run.
# Compares SCIP-SDP (when linked) with Pajarito + Hypatia.
# Only runs when SCIP-SDP is linked (SCIPOPTDIR set to SCIP-SDP install and Pkg.build("SCIP") run).
# Pajarito, Hypatia, HiGHS are assumed to be loaded (e.g. by the test runner or global env).

using Test
using SCIP
import MathOptInterface as MOI
using Pajarito
using Hypatia
using HiGHS

const SDP_SKIP_MSG = """
SCIP-SDP is not linked. To run SDP tests:
  1. Set ENV["SCIPOPTDIR"] to your SCIP-SDP install directory (e.g. "/Users/deborah/SCIP-SDP/build").
  2. Run Pkg.build("SCIP").
  3. Restart Julia and re-run the tests.
Without SCIP-SDP linked, this testset is skipped."""

const SDP_FAIL_MSG = """
SCIP-SDP is linked but the solve did not return a solution. Your build may be misconfigured or
plugins may not have loaded correctly (e.g. 'nonlinear already included' conflict).
  - Ensure SCIPOPTDIR points to a valid SCIP-SDP install (e.g. /Users/deborah/SCIP-SDP/build).
  - Ensure the library and its dependencies load (e.g. set DYLD_LIBRARY_PATH or fix rpaths).
  - If the SCIP-SDP command-line binary works, the Julia interface should use the same plugin order."""

function _build_sdp_max_x_model(optimizer_constructor)
    # Continuous SDP: max x s.t. [1 x; x 1] ⪰ 0 => -1 ≤ x ≤ 1, optimal x = 1.
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
    if !SCIP.sdp_available()
        @test_skip SDP_SKIP_MSG
    else
        # Without allow_sdp, SCIP does not support SDP constraints
        @test !MOI.supports_constraint(SCIP.Optimizer(), MOI.VectorAffineFunction{Float64}, MOI.PositiveSemidefiniteConeTriangle)

        # 1) Pajarito + Hypatia as reference
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

        # 2) SCIP-SDP (linked): branch-and-bound, then outer approximation
        # If optimizer creation fails (e.g. plugin conflict), we let it throw.
        model, _ = _build_sdp_max_x_model(() -> SCIP.Optimizer(allow_sdp=true))
        MOI.optimize!(model)
        status = MOI.get(model, MOI.TerminationStatus())
        n_sols = MOI.get(model, MOI.ResultCount())
        ok = status in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED) && n_sols > 0
        if !ok
            error("SCIP-SDP solve did not return a solution: status=$status, n_sols=$n_sols. $SDP_FAIL_MSG")
        end
        @test ok
        if ok
            scip_obj = MOI.get(model, MOI.ObjectiveValue())
            @test scip_obj ≈ 1.0 atol = 1e-4
            @test scip_obj ≈ pajarito_obj atol = 1e-3
        end

        oa_constructor = () -> begin
            o = SCIP.Optimizer(allow_sdp=true)
            MOI.set(o, SCIP.SDPSolvingMode(), :outer_approximation)
            return o
        end
        model_oa, _ = _build_sdp_max_x_model(oa_constructor)
        MOI.optimize!(model_oa)
        status_oa = MOI.get(model_oa, MOI.TerminationStatus())
        n_sols_oa = MOI.get(model_oa, MOI.ResultCount())
        ok_oa = status_oa in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED) && n_sols_oa > 0
        if !ok_oa
            error("SCIP-SDP outer-approximation solve did not return a solution: status=$status_oa, n_sols=$n_sols_oa. $SDP_FAIL_MSG")
        end
        @test ok_oa
        if ok_oa
            scip_oa_obj = MOI.get(model_oa, MOI.ObjectiveValue())
            @test scip_oa_obj ≈ 1.0 atol = 1e-4
            @test scip_oa_obj ≈ pajarito_obj atol = 1e-3
        end
    end
end
