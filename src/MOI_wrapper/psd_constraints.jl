# Copyright (c) 2018 Felipe Serrano, Miles Lubin, Robert Schwarz, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.
#
# PSD cone (PositiveSemidefiniteConeTriangle). Only loaded when have_scip_sdp.

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
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
