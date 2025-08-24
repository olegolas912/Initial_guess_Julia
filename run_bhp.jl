# ============================================================
# run_bhp_tstep_all_logs.jl
# Запускает все кейсы QINJ_* по возрастанию номера и
# внутри каждого — файлы *_TSTEP_a_b.DATA по (a,b) ↑
# Пишет разбиение ВСЕХ шагов в CSV
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
const ROOT = raw"D:\convergance_tests\inj_check_two_years"     # ← корень с папками QINJ_***
const OUT_CSV = joinpath(ROOT, "tstep_all_logs.csv")          # итоговый CSV
const RUN_RX  = r"^QINJ_(\d{3})$"
const DATA_RX = r"_TSTEP_(\d+)_(\d+)\.DATA$"                  # извлекаем a и b
const N_MINISTEP_COLS = 15                                    # макс. столбцов с мини-шагами
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
    sort!(files; by = f -> parse(Int, match(r"jutul_(\d+)\.jld2$", basename(f)).captures[1]))
    return files
end

# -------------------- CSV заголовок ----------------
col_names = vcat(["bhp_dir","data_file","a","b","log_idx","n_ministeps"],
                 ["dt$(i)" for i=1:N_MINISTEP_COLS])
open(OUT_CSV, "w") do io
    println(io, join(col_names, ','))
end

# -------------------- сбор и сортировка кейсов -----
# Берём папки QINJ_*** и сортируем по числу ↑
run_dirs = filter(d -> isdir(d) && occursin(RUN_RX, basename(d)),
                  readdir(ROOT; join=true, sort=false))
sort!(run_dirs; by = d -> parse(Int, match(RUN_RX, basename(d)).captures[1]))

# -------------------- основной цикл ----------------
for rd in run_dirs
    # Собираем файлы *_TSTEP_a_b.DATA и сортируем по (a,b) ↑
    data_files = filter(f -> isfile(f) && occursin(DATA_RX, basename(f)),
                        readdir(rd; join=true, sort=false))
    sort!(data_files; by = f -> begin
        m = match(DATA_RX, basename(f))::RegexMatch
        (parse(Int, m.captures[1]), parse(Int, m.captures[2]))
    end)

    for data_path in data_files
        m = match(DATA_RX, basename(data_path))::RegexMatch
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
                timestep_max_increase    = 10000.0,
                timestep_max_decrease    = 0.0001,
                max_timestep             = 365day*10,
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
