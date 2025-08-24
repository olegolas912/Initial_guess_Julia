# ============================================================
# run_qinj_tstep_all_logs_parallel_retry.jl
# Параллельный запуск QINJ_* с авто-перезапуском задач
# при падении воркера. Без ретраев по самим кейсам.
# Порядок: QINJ_№ ↑, внутри — (a,b) ↑. CSV детерминированный.
# ============================================================

using Distributed
using Base.Threads: nthreads

# --- целевое число воркеров: из ENV JULIA_WORKERS, иначе CPU-1 ---
const TARGET_WORKERS = let s = get(ENV, "JULIA_WORKERS", "")
    s != "" ? parse(Int, s) : max(1, Sys.CPU_THREADS - 1)
end

# если уже есть воркеры (например, запуск с -p), добираем недостающее
if nworkers() < TARGET_WORKERS
    addprocs(TARGET_WORKERS - nworkers(); exeflags="--threads=auto")
end



# -------- ИНИЦИАЛИЗАЦИЯ НА ВСЕХ ПРОЦЕССАХ (ТОП-УРОВЕНЬ) --------
@everywhere begin
    using Pkg
    const ENV_PATH = joinpath(@__DIR__, "original_env")
    Pkg.activate(ENV_PATH; shared=false)
    const PKG_DEV = raw"D:\julia-1.11.5\JuliaDepot\dev"
    Pkg.develop(path=joinpath(PKG_DEV, "Jutul"))
    Pkg.develop(path=joinpath(PKG_DEV, "JutulDarcy"))
    Pkg.instantiate()

    using Jutul, JutulDarcy
    using JLD2, Printf, Dates

    const RUN_RX  = r"^QINJ_(\d{3})$"
    const DATA_RX = r"_TSTEP_(\d+)_(\d+)\.DATA$"
    const N_MINISTEP_COLS = 15
    const day = si_unit(:day)

    # ---------- тип задания ----------
    struct CaseTask
        qinj_dir::String
        data_path::String
        a::Int
        b::Int
    end

    # ---------- утилиты ----------
    function read_ministeps(j2::AbstractString)::Vector{Float64}
        d = load(j2)
        if haskey(d, "TSTEP")
            return collect(d["TSTEP"])
        elseif haskey(d, "report")
            ms = get(d["report"], :ministeps, [])
            return [m[:dt] / 86400 for m in ms if get(m, :success, true)]
        else
            return Float64[]
        end
    end

    function list_log_files(logs_dir::AbstractString)
        files = filter(f -> endswith(f, ".jld2"), readdir(logs_dir; join=true))
        sort!(files; by = f -> parse(Int, match(r"jutul_(\d+)\.jld2$", basename(f)).captures[1]))
        return files
    end

    # ---------- одиночный расчёт (без ретраев по кейсу) ----------
    function simulate_one_case(task::CaseTask)
        rd, data_path, a, b = task.qinj_dir, task.data_path, task.a, task.b
        logs_dir = joinpath(rd, "!logs", "TSTEP_$(a)_$(b)")
        isdir(logs_dir) || mkpath(logs_dir)
        for f in readdir(logs_dir; join=true)
            isfile(f) && rm(f; force=true)
        end

        rows = Vector{Vector{String}}()
        try
            case = setup_case_from_data_file(data_path)
            simulate_reservoir(case;
                info_level               = 0,
                output_substates         = true,
                output_path              = logs_dir,
                timesteps                = :none,
                initial_dt               = a*day,
                max_nonlinear_iterations = 15,
                timestep_max_increase    = 100.0,
                timestep_max_decrease    = 0.01,
                max_timestep             = 365day*5,
                min_timestep             = 1e-6
            )

            logs = list_log_files(logs_dir)
            for lf in logs
                dts = read_ministeps(lf)
                log_idx = parse(Int, match(r"jutul_(\d+)\.jld2$", basename(lf)).captures[1])
                fixed = vcat([basename(rd), basename(data_path), string(a), string(b),
                              string(log_idx), string(length(dts))],
                             string.(dts))
                needed = 6 + N_MINISTEP_COLS
                length(fixed) < needed && append!(fixed, fill("", needed - length(fixed)))
                push!(rows, fixed)
            end
        catch err
            err_row = [basename(rd), basename(data_path), string(a), string(b), "FAIL_CASE", sprint(showerror, err)]
            needed = 6 + N_MINISTEP_COLS
            length(err_row) < needed && append!(err_row, fill("", needed - length(err_row)))
            push!(rows, err_row)
        end
        return rows
    end
