mutable struct BinaryStump{S} <: ExactStat{(1, 0)}
    stats1::S           # summary statistics for class = -1
    stats2::S           # summary statistics for class = 1
    split_var::Int      # which variable to split on
    split_loc::Float64  # location to make the split
    split_lab::Float64  # class label when xj < split_loc
    featuresubset::Vector{Int}  # indices of the subset of features
end
function BinaryStump(p::Int, b::Int = 10, subset = 1:p) 
    BinaryStump(p * Hist(b), p * Hist(b), 0, Inf, 0.0, collect(subset))
end
function Base.show(io::IO, o::BinaryStump)
    println(io, "BinaryStump:")
    println(io, "  > -1: ", name(o.stats1))
    print(io, "  >  1: ", name(o.stats2))
    if o.split_var > 0
        print(io, "\n  > split on variable ", o.featuresubset[o.split_var], " at ", o.split_loc)
    end
end

nparams(o::BinaryStump) = length(o.stats1)
function probs(o::BinaryStump) 
    n = [nobs(first(o.stats1)), nobs(first(o.stats2))]
    n ./ sum(n)
end

value(o::BinaryStump) = find_split(o)

function fit!(o::BinaryStump, xy, γ)
    x, y = xy
    xi = x[o.featuresubset]
    if y == -1.0 
        fit!(o.stats1, xi, γ)
    elseif y == 1.0
        fit!(o.stats2, xi, γ)
    else 
        error("$y should be -1 or 1")
    end
end

function find_split(o::BinaryStump)
    imp_root = impurity(probs(o))
    s1 = copy(o.stats1)
    s2 = copy(o.stats2)
    ig = zeros(nparams(o))  # information gain
    locs = zeros(nparams(o))
    labs = zeros(nparams(o))
    for j in eachindex(ig)
        h1 = s1[j]
        h2 = s2[j]
        locj = (mean(h1) + mean(h2)) / 2  # TODO: find best split location

        n1l, n1r = splitcounts(h1, locj)  # number of -1s, left and right
        n2l, n2r = splitcounts(h2, locj)  # number of 1s, left and right

        counts_l = [n1l, n2l]  # counts of -1 and 1 in left
        counts_r = [n1r, n2r]  # counts of -1 and 1 in right

        probs_l = counts_l ./ sum(counts_l)  # probs of left
        probs_r = counts_r ./ sum(counts_r)  # probs of right

        left_imp = impurity(probs_l)  # impurity of left
        right_imp = impurity(probs_r)  # impurity of right
        after_imp = smooth(left_imp, right_imp, (n1r + n2r) / (n1r + n2r + n1l + n2l))

        locs[j] = locj
        ig[j] = imp_root - after_imp 

        # More -1s than 1s in left?  label -1 : label 1
        labs[j] = n1l > n2l ? -1.0 : 1.0
    end
    o.split_var = findmax(ig)[2]    # find largest information gain
    o.split_loc = locs[o.split_var] # get split location
    o.split_lab = labs[o.split_var] # get label for when split is true
end

function classify(o::BinaryStump, x::VectorOb) 
    x[o.featuresubset[o.split_var]] < o.split_loc ? o.split_lab : -o.split_lab
end
function classify(o::BinaryStump, x::AbstractMatrix, ::Rows = Rows())
    mapslices(x -> classify(o, x), x, 2)
end
function classify(o::BinaryStump, x::AbstractMatrix, ::Cols)
    mapslices(x -> classify(o, x), x, 1)
end

#-----------------------------------------------------------------------# BinaryStumpForest 
"""
    BinaryStumpForest(p::Int; nt = 100, b = 10, np = 3)

Build a random forest (for responses -1, 1) based on stumps (single-split trees) where 

- `p` is the number of predictors 
- `nt` is the number of trees (stumps) in the forest 
- `b` is the number of histogram bins used to estimate ``P(x_j | class)``
- `np` is the number of random predictors each tree will use

# Usage

After fitting, you must call `value` to calculate the splits.
"""
struct BinaryStumpForest{S} <: ExactStat{(1, 0)}
    forest::Vector{BinaryStump{S}}
