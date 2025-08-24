using JLD2
using Printf

# Папка с *.jld2 логами
DIR = raw"D:\convergance_tests\inj_check_one_year\QINJ_120\!logs"

function process_logs(dir::AbstractString; outname::AbstractString="jutul_ministeps_all.csv")
    files = sort(filter(f -> endswith(lowercase(f), ".jld2"),
                        readdir(dir; join=true)))

    header = [
        "step","file","internal_step","ministep","attempts","accepted_attempt","dt",
        "linear_acc","linear_all","linear_wasted",
        "newton_acc","newton_all","newton_wasted",
        "linearizations_acc","linearizations_all","linearizations_wasted",
        "precond_acc","precond_all","precond_wasted"
    ]

    outpath = joinpath(dir, outname)

    result = open(outpath, "w") do io
        println(io, join(header, ","))

        # агрегаты
        tot_ms = 0
        nsteps = length(files)
        sum_new_all = 0; sum_new_w = 0
        sum_linits_all = 0; sum_linits_w = 0
        sum_linz_all = 0; sum_linz_w = 0
        sum_prec_all = 0; sum_prec_w = 0

        toint(x) = try x === nothing ? 0 : Int(round(x)) catch; 0 end
        getstat(a, k) = begin
            st = (a isa AbstractDict && haskey(a, :stats)) ? a[:stats] : nothing
            if st === nothing
                0
            elseif st isa NamedTuple
                k in propertynames(st) ? something(getfield(st, k), 0) : 0
            elseif st isa AbstractDict
                get(st, k, 0)
            else
                try getfield(st, k) catch; 0 end
            end
        end

        for (i, f) in enumerate(files)
            root = try
                JLD2.load(f)
            catch e
                @warn "Не удалось прочитать файл" file=f error=e
                continue
            end

            rep = (root isa AbstractDict && haskey(root, "report") && root["report"] isa AbstractDict) ?
                  root["report"] : Dict{Symbol,Any}()
            ministeps = (haskey(rep, :ministeps) ? rep[:ministeps] : Any[])
            internal = haskey(root, "step") ? root["step"] : i

            # группируем попытки до success=true
            groups = Vector{Vector{Any}}()
            cur = Vector{Any}()
            for a in ministeps
                push!(cur, a)
                succ = (a isa AbstractDict) ? get(a, :success, false) : false
                if succ === true
                    push!(groups, cur)
                    cur = Vector{Any}()
                end
            end

            for (j, g) in enumerate(groups)
                tot_ms += 1
                acc = g[end]
                dt = (acc isa AbstractDict && haskey(acc, :dt)) ? acc[:dt] : NaN

                # ВСЕ попытки (внимание на пробел перед `for` 👇)
                linits_all = sum(toint(getstat(a, :linear_iterations))              for a in g)  # Linear solver iters
                new_all    = sum(toint(getstat(a, :newtons))                         for a in g)  # Newton
                linz_all   = sum(toint(getstat(a, :linearizations))                  for a in g)  # Linearizations
                prec_all   = sum(toint(getstat(a, :linear_solve_precond_iterations)) for a in g)  # Precond apply

                # Принятая попытка
                linits_acc = toint(getstat(acc, :linear_iterations))
                new_acc    = toint(getstat(acc, :newtons))
                linz_acc   = toint(getstat(acc, :linearizations))
                prec_acc   = toint(getstat(acc, :linear_solve_precond_iterations))

                linits_w = linits_all - linits_acc
                new_w    = new_all    - new_acc
                linz_w   = linz_all   - linz_acc
                prec_w   = prec_all   - prec_acc

                # Копим тоталы
                sum_linits_all += linits_all; sum_linits_w += linits_w
                sum_new_all    += new_all;    sum_new_w    += new_w
                sum_linz_all   += linz_all;   sum_linz_w   += linz_w
                sum_prec_all   += prec_all;   sum_prec_w   += prec_w

                row = [
                    string(i),
                    basename(f),
                    string(internal),
                    string(j),
                    string(length(g)),
                    string(length(g)),
                    @sprintf("%.6g", dt),
                    string(linits_acc), string(linits_all), string(linits_w),
                    string(new_acc),    string(new_all),    string(new_w),
                    string(linz_acc),   string(linz_all),   string(linz_w),
                    string(prec_acc),   string(prec_all),   string(prec_w)
                ]
                println(io, join(row, ","))
            end
        end

        (
            nsteps      = nsteps,
            tot_ms      = tot_ms,
            newton        = (total=sum_new_all,    wasted=sum_new_w),
            linear_solver = (total=sum_linits_all, wasted=sum_linits_w),
            linearization = (total=sum_linz_all,   wasted=sum_linz_w),
            precond_apply = (total=sum_prec_all,   wasted=sum_prec_w),
            outpath     = outpath
        )
    end

    # Сверка с jutul-формой
    @printf("\nCSV сохранён в: %s\n", result.outpath)
    @printf("Totals across %d steps, %d ministeps:\n", result.nsteps, result.tot_ms)
    @printf("  Newton         : total %d (wasted %d) | avg/step %.3f  avg/ministep %.4f\n",
            result.newton.total, result.newton.wasted,
            result.newton.total / max(result.nsteps, 1),
            result.newton.total / max(result.tot_ms, 1))
    @printf("  Linearization  : total %d (wasted %d) | avg/step %.3f  avg/ministep %.4f\n",
            result.linearization.total, result.linearization.wasted,
            result.linearization.total / max(result.nsteps, 1),
            result.linearization.total / max(result.tot_ms, 1))
    @printf("  Linear solver  : total %d (wasted %d) | avg/step %.3f  avg/ministep %.4f\n",
            result.linear_solver.total, result.linear_solver.wasted,
            result.linear_solver.total / max(result.nsteps, 1),
            result.linear_solver.total / max(result.tot_ms, 1))
    @printf("  Precond apply  : total %d (wasted %d) | avg/step %.3f  avg/ministep %.4f\n",
            result.precond_apply.total, result.precond_apply.wasted,
            result.precond_apply.total / max(result.nsteps, 1),
            result.precond_apply.total / max(result.tot_ms, 1))

    return result
end

# Запуск
process_logs(DIR; outname="jutul_ministeps_all.csv");
