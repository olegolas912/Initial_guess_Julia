import Pkg;
Pkg.activate("D:/Jutul_project/MsProject");
using Revise, MsProject
using Jutul, JutulDarcy, GLMakie, DelimitedFiles, HYPRE

methods(Jutul.simulator_storage)

egg_dir = JutulDarcy.GeoEnergyIO.test_input_file_path("EGG")
case = setup_case_from_data_file(joinpath(egg_dir, "EGG.DATA"))
ws, states = simulate_reservoir(case, output_substates=true)