# Copyright (c) 2018 Felipe Serrano, Miles Lubin, Robert Schwarz, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.
#
# SCIP-SDP: PSD cone, B&B vs outer approximation, optional Pajarito comparison.
# All tests are skipped when SCIP is not linked with SCIP-SDP (have_scip_sdp == false).

using Test
using MathOptInterface
const MOI = MathOptInterface
using SCIP

# Skip entire file when SCIP-SDP not available
if !@eval(SCIP, have_scip_sdp)
    @testset "SCIP-SDP" begin
        @test_skip "SCIP-SDP not linked (set SCIP_SDP_OPTDIR and rebuild to enable)"
    end
else
    # Small MISDP: min a + c  s.t. [a b; b c] ⪰ 0, b ∈ {0,1}. Optimal: 0 (a=c=0, b=0).
    function build_misdp_model(optimizer_constructor)
        model = MOI.instantiate(optimizer_constructor)
        MOI.set(model, MOI.Silent(), true)
        n = 2
        d = n * (n + 1) ÷ 2  # 3 variables for 2×2 PSD
        x = [MOI.add_variable(model) for _ in 1:d]
        MOI.add_constraint(model, x[2], MOI.ZeroOne())  # b binary
        MOI.add_constraint(
            model,
            MOI.VectorOfVariables(x),
            MOI.PositiveSemidefiniteConeTriangle(n),
        )
        MOI.set(model, MOI.ObjectiveSense(), MOI.MIN_SENSE)
        MOI.set(
            model,
            MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}(),
            MOI.ScalarAffineFunction(MOI.ScalarAffineTerm.([1.0, 1.0], [x[1], x[3]]), 0.0),
        )
        return model
    end

    @testset "SCIP-SDP" begin
        @testset "B&B with SDP relaxation (relaxing/SDP/freq=1)" begin
            model = build_misdp_model(SCIP.Optimizer)
            MOI.set(model, MOI.RawOptimizerAttribute("relaxing/SDP/freq"), 1)
            MOI.optimize!(model)
            @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMAL
            @test MOI.get(model, MOI.ObjectiveValue()) ≈ 0.0 atol = 1e-5
        end

        @testset "Outer approximation / cutting planes (relaxing/SDP/freq=-1)" begin
            model = build_misdp_model(SCIP.Optimizer)
            MOI.set(model, MOI.RawOptimizerAttribute("relaxing/SDP/freq"), -1)
            MOI.set(model, MOI.RawOptimizerAttribute("lp/solvefreq"), 1)
            MOI.optimize!(model)
            @test MOI.get(model, MOI.TerminationStatus()) == MOI.OPTIMAL
            @test MOI.get(model, MOI.ObjectiveValue()) ≈ 0.0 atol = 1e-5
        end

        # Optional: compare with Pajarito (Hypatia + HiGHS) if available
        @testset "Pajarito comparison (optional)" begin
            try
                using Pajarito
                using Hypatia
                using HiGHS
                # Pajarito uses optimizer_with_attributes; skip if API doesn't match
                oa = MOI.OptimizerWithAttributes(HiGHS.Optimizer, MOI.Silent() => true)
                conic = MOI.OptimizerWithAttributes(Hypatia.Optimizer, MOI.Silent() => true)
                model_paj = build_misdp_model(() -> Pajarito.Optimizer(oa, conic))
                MOI.optimize!(model_paj)
                obj_paj = MOI.get(model_paj, MOI.ObjectiveValue())
                @test obj_paj ≈ 0.0 atol = 1e-5
                model_scip = build_misdp_model(SCIP.Optimizer)
                MOI.set(model_scip, MOI.RawOptimizerAttribute("relaxing/SDP/freq"), 1)
                MOI.optimize!(model_scip)
                obj_scip = MOI.get(model_scip, MOI.ObjectiveValue())
                @test obj_scip ≈ obj_paj atol = 1e-4
            catch
                @test_skip "Pajarito/Hypatia/HiGHS not available or API mismatch"
            end
        end
    end
end
