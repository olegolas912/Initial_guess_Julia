using Pkg

env = joinpath(@__DIR__, "original_env")
Pkg.activate(env; shared=false)
Pkg.precompile()
pkg_path = raw"D:\julia-1.11.5\JuliaDepot\dev"
Pkg.develop(path=joinpath(pkg_path, "Jutul"))
Pkg.develop(path=joinpath(pkg_path, "JutulDarcy"))
Pkg.instantiate()
Pkg.add("GLMakie")
Pkg.add("JLD2")


using Jutul, JutulDarcy, GLMakie

include(joinpath(@__DIR__, "generate_tstep.jl"))
using .GenerateTSTEP

#разбивает на шаги schedule
tsteps(n, first) = begin
    r = 365 * 5 - first
    b, e = r ÷ (n - 1), r % (n - 1)
    ts = vcat(first, fill(b + 1, e), fill(b, (n - 1) - e))
    println(join(ts, " "))
end
tsteps(2, 400)

365 * 5 / 4

case = setup_case_from_data_file(joinpath("D:\\convergance_tests\\orig-Copy", "Egg_Model_ECL.DATA"))
# @time result = simulate_reservoir(case, timesteps=:none, output_substates=true, cutting_criterion=nothing)
day = si_unit(:day)
@time result = simulate_reservoir(case, info_level=2, output_path="D:\\convergance_tests\\orig-Copy\\!logs",
    timesteps=:none, max_nonlinear_iterations=15,
    timestep_max_increase=100.0, timestep_max_decrease=0.01, max_timestep=315360000, min_timestep=1.0e-6,
    initial_dt=400day)

for f in filter(x -> endswith(x, ".jld2"), readdir("D:/convergance_tests/orig-Copy/!logs"; join=true))
    println("\nФайл ", f)
    write_tstep(f)
end
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

for (name, series) in result.wells.wells
    oil_rate = -series[:orat] .* 86400
    liq_rate = -series[:lrat] .* 86400
    println("Дебит нефти: $oil_rate")
    println("Дебит жидкости: $liq_rate")
end

t = result.wells.time
t = vcat(0.0, t)
dt = diff(t)

cum_prod = Dict{Symbol,Dict{Symbol,Vector{Float64}}}()

for (name, series) in result.wells.wells
    qo = -series[:orat] .* dt
    ql = -series[:lrat] .* dt

    cum_oil = cumsum(qo)
    cum_liq = cumsum(ql)

    cum_prod[name] = Dict(:cum_orat => cum_oil,
        :cum_lrat => cum_liq)
end

println(cum_prod[:PROD2][:cum_orat])
println(cum_prod[:PROD2][:cum_lrat])

plot_reservoir_simulation_result(case.model, result)