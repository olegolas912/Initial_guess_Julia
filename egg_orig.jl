using Pkg

env = joinpath(@__DIR__, "original_env")
Pkg.activate(env; shared=false)
Pkg.precompile()
pkg_path = raw"D:\julia-1.11.5\JuliaDepot\dev"
Pkg.develop(path=joinpath(pkg_path, "Jutul"))
Pkg.develop(path=joinpath(pkg_path, "JutulDarcy"))
Pkg.instantiate()

using Pkg
Pkg.add("Jutul")
Pkg.add("JutulDarcy")
Pkg.add("GLMakie")
Pkg.add("JLD2")

using Jutul, JutulDarcy

include(joinpath(@__DIR__, "generate_tstep.jl"))
using .GenerateTSTEP

tsteps(n, first) = begin
    r = 365 * 5 - first
    b, e = r ÷ (n - 1), r % (n - 1)
    ts = vcat(first, fill(b + 1, e), fill(b, (n - 1) - e))
    println(join(ts, " "))
end
tsteps(2, 400)

day = si_unit(:day)
case = setup_case_from_data_file(joinpath("D:\\MsProject", "Egg_Model_ECL.DATA"))
# @time result = simulate_reservoir(case, timesteps=:none, output_substates=true, cutting_criterion=nothing)
@time result = simulate_reservoir(case, info_level=0, output_path="D:\\t_nav_models\\egg\\!logs",
    timesteps=:none, max_nonlinear_iterations=15,
    timestep_max_increase=100.0, timestep_max_decrease=0.01, max_timestep=315360000, min_timestep=1.0e-6,
    initial_dt=365day)

for f in filter(x -> endswith(x, ".jld2"), readdir("D:\\t_nav_models\\egg\\!logs"; join=true))
    println("\nФайл ", f)
    write_tstep(f)
end

for f in readdir(raw"D:\\t_nav_models\\egg\\!logs"; join=true)
    isfile(f) && rm(f)
end

function simulation(data_file;
                    info_level               = 0,
                    timesteps                = :none,
                    max_nonlinear_iterations = 15,
                    timestep_max_increase    = 100.0,
                    timestep_max_decrease    = 0.01,
                    max_timestep             = 315_360_000,
                    min_timestep             = 1.0e-6,
                    initial_dt               = 55*si_unit(:day))
    logs_dir = joinpath(dirname(data_file), "!logs")
    isdir(logs_dir) || mkpath(logs_dir)

    case   = setup_case_from_data_file(data_file)

    @time result = simulate_reservoir(case;
        info_level,
        output_path           = logs_dir,
        timesteps,
        max_nonlinear_iterations,
        timestep_max_increase,
        timestep_max_decrease,
        max_timestep,
        min_timestep,
        initial_dt)

    show(result); println()                     # печать сводки СРАЗУ после расчёта

    for f in filter(endswith(".jld2"), readdir(logs_dir; join = true))
        println("\nФайл ", f)
        write_tstep(f)                          # отчёты TSTEP – ПОСЛЕДНИЕ в выводе
    end

    for f in readdir(logs_dir; join = true)
        isfile(f) && rm(f)
    end

    return nothing                              # ничего не печатается после TSTEP
end

simulation(raw"D:\\convergance_tests\\bhp_check_one_year\\BHP_390\\Egg_Model_ECL.DATA")