end
function BinaryStumpForest(p::Integer; nt = 100, b = 10, np = 3)
    forest = [BinaryStump(np, b, sample(1:p, np; replace=false)) for i in 1:nt]
    BinaryStumpForest(forest)
end

value(o::BinaryStumpForest) = value.(o.forest)

function fit!(o::BinaryStumpForest, xy, γ)
    i = rand(1:length(o.forest))  # TODO: other schemes for this randomization part
    fit!(o.forest[i], xy, γ)
end

function predict(o::BinaryStumpForest, x::VectorOb)
    mean(classify(stump, x) for stump in o.forest)
end
classify(o::BinaryStumpForest, x::VectorOb) = sign(predict(o, x))

for f in [:predict, :classify]
    @eval begin 
        function $f(o::BinaryStumpForest, x::AbstractMatrix, dim::Rows = Rows())
            mapslices(x -> $f(o, x), x, 2)
        end
        function $f(o::BinaryStumpForest, x::AbstractMatrix, dim::Cols)
            mapslices(x -> $f(o, x), x, 1)
        end
    end
end
















#-----------------------------------------------------------------------# Stump
struct Stump{T <: NBClassifier} <: ExactStat{(1, 0)}
    root::T 
    split_locs::Vector{Float64}
    info_gains::Vector{Float64}
    probs::Vector{Float64}
end
Stump(p::Integer, T::Type, b::Int=10) = Stump(NBClassifier(p, T, b), zeros(p), zeros(p), zeros(p))

function fit!(o::Stump, xy, γ)
    fit!(o.root, xy, γ)
end

nparams(o::Stump) = length(split_locs)

function get_splits!(o::Stump)
    base_impurity = impurity(o.root)
    for j in nparams(o)
        hist_vec = o.root[j]
        split_locs[j] = mean(mean(h) for h in hist_vec)

    end
end

function impurity(v::Vector{<:Hist})
    n = nobs.(v)
    entropy2(nobs.(v) ./ sum(n))
end



#-----------------------------------------------------------------------# StumpForest

"""
    StumpForest(p::Int, T::Type; b=10, nt=100, np=3)

Online random forest with stumps (one-node trees) where:

- `p` is the number of predictors. 
- `b` is the number of histogram bins to estimate conditional densities.
- `nt` is the number of trees in the forest.
- `np` is the number predictors to give to each stump.

# Example 

    x = randn(10_000, 10)
    y = x * linspace(-1, 1, 10) .> 0 

    s = Series((x, y), StumpForest(10, Bool))

    # prediction accuracy
    mean(y .== classify(s.stats[1], x))
"""
struct StumpForest{T <: NBClassifier} <: ExactStat{(1,0)}
    forest::Vector{T}
    inputs::Matrix{Int}  # NBClassifier i gets: x[inputs[i]]
end

# b  = size of histogram
# nt = number of trees in forest
# np = number of predictors to give each tree
function StumpForest(p::Integer, T::Type; b = 10, nt = 100, np = 3)
    forest = [NBClassifier(np, T, b) for i in 1:nt]
    inputs = zeros(Int, np, nt)
    for j in 1:nt 
        inputs[:, j] = sample(1:p, np; replace = false)
    end
    StumpForest(forest, inputs)
end

Base.keys(o::StumpForest) = keys(o.forest[1])

function fit!(o::StumpForest, xy, γ)
    x, y = xy
    i = rand(1:length(o.forest))
    fit!(o.forest[i], (@view(x[o.inputs[:, i]]), y), γ)
end

function predict(o::StumpForest, x::VectorOb)
    out = predict(o.forest[1], x[o.inputs[:, 1]])
    for i in 2:length(o.forest)
        @views smooth!(out, predict(o.forest[i], x[o.inputs[:, i]]), 1/i)
    end
    out
end
function classify(o::StumpForest, x::VectorOb)
    _, i = findmax(predict(o, x))
    keys(o)[i]
end

for f in [:predict, :classify]
    @eval begin
        function $f(o::StumpForest, x::AbstractMatrix, dim::Rows = Rows())
            mapslices(x -> $f(o, x), x, 2)
        end
        function $f(o::StumpForest, x::AbstractMatrix, dim::Cols)
            mapslices(x -> $f(o, x), x, 1)
        end
    end
end