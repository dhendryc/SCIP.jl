# Copyright (c) 2018 Felipe Serrano, Miles Lubin, Robert Schwarz, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.
#
# PSD cone (PositiveSemidefiniteConeTriangle). Only loaded when have_scip_sdp.
# VectorAffineFunction avoids checkVarsLocks when matrix entries are affine in
# variables that also appear in other constraints.

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{MOI.PositiveSemidefiniteConeTriangle},
)
    return have_scip_sdp
end

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorAffineFunction{Float64}},
    ::Type{MOI.PositiveSemidefiniteConeTriangle},
)
    return have_scip_sdp
end

function MOI.add_constraint(
    o::Optimizer,
    func::MOI.VectorOfVariables,
    set::MOI.PositiveSemidefiniteConeTriangle,
)
    allow_modification(o)
    varrefs = [VarRef(vi.value) for vi in func.variables]
    cr = add_psd_constraint(o.inner, varrefs)
    ci = MOI.ConstraintIndex{typeof(func),typeof(set)}(cr.val)
    register!(o, ci)
    register!(o, cons(o, ci), cr)
    return ci
end

function MOI.add_constraint(
    o::Optimizer,
    func::MOI.VectorAffineFunction{Float64},
    set::MOI.PositiveSemidefiniteConeTriangle,
)
    allow_modification(o)
    n = MOI.output_dimension(set)
    const_vec = copy(func.constants)
    terms_per_var = Dict{VarRef,Vector{Tuple{Int,Int,Float64}}}()
    for term in func.terms
        i, j = _psd_k_to_ij(term.output_index)
        vr = VarRef(term.scalar_term.variable.value)
        push!(get!(terms_per_var, vr) do; Tuple{Int,Int,Float64}[] end, (i, j, term.scalar_term.coefficient))
    end
    varrefs = collect(keys(terms_per_var))
    cr = add_psd_constraint_affine(o.inner, varrefs, terms_per_var, const_vec)
    ci = MOI.ConstraintIndex{typeof(func),typeof(set)}(cr.val)
    register!(o, ci)
    register!(o, cons(o, ci), cr)
    return ci
end

function MOI.get(
    o::Optimizer,
    ::MOI.ConstraintFunction,
    ci::MOI.ConstraintIndex{MOI.VectorOfVariables,MOI.PositiveSemidefiniteConeTriangle},
)
    throw(MOI.GetNotAllowed())
end

function MOI.get(
    o::Optimizer,
    ::MOI.ConstraintSet,
    ci::MOI.ConstraintIndex{MOI.VectorOfVariables,MOI.PositiveSemidefiniteConeTriangle},
)
    throw(MOI.GetNotAllowed())
end
