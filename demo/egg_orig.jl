using Pkg


env = joinpath(@__DIR__, "original_env")
Pkg.activate(env; shared=false)
Pkg.precompile()
pkg_path = raw"D:\julia-1.11.5\JuliaDepot\dev"
Pkg.develop(path=joinpath(pkg_path, "Jutul"))
Pkg.develop(path=joinpath(pkg_path, "JutulDarcy"))
Pkg.instantiate()
Pkg.add("GLMakie")

using Jutul, JutulDarcy, GLMakie

# case = setup_case_from_data_file(joinpath("D:\\DeepField\\open_data\\egg", "Egg_Model_ECL.DATA"))
case = setup_case_from_data_file(joinpath("D:\\convergance_tests\\orig - Copy", "Egg_Model_ECL.DATA"))

# @time result = simulate_reservoir(case, timesteps=:none, output_substates=true, cutting_criterion=nothing)
@time result = simulate_reservoir(case)
plot_reservoir_simulation_result(case.model, result)