end
# -----------------------------------------------------------------

# ---- настройки мастера ----
const ROOT    = raw"D:\convergance_tests\inj_check_one_year"
const OUT_CSV = joinpath(ROOT, "tstep_all_logs_parallel.csv")

# собрать задания (на мастере), упорядочить
function build_tasks(root::AbstractString)::Vector{CaseTask}
    run_dirs = filter(d -> isdir(d) && occursin(RUN_RX, basename(d)),
                      readdir(root; join=true, sort=false))
    sort!(run_dirs; by = d -> parse(Int, match(RUN_RX, basename(d)).captures[1]))

    tasks = CaseTask[]
    for rd in run_dirs
        data_files = filter(f -> isfile(f) && occursin(DATA_RX, basename(f)),
                            readdir(rd; join=true, sort=false))
        sort!(data_files; by = f -> begin
            m = match(DATA_RX, basename(f))::RegexMatch
            (parse(Int, m.captures[1]), parse(Int, m.captures[2]))
        end)
        for f in data_files
            m = match(DATA_RX, basename(f))::RegexMatch
            a = parse(Int, m.captures[1]); b = parse(Int, m.captures[2])
            push!(tasks, CaseTask(rd, f, a, b))
        end
    end
    return tasks
end

# параллельный запуск с авто-перезапуском задач при падении воркера
function run_with_retries(tasks::Vector{CaseTask}; max_rounds::Int=3)
    pending_idxs = collect(1:length(tasks))
    results_map = Dict{Int, Vector{Vector{String}}}()
    round = 1
    while !isempty(pending_idxs) && round <= max_rounds
        local_tasks = tasks[pending_idxs]
        chunks = pmap(simulate_one_case, local_tasks; batch_size=1,
                      on_error = (ex, t) -> nothing)

        new_pending = Int[]
        for (idx, res) in zip(pending_idxs, chunks)
            if res === nothing
                push!(new_pending, idx)          # воркер умер → перезапустим на следующем круге
            else
                results_map[idx] = res
            end
        end
        pending_idxs = new_pending
        round += 1
    end

    # что осталось после max_rounds — считаем непреодолимой проблемой воркера
    for idx in pending_idxs
        t = tasks[idx]
        row = [basename(t.qinj_dir), basename(t.data_path), string(t.a), string(t.b), "FAIL_WORKER", ""]
        needed = 6 + N_MINISTEP_COLS
        length(row) < needed && append!(row, fill("", needed - length(row)))
        results_map[idx] = [row]
    end

    all_rows = Vector{Vector{String}}()
    for idx in sort!(collect(keys(results_map)))
        append!(all_rows, results_map[idx])
    end
    return all_rows
end

# запись CSV с сортировкой по QINJ№, a, b, log_idx/FAIL*
function write_csv(rows::Vector{Vector{String}}, out_path::AbstractString)
    sort!(rows; by = r -> begin
        m = match(RUN_RX, r[1]); qn = m === nothing ? 10^9 : parse(Int, m.captures[1])
        a = tryparse(Int, r[3]); a === nothing && (a = 10^9)
        b = tryparse(Int, r[4]); b === nothing && (b = 10^9)
        li = occursin("FAIL", r[5]) ? typemax(Int) : parse(Int, r[5])
        (qn, a, b, li)
    end)

    col_names = vcat(["bhp_dir","data_file","a","b","log_idx","n_ministeps"],
                     ["dt$(i)" for i=1:N_MINISTEP_COLS])

    open(out_path, "w") do io
        println(io, join(col_names, ','))
        for r in rows
            println(io, join(r[1:length(col_names)], ','))
        end
    end
end

# -------------------- main ------------------------
function main()
    tasks = build_tasks(ROOT)
    @info "План запуска" tasks=length(tasks) workers=nworkers() procs=nprocs() cpu_threads=Sys.CPU_THREADS julia_threads=nthreads()
    rows = run_with_retries(tasks; max_rounds=3)
    write_csv(rows, OUT_CSV)
    @info "Готово → $OUT_CSV"
end

main()
