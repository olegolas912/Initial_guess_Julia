# ============================================================
# run_bhp_tstep_all_logs.jl
# Запускает все кейсы BHP_* и пишет разбиение ВСЕХ шагов в CSV
# ============================================================
using Pkg
env = joinpath(@__DIR__, "original_env")
Pkg.activate(env; shared=false)
Pkg.precompile()
pkg_path = raw"D:\julia-1.11.5\JuliaDepot\dev"
Pkg.develop(path=joinpath(pkg_path, "Jutul"))
Pkg.develop(path=joinpath(pkg_path, "JutulDarcy"))
Pkg.instantiate()

using Jutul, JutulDarcy
using JLD2, Printf

# -------------------- настройки --------------------
const ROOT = raw"D:\convergance_tests\cases_bhp_one_year"     # ← корень с папками BHP_***
const OUT_CSV = joinpath(ROOT, "tstep_all_logs.csv") # итоговый CSV
const RUN_RX = r"^BHP_\d{3}$"
const DATA_RX = r"_TSTEP_(\d+)_(\d+)\.DATA$"         # извлекаем a и b
const N_MINISTEP_COLS = 15                           # макс. столбцов с мини-шагами
day = si_unit(:day)

# -------------------- утилиты ----------------------
function read_ministeps(j2::AbstractString)::Vector{Float64}
    d = load(j2)
    if haskey(d, "TSTEP")
        # старый формат: вектор Δt (уже в сутках)
        return collect(d["TSTEP"])
    elseif haskey(d, "report")
        ms = get(d["report"], :ministeps, [])
        return [m[:dt] / 86400 for m in ms if get(m, :success, true)]
    else
        return Float64[]
    end
end

function list_log_files(logs_dir::AbstractString)
    # "jutul_1.jld2", "jutul_2.jld2", ...
    files = filter(f -> endswith(f, ".jld2"), readdir(logs_dir; join=true))
    sort(files; by = f -> tryparse(Int, match(r"jutul_(\d+)\.jld2$", basename(f)).captures[1]))
end

# -------------------- CSV заголовок ----------------
col_names = vcat(["bhp_dir","data_file","a","b","log_idx","n_ministeps"],
                 ["dt$(i)" for i=1:N_MINISTEP_COLS])
open(OUT_CSV, "w") do io
    println(io, join(col_names, ','))
end

# -------------------- основной цикл ----------------
run_dirs = filter(d -> isdir(d) && occursin(RUN_RX, basename(d)),
                  readdir(ROOT; join=true, sort=true))

for rd in run_dirs
    data_files = filter(f -> isfile(f) && occursin(DATA_RX, basename(f)),
                        readdir(rd; join=true, sort=true))

    for data_path in data_files
        m = match(DATA_RX, basename(data_path))
        a = parse(Int, m.captures[1]); b = parse(Int, m.captures[2])

        logs_dir = joinpath(rd, "!logs")
        isdir(logs_dir) || mkpath(logs_dir)
        # очистка логов перед запуском
        for f in readdir(logs_dir; join=true)
            isfile(f) && rm(f; force=true)
        end

        # ---- расчёт ----
        @printf("%-12s  %-30s  TSTEP=(%3d,%3d) ... ",
                basename(rd), basename(data_path), a, b)
        flush(stdout)

        ok = true
        try
            case = setup_case_from_data_file(data_path)
            simulate_reservoir(case;
                info_level               = 0,
                output_substates         = true,
                output_path              = logs_dir,
                timesteps                = :none,          # адаптивный шаг
                initial_dt               = a*day,          # стартуем с первого шага из файла
                max_nonlinear_iterations = 15,
                timestep_max_increase    = 100.0,
                timestep_max_decrease    = 0.01,
                max_timestep             = 365day*5,
                min_timestep             = 1e-6
            )
        catch err
            ok = false
            @printf("FAIL (%s)\n", sprint(showerror, err))
        end

        # ---- сбор логов ----
        rows_written = 0
        if ok
            logs = list_log_files(logs_dir)
            for lf in logs
                dts = read_ministeps(lf)
                log_idx = parse(Int, match(r"jutul_(\d+)\.jld2$", basename(lf)).captures[1])
                padded = vcat([basename(rd), basename(data_path), string(a), string(b),
                               string(log_idx), string(length(dts))],
                              string.(dts))
                length(padded) < length(col_names) && append!(padded, fill("", length(col_names)-length(padded)))
                open(OUT_CSV, "a") do io
                    println(io, join(padded, ','))
                end
                rows_written += 1
            end
        end

        @printf("OK (logs: %d)\n", rows_written)
        flush(stdout)
    end
end

println("\nГотово → ", OUT_CSV)
