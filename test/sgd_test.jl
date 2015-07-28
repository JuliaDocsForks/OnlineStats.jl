module SGDTest

using FactCheck, OnlineStats, Distributions, Compat

function convertLogisticY(xβ)
    prob = OnlineStats.invlink(LogisticLink(), xβ)
    @compat Float64(rand(Bernoulli(prob)))
end

facts("SGD") do

    const n = 1_000_000
    const p = 50
    x = randn(n, p)
    β = collect(1.:p)

    atol = 0.5
    rtol = 0.1

    context("OLS") do
        y = x*β + randn(n)
        o = OnlineStats.SGD(x, y)
        @fact coef(o) - β => roughly(zeros(p), atol = atol, rtol = rtol)
        @fact predict(o, ones(p)) => roughly(1.0 * sum(β), atol = atol, rtol = rtol)

        # updatebatch!
        o = OnlineStats.SGD(p)
        OnlineStats.onlinefit!(o, 500, x, y; batch = true)
        @fact coef(o) - β => roughly(zeros(p), atol = atol, rtol = rtol)

        # ridge regression
        # repeat same data in first 2 variables
        # it should give 1.5 for β₁ and β₂ after reg (even though actual betas are 1 and 2)
        x[:,2] = x[:,1]
        y = x * β
        β2 = vcat(1.5, 1.5, β[3:end])
        o = SGD(x, y; reg = L2Reg(0.01))
        OnlineStats.DEBUG(o, ": β=", β2)
        @fact coef(o)[1] => roughly(1.5, atol = atol, rtol = rtol)
        @fact coef(o)[2] => roughly(1.5, atol = atol, rtol = rtol)

        # lasso
        β = collect(1.:p)
        β[10:end] = 0.0
        y = x*β + randn(n)
        o = OnlineStats.SGD(x, y; reg = OnlineStats.L1Reg(0.01))

        @fact statenames(o) => [:β, :nobs]
        @fact state(o)[1] => coef(o)
        @fact state(o)[2] => nobs(o)
    end

    context("Logistic") do
        β = (collect(1.:p) - p/2) / p
        y = map(convertLogisticY, x * β)

        o = SGD(x, y, StochasticWeighting(.51); link=LogisticLink(), loss=LogisticLoss())
        OnlineStats.DEBUG(o, ": β=", β)
        @fact coef(o) - β => roughly(zeros(p), atol = 0.5, rtol = 0.1)

        # updatebatch!
        o = SGD(p, OnlineStats.StochasticWeighting(.51); link=OnlineStats.LogisticLink(), loss=OnlineStats.LogisticLoss())
        OnlineStats.onlinefit!(o, 100, x, y; batch = true)
        @fact coef(o) - β => roughly(zeros(p), atol = 0.5, rtol = 0.1) "batch version"

        # logistic l2
        # repeat same data in first 2 variables
        # it should give 1.5 for β₁ and β₂ after reg (even though actual betas are 1 and 2)
        β = collect(1.:10)
        x = x[:, 1:10]
        y = map(convertLogisticY, x * β)
        x[:,2] = x[:,1]
        o = SGD(x, y; link=LogisticLink(), loss=LogisticLoss(), reg=L2Reg(0.00001))
        @fact coef(o)[1] => roughly(1.5, atol = 0.8, rtol = 0.2)
        @fact coef(o)[2] => roughly(1.5, atol = 0.8, rtol = 0.2)
    end

    context("Quantile Regression") do
        x = randn(n, p)
        β = collect(1.:p)
        y = x * β + randn(n)

        o = SGD(x, y; loss = QuantileLoss())
        @fact coef(o) => roughly(β, atol = 0.5, rtol = 0.1)

        o = SGD(hcat(ones(n), x), y; loss = QuantileLoss(.8))
        @fact coef(o) => roughly(vcat(quantile(Normal(), .8), β), atol = 0.5, rtol = 0.1)

        # updatebatch!
        o = OnlineStats.SGD(p, OnlineStats.StochasticWeighting(.3, .01); loss=OnlineStats.QuantileLoss())
        OnlineStats.onlinefit!(o, 10, x, y; batch = true)
        @fact coef(o) => roughly(β, atol = 0.5, rtol = 0.1) "batch version"

        ϵdist = Normal(0, 5)
        y = x * β + rand(ϵdist, n)
        o = SGD(hcat(ones(n), x), y; loss = QuantileLoss(.8))
        @fact coef(o) => roughly(vcat(quantile(ϵdist, .8), β), atol = 0.5, rtol = 0.1)
    end
end


end #module