using Pkg

Pkg.activate(raw"D:\Jutul_project\MsProject")

Pkg.develop(path=raw"D:\julia-1.11.5\JuliaDepot\dev\Jutul")
Pkg.develop(path=raw"D:\julia-1.11.5\JuliaDepot\dev\JutulDarcy")

Pkg.add("GLMakie")
Pkg.add("DelimitedFiles")
Pkg.add("HYPRE")
Pkg.add("LinearAlgebra")

Pkg.instantiate()
