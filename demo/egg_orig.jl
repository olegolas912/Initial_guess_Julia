using Pkg

env = joinpath(@__DIR__, "original_env")
Pkg.activate(env; shared=false)
Pkg.precompile()
pkg_path = raw"D:\julia-1.11.5\JuliaDepot\dev"
Pkg.develop(path=joinpath(pkg_path, "Jutul"))
Pkg.develop(path=joinpath(pkg_path, "JutulDarcy"))
Pkg.instantiate()

using Jutul, JutulDarcy

case = setup_case_from_data_file(joinpath("D:\\DeepField\\open_data\\egg", "Egg_Model_ECL.DATA"))

@time ws, states = simulate_reservoir(case, timesteps=:none, output_substates=true, cutting_criterion=nothing)

println("\n✓ Расчёт завершён.  Доступны переменные `ws`, `states`.")
