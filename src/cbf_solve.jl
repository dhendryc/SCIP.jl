# Copyright (c) 2018 Felipe Serrano, Miles Lubin, Robert Schwarz, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.
#
# Load a problem from a CBF file, solve with SCIP-SDP, and return solution.
# Bypasses the MOI/SCIP programmatic API to avoid the checkVarsLocks assertion
# when variables appear in both SDP and linear constraints.

"""
    solve_cbf_with_scip_sdp(cbf_path::String; time_limit=Inf, gap=1e-2, absgap=1e-6, verbose=true, sdp_mode=:oa)

Load an optimization problem from a CBF file, solve with SCIP-SDP, and return
(status, var_values_by_name, objective_value, solve_time, dual_bound, rel_gap, ...).

- `gap`: relative optimality gap limit (SCIP `limits/gap`). Solving stops when relative gap is below this.
- `absgap`: optional absolute optimality gap limit (SCIP `limits/absgap`). If set, solving also stops when
  |primal - dual| is below this value.
- `presolving`: if `true` (default), use SCIP presolving (`presolving/maxrounds = -1`). If `false`, disable
  presolving (`presolving/maxrounds = 0`).
- `symmetry`: if `true` (default), enable symmetry handling (`misc/usesymmetry = 1`). If `false`, disable
  symmetry detection / propagation (`misc/usesymmetry = 0`).

Requires SCIP-SDP (have_scip_sdp == true). Uses SCIPreadProb to load the file,
avoiding the programmatic MOI path that triggers checkVarsLocks for models with
variables in both SDP and linear constraints.

# Solving mode (`sdp_mode`)
- `:bnb` — Branch-and-bound with SDP relaxations: solve SDP at each node (relaxing/SDP/freq=1).
- `:oa`  — Outer approximation: LP relaxations plus cutting planes, no SDP at nodes (relaxing/SDP/freq=-1, lp/solvefreq=1).
"""
function solve_cbf_with_scip_sdp(
    cbf_path::String;
    time_limit = Inf,
    gap = 1e-2,
    absgap = 1e-6,
    verbose = true,
    sdp_mode = :oa,
    presolving = true,
    symmetry = true,
)
    @assert have_scip_sdp "SCIP-SDP required. Set SCIP_SDP_OPTDIR and rebuild SCIP."
    isfile(cbf_path) || error("CBF file not found: $cbf_path")
    sdp_mode in (:bnb, :oa) || error("sdp_mode must be :bnb (B&B with SDP) or :oa (outer approximation), got $sdp_mode")

    scip_ref = Ref{Ptr{SCIP_}}(C_NULL)
    @SCIP_CALL SCIPcreate(scip_ref)
    scip = scip_ref[]
    try
        @SCIP_CALL SCIPSDPincludeDefaultPlugins(scip)
        @SCIP_CALL SCIPcreateProbBasic(scip, "")
        @SCIP_CALL SCIPreadProb(scip, cbf_path, "cbf")

        # Parameters
        if isfinite(time_limit) && time_limit > 0
            _set_param(scip, "limits/time", time_limit)
        end
        _set_param(scip, "limits/gap", gap)
        _set_param(scip, "limits/absgap", absgap)
        _set_param(scip, "display/verblevel", verbose ? 4 : 0)

        # Presolving and symmetry (same semantics as SCIP.jl MOI `Presolving` and `misc/usesymmetry`)
        _set_param(scip, "presolving/maxrounds", presolving ? -1 : 0)
        _set_param(scip, "misc/usesymmetry", symmetry ? 1 : 0)

        # Solving mode: B&B with SDP relaxations vs outer approximation
        if sdp_mode === :bnb
            _set_param(scip, "relaxing/SDP/freq", 1)
        else
            _set_param(scip, "relaxing/SDP/freq", -1)
            _set_param(scip, "lp/solvefreq", 1)
        end

        @SCIP_CALL SCIPsolve(scip)

        status = SCIPgetStatus(scip)
        solve_time = SCIPgetSolvingTime(scip)

        # Bounds and gap (SCIP uses minimization internally: dual = lower, primal = upper)
        dual_bound = SCIPgetDualbound(scip)
        rel_gap = SCIPgetGap(scip)

        # Diagnostics: nodes (both modes), cuts (OA mode), SDP iterations (B&B mode)
        n_nodes = Int(SCIPgetNNodes(scip))
        n_cuts_found = SCIPgetNCutsFound(scip)
        n_cuts_applied = SCIPgetNCutsApplied(scip)
        n_sdp_iters = SCIPrelaxSDPgetNIterations(scip)

        var_values = Dict{String,Float64}()
        var_values_ordered = Float64[]
        obj_val = NaN

        sol = SCIPgetBestSol(scip)
        if sol != C_NULL
            obj_val = SCIPgetSolOrigObj(scip, sol)
            nvars = SCIPgetNVars(scip)
            if nvars > 0
                vars_ptr = SCIPgetVars(scip)
                var_arr = unsafe_wrap(Array{Ptr{SCIP_VAR}}, vars_ptr, nvars)
                sizehint!(var_values_ordered, nvars)
                for i in 1:nvars
                    v = var_arr[i]
                    name_ptr = SCIPvarGetName(v)
                    name = name_ptr == C_NULL ? "" : unsafe_string(name_ptr)
                    val = SCIPgetSolVal(scip, sol, v)
                    var_values[name] = val
                    push!(var_values_ordered, val)
                end
            end
        end

        return (; status, var_values, var_values_ordered, obj_val, solve_time,
            dual_bound, rel_gap,
            n_nodes, n_cuts_found, n_cuts_applied, n_sdp_iters)
    finally
        if scip_ref[] != C_NULL
            @SCIP_CALL SCIPfree(scip_ref)
        end
    end
end

function _set_param(scip::Ptr{SCIP_}, name::AbstractString, value)
    param = SCIPgetParam(scip, name)
    param == C_NULL && error("Unrecognized parameter: $name")
    paramtype = SCIPparamGetType(param)
    if paramtype === SCIP_PARAMTYPE_BOOL
        @SCIP_CALL SCIPsetBoolParam(scip, name, value)
    elseif paramtype === SCIP_PARAMTYPE_INT
        @SCIP_CALL SCIPsetIntParam(scip, name, value)
    elseif paramtype === SCIP_PARAMTYPE_LONGINT
        @SCIP_CALL SCIPsetLongintParam(scip, name, value)
    elseif paramtype === SCIP_PARAMTYPE_REAL
        @SCIP_CALL SCIPsetRealParam(scip, name, value)
    elseif paramtype === SCIP_PARAMTYPE_CHAR
        @SCIP_CALL SCIPsetCharParam(scip, name, value)
    elseif paramtype === SCIP_PARAMTYPE_STRING
        @SCIP_CALL SCIPsetStringParam(scip, name, value)
    else
        error("Unexpected parameter type: $paramtype")
    end
end
