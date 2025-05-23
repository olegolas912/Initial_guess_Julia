using Pkg

env = joinpath(@__DIR__, "original_env")
Pkg.activate(env; shared=false)
Pkg.precompile()
pkg_path = raw"D:\julia-1.11.5\JuliaDepot\dev"
Pkg.develop(path=joinpath(pkg_path, "Jutul"))
Pkg.develop(path=joinpath(pkg_path, "JutulDarcy"))
Pkg.instantiate()

using Jutul, JutulDarcy

egg_dir = JutulDarcy.GeoEnergyIO.test_input_file_path("EGG")
case = setup_case_from_data_file(joinpath(egg_dir, "EGG.DATA"))

@time ws, states = simulate_reservoir(case; output_substates=true)

println("\n✓ Расчёт завершён.  Доступны переменные `ws`, `states`.")
