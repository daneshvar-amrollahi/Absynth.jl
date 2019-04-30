
using SymPy
using Combinatorics
using LinearAlgebra

# ------------------------------------------------------------------------------

import SymEngine.Basic
import SymPy.Sym

SymPy.Sym(x::Basic) = Sym(string(x))
SymEngine.Basic(x::SymPy.Sym) = Basic(string(x))

function coeffs(ex::Basic, x::Basic)
    Basic.(SymPy.coeffs(Sym(ex), Sym(x)))
end

function degree(ex::Basic, x::Basic)
    convert(Int, SymPy.degree(Sym(ex), gen=Sym(x)))
end

simplify(x::Basic) = Basic(SymPy.simplify(Sym(x)))

isconstant(x::Basic) = isempty(SymEngine.free_symbols(x))

# ------------------------------------------------------------------------------

function constraints(inv::Basic, dims::Int)
    B = [Basic("b$i$j") for i in 1:dims, j in 1:dims]
    constraints(B, inv)
end

function constraints(B::Matrix{Basic}, inv::Basic)
    for ms in partitions(size(B, 1))
        @info "Multiplicities" ms
        constraints(B, inv, ms)
        break
    end
end

abstract type AlgebraicNumber end

function constraints(B::Matrix{Basic}, inv::Basic, ms::Vector{Int})
    t = length(ms)
    rs = symroot(t)
    lc = Basic("n")
    cfs = cforms(size(B, 1), rs, ms, lc)
    p = SymEngine.lambdify(inv)(cfs...)
    cscforms = cstr_cforms(B, rs, ms)
    csroots, distinct = cstr_roots(B, rs, ms)
    csrel = cstr_algrel(p, rs, lc)
    @info "" cscforms csroots distinct csrel

    cs = Iterators.flatten(symconst(i, j, size(B, 1)) for i in 1:t for j in 1:ms[i]) |> collect
    bs = Iterators.flatten(B) |> collect
    vars = [cs; bs; rs]
    varmap = Dict(v=>AlgebraicNumber for v in vars)
    @info "Variables" vars |> collect

    solver = T()
    NLSat.variables!(solver, varmap...)
    NLSat.constraints!(solver, cscforms...)
    NLSat.constraints!(solver, csroots...)
    NLSat.constraints!(solver, csrel...)
end

function cforms(varcnt::Int, rs::Vector{Basic}, ms::Vector{Int}, lc::Basic)
    t = length(rs)
    sum(symconst(i, j, varcnt) * rs[i] * lc^(j-1) for i in 1:t for j in 1:ms[i])
end

symconst(i::Int, j::Int, rows::Int) = reshape([Basic("c$i$j$k") for k in 1:rows], rows, 1)
symroot(n::Int) = [Basic("w$i") for i in 1:n]

# ------------------------------------------------------------------------------

# function solve(s::Synthesizer; solvertype::Type{T}=Z3Solver, timeout::Int=120) where {T<:NLSolver}
#     @assert !isempty(invariants(s)) "No invariants specified."
#     if s.updated
#         _constraints!(s)
#     end

#     solver = T()

#     tmpl = template(s)
#     ivars = Dict{Symbol,Type}(Symbol(Recurrences.initvar(k))=>v for (k,v) in varmap(tmpl))
#     NLSat.variables!(solver, argmap(tmpl)..., ivars...)
#     if !isempty(constraints(s))
#         NLSat.constraints!(solver, constraints(s)...)
#     end
#     if !isempty(invconstraints(s))
#         NLSat.constraints!(solver, invconstraints(s)...)
#     end

#     status, model = NLSat.solve(solver, timeout=timeout)
#     @debug "Result of $T" status model
#     if status == NLSat.sat
#         undef = setdiff(args(tmpl), keys(model))
#         if !isempty(undef)
#             # TODO: deal with unknowns which do not appear in model
#             for v in undef
#                 push!(model, v => 0)
#             end
#         end
#         return setvalues(tmpl, Dict{Symbol,CoeffType}(model))
#     elseif status == NLSat.timeout
#         @error "Timeout"
#     else
#         @error "No solution exists. Result of $T: $status"
#     end
# end

# ------------------------------------------------------------------------------

function cstr_cforms(B::Matrix{Basic}, rs::Vector{Basic}, ms::Vector{Int})
    rows = size(B, 1)
    t = length(rs)
    [sum(binomial(k-1, j-1) * symconst(i, k, rows) * rs[i] for k in j:ms[i]) - B * symconst(i, j, rows) for i in 1:t for j in 1:ms[i]]
end

function cstr_roots(B, rs, ms)
    λ = Basic("lbd")
    cpoly = det(B-UniformScaling(λ)) |> simplify
    cstr = [SymEngine.subs(cpoly, λ=>r) for r in rs]
    # distinct = [r1-r2 for (r1,r2) in combinations(rs, 2)]
    cstr, combinations(rs, 2)
end

# ------------------------------------------------------------------------------

function cstr_algrel(p::Basic, rs::Vector{Basic}, lc::Basic)
    qs = destructpoly(p, lc)
    cs = Basic[]
    for (i, q) in enumerate(qs)
        ms, us = destructterm(q, rs)
        l = length(ms)
        if all(isone, ms)
            l = 1
        end
        c = [sum(m^j*u for (m,u) in zip(ms,us)) for j in 0:l-1]
        append!(cs, c)
    end
    cs
end

# ------------------------------------------------------------------------------

function destructpoly(p::Basic, lc::Basic)
    coeffs(p, lc)
end

function destructterm(p::Basic, rs::Vector{Basic})
    ms = Basic[]
    cs = Basic[]
    for term in get_args(SymEngine.expand(p))
        ds = [degree(term, r) for r in rs]
        m = prod(r^d for (r,d) in zip(rs,ds))
        c = term / m
        push!(ms, m)
        push!(cs, c)
    end
    ms, cs
end


