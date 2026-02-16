# Copyright (c) 2018 Felipe Serrano, Miles Lubin, Robert Schwarz, and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

# SDP constraints: (VectorAffineFunction, PositiveSemidefiniteConeTriangle)
# Only supported when the optimizer was created with allow_sdp=true and SCIP-SDP is linked.

function _moi_psd_index_to_upper_triangle(k::Int, n::Int)::Tuple{Int,Int}
    # MOI PositiveSemidefiniteConeTriangle: lower triangle column by column.
    # Index k (1-based) -> (row, col) 1-based with row >= col.
    for j in 1:n
        if 2 * k <= j * (2 * n - j + 1)
            row = k - (j - 1) * n + div(j * (j - 1), 2)
            return (row, j)
        end
    end
    return (n, n)
end

function MOI.supports_constraint(
    o::Optimizer,
    ::Type{MOI.VectorAffineFunction{Float64}},
    ::Type{MOI.PositiveSemidefiniteConeTriangle},
)
    return o.sdp_enabled
end

function MOI.add_constraint(
    o::Optimizer,
    func::MOI.VectorAffineFunction{Float64},
    set::MOI.PositiveSemidefiniteConeTriangle,
)
    if !o.sdp_enabled
        throw(MOI.UnsupportedConstraint{typeof(func),typeof(set)}())
    end
    allow_modification(o)
    n = set.side_dimension
    dim = div(n * (n + 1), 2)
    if MOI.output_dimension(func) != dim
        error(
            "Dimension mismatch: PositiveSemidefiniteConeTriangle($n) has dimension $dim, " *
            "but function has output dimension $(MOI.output_dimension(func)).",
        )
    end
    # Group variable terms by variable and by (row,col); constant part.
    # func.terms: VectorAffineTerm(output_index, ScalarAffineTerm(coef, variable))
    # func.constants: vector of length dim
    var_entries = Dict{VarRef,Vector{Tuple{Int,Int,Float64}}}()
    const_entries = Tuple{Int,Int,Float64}[]
    for (idx, term) in enumerate(func.terms)
        output_index = term.output_index
        coef = term.scalar_term.coefficient
        vi = term.scalar_term.variable
        row, col = _moi_psd_index_to_upper_triangle(output_index, n)
        vr = VarRef(vi.value)
        if !haskey(var_entries, vr)
            var_entries[vr] = Tuple{Int,Int,Float64}[]
        end
        push!(var_entries[vr], (row, col, coef))
    end
    for (output_index, c) in enumerate(func.constants)
        iszero(c) && continue
        row, col = _moi_psd_index_to_upper_triangle(output_index, n)
        push!(const_entries, (row, col, c))
    end
    # Order variables by VarRef value for deterministic ordering
    var_refs = sort!(collect(keys(var_entries)); by=vr -> vr.val)
    var_entries_list = [var_entries[vr] for vr in var_refs]
    cr = add_sdp_constraint(
        o.inner,
        "",
        n,
        var_refs,
        var_entries_list,
        const_entries,
    )
    F = MOI.VectorAffineFunction{Float64}
    S = MOI.PositiveSemidefiniteConeTriangle
    ci = MOI.ConstraintIndex{F,S}(cr.val)
    register!(o, ci)
    register!(o, cons(o, ci), cr)
    return ci
end

function MOI.get(
    o::Optimizer,
    ::MOI.ConstraintFunction,
    ci::MOI.ConstraintIndex{MOI.VectorAffineFunction{Float64},MOI.PositiveSemidefiniteConeTriangle},
)
    _throw_if_invalid(o, ci)
    # We would need SCIPconsSdpGetData to implement get; for now throw.
    return error("Getting SDP constraint function is not implemented.")
end

function MOI.get(
    o::Optimizer,
    ::MOI.ConstraintSet,
    ci::MOI.ConstraintIndex{MOI.VectorAffineFunction{Float64},MOI.PositiveSemidefiniteConeTriangle},
)
    _throw_if_invalid(o, ci)
    c = cons(o, ci)
    ptr = Libdl.dlsym(Libdl.dlopen(libscip), :SCIPconsSdpGetBlocksize; throw_error=false)
    ptr === C_NULL && error("SCIPconsSdpGetBlocksize not found.")
    n = ccall(ptr, Cint, (Ptr{Cvoid}, Ptr{Cvoid}), o.inner.scip[], c)
    return MOI.PositiveSemidefiniteConeTriangle(n)
end
