# ============================================================
# run_all_cases.jl
# ============================================================
using Pkg
# Pkg.add("Jutul")
# Pkg.add("JutulDarcy")
# Pkg.add("GLMakie")
# Pkg.add("JLD2")
# Pkg.add("CSV")
# Pkg.add("DataFrames")


using Jutul, JutulDarcy
using JLD2, CSV, DataFrames
import Printf: @printf

const ROOT = raw"D:\convergance_tests\edge_cases_permeability"            # где лежат run_*
const OUT_CSV = joinpath(ROOT, "tstep_summary.csv")        # итоговый файл
const INITIAL_DTS = 40:5:70                              # диапазон первых шагов, сут
const N_MINISTEP_COLS = 30                                 # макс. столбцов под мини-шаги
const RUN_RX = r"^run_\d{3}"
day = si_unit(:day)

# ---------- ф-ция: разобрать первый лог и вернуть вектор Δt (сут) ----------
function read_ministeps(log_dir::String)
    jld_files = filter(f -> endswith(f, ".jld2"),
                       sort(readdir(log_dir; join=true)))
    isempty(jld_files) && return Float64[]
    data = load(jld_files[1])                 # первый лог
    ms = get(data["report"], :ministeps, [])
    dt_days = [m[:dt] / 86400 for m in ms if m[:success]]
    return dt_days
end

# ---------- ф-ция: прогнать один data-файл с данным initial_dt ----------
function run_case(data_path::String; initial_dt_day::Int)
    case = setup_case_from_data_file(data_path)

    result = simulate_reservoir(
        case;
        info_level             = 0,
        output_substates       = true,
        output_path            = dirname(data_path) * "\\!logs",
        max_nonlinear_iterations = 15,
        timestep_max_increase  = 100.0,
        timestep_max_decrease  = 0.01,
        max_timestep           = 365day * 5,
        min_timestep           = 1.0e-6,
        timesteps              = :none,
        initial_dt             = initial_dt_day * day,
    )
    return
end

# ---------- подготовка CSV (заголовок) ----------
col_names = vcat(
    ["run_dir", "initial_dt"],
    ["dt$(i)" for i in 1:N_MINISTEP_COLS],
)
open(OUT_CSV, "w") do io
    println(io, join(col_names, ','))
end

# ---------- основной двойной цикл ----------
run_dirs = filter(d ->
    isdir(d) && occursin(RUN_RX, basename(d)),
    readdir(ROOT; join=true, sort=true)
)
total_runs = length(run_dirs) * length(INITIAL_DTS)
idx = 0

for rd in run_dirs
    data_file = first(filter(f -> endswith(f, ".DATA"), readdir(rd; join=true)))
    logs_dir  = rd * "\\!logs"
    mkpath(logs_dir)

    for dt_first in INITIAL_DTS
        global idx += 1
        @printf "[%4d / %4d]  %-15s  initial_dt = %3d day(s) ... " idx total_runs basename(rd) dt_first
        # чистим логи, если остались
        for f in readdir(logs_dir; join=true)
            isfile(f) && rm(f; force=true)
        end

        # --- расчёт ---
        dts = Float64[]                          # ← объявляем заранее
        try
            run_case(data_file; initial_dt_day = dt_first)
            dts = read_ministeps(logs_dir)
            @printf("OK  (ministeps: %d)\n", length(dts))
        catch err
            @printf("FAIL  (%s)\n", sprint(showerror, err))
            dts = Float64[]                      # гарантируем определённость
        end


        # --- запись строки в CSV ---
        padded = vcat([basename(rd), string(dt_first)], string.(dts))
        length(padded) < length(col_names) && append!(padded, fill("", length(col_names) - length(padded)))
        open(OUT_CSV, "a") do io
            println(io, join(padded, ','))
        end
    end
end

println("\nГотово  →  ", OUT_CSV)
