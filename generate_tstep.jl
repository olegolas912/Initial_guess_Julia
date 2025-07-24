module GenerateTSTEP

export write_tstep

using JLD2
using Printf

function write_tstep(path::AbstractString; tol=1e-6)
    data = load(path)
    ms = data["report"][:ministeps]
    dt = [m[:dt] / 86400 for m in ms if m[:success]]

    dt_fmt = [abs(round(d) - d) < tol ? Int(round(d)) : d for d in dt]

    println("TSTEP")
    print("   ")
    for d in dt_fmt
        d isa Int ? @printf("%d ", d) : @printf("%.3f ", d)
    end
    println("/")
    println("END")
end

end