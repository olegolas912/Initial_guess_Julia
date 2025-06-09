import Pkg
Pkg.activate("D:/Jutul_project/MsProject");
using Revise, MsProject
using Jutul, JutulDarcy, GLMakie, DelimitedFiles, HYPRE

methods(Jutul.simulator_storage)

case = setup_case_from_data_file(joinpath("D:\\DeepField\\open_data\\egg", "Egg_Model_ECL.DATA"))
@time res_result = simulate_reservoir(case, timesteps=:none)
ws, states, t = res_result
