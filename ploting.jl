
plot_reservoir_simulation_result(case.model, result)
#------------------------------
using JLD2, Printf

file = "D:/convergance_tests/orig-Copy/!logs/jutul_1.jld2"
data = load(file)
ms = data["report"][:ministeps]
dt_days = [m[:dt] / 86400 for m in ms if m[:success]]
tol = 1e-6
fmt = [abs(round(d) - d) < tol ? Int(round(d)) : d for d in dt_days]

println("TSTEP")
for d in fmt
    d isa Int ? @printf("%d ", d) : @printf("%.3f ", d)
end
println("/")
println("END")
#------------------------------

plot_reservoir_simulation_result(case.model, result)

#------------------------------

for (name, series) in result.wells.wells
    oil_rate = -series[:orat] .* 86400
    liq_rate = -series[:lrat] .* 86400
    println("Дебит нефти: $oil_rate")
    println("Дебит жидкости: $liq_rate")
end

#------------------------------

function fluids(result; time0=0.0, rate_unit_factor=1.0)
    t = vcat(float(time0), Float64.(result.wells.time))
    dt = diff(t)
    N = length(dt)

    total_oil = 0.0
    total_wat = 0.0
    total_inj = 0.0

    cum_oil = Dict{String,Float64}()
    cum_wat = Dict{String,Float64}()
    cum_inj = Dict{String,Float64}()

    all_lrat_pos = Float64[]
    all_lrat_neg = Float64[]

    for (name, series) in result.wells.wells
        orat = rate_unit_factor .* Float64.(series[:orat])
        lrat = rate_unit_factor .* Float64.(series[:lrat])

        length(orat) == N || error("orat length $(length(orat)) != $N for $name")
        length(lrat) == N || error("lrat length $(length(lrat)) != $N for $name")
        orat = -orat
        wrate = similar(lrat)
        irate = similar(lrat)
        @inbounds @simd for i in eachindex(lrat)
            v = lrat[i]
            if v > 0.0
                irate[i] = v
                wrate[i] = 0.0
            else
                irate[i] = 0.0
                wrate[i] = -v
            end
        end

        oil_step = orat .* dt
        wat_step = wrate .* dt
        inj_step = irate .* dt

        co = sum(oil_step)
        cw = sum(wat_step)
        ci = sum(inj_step)

        cum_oil[string(name)] = co
        cum_wat[string(name)] = cw
        cum_inj[string(name)] = ci

        total_oil += co
        total_wat += cw
        total_inj += ci

        append!(all_lrat_pos, lrat[lrat.>0.0])
        append!(all_lrat_neg, lrat[lrat.<0.0])
    end

    return (; total_oil, total_wat, total_inj,
        cum_oil, cum_wat, cum_inj,
        all_lrat_pos, all_lrat_neg,
        dt)
end

function print_fluids(f)
    println("ИТОГИ: нефть=", f.total_oil, " м³; вода(добыча)=", f.total_wat, " м³; вода(закачка)=", f.total_inj, " м³")
    for n in sort!(collect(keys(f.cum_oil)))
        println("  ", n, ": нефть=", f.cum_oil[n], " м³; вода=", f.cum_wat[n], " м³; закачка=", f.cum_inj[n], " м³")
    end
end

f = fluids(result; time0=0.0, rate_unit_factor=1.0)
print_fluids(f)

#------------------------------
