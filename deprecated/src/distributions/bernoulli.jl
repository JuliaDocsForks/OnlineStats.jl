#-------------------------------------------------------# Type and Constructors
type FitBernoulli{W <: Weighting} <: DistributionStat
    d::Dist.Bernoulli
    p::Float64  # success probability
    n::Int64
    weighting::W
end

"""
`distributionfit(Dist, y, wgt)`

Track parametric estimates of distribution `Dist` using data `y` and weighting `wgt`.
"""
function distributionfit{T <: Integer}(::Type{Dist.Bernoulli}, y::AVec{T}, wgt::Weighting = default(Weighting))
    o = FitBernoulli(wgt)
    update!(o, y)
    o
end

FitBernoulli{T <: Integer}(y::AVec{T}, wgt::Weighting = default(Weighting)) =
    distributionfit(Dist.Bernoulli, y, wgt)

FitBernoulli(wgt::Weighting = default(Weighting)) =
    FitBernoulli(Dist.Bernoulli(0), 0., 0, wgt)


#---------------------------------------------------------------------# update!
function update!(obj::FitBernoulli, y::Integer)
    λ = weight(obj)
    obj.p = smooth(obj.p, (Float64(y)), λ)
    obj.d = Dist.Bernoulli(obj.p)
    obj.n += 1
    return
end