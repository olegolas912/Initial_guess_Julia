module JutulMiniStepPatch
__precompile__(false)

using Jutul
import Jutul: simulator_storage, solve_ministep,
    check_output_variables, sort_secondary_variables!,
    setup_state, setup_storage, ProgressRecorder,
    initialize_storage!, specialize_simulator_storage,
    prepare_step_storage,
    perform_step!, progress_recorder, current_time,
    update_before_step!, update_secondary_variables!,
    next_iteration!, apply_nonlinear_strategy!,
    update_after_step!, reset_state_to_previous_state!,
    simulator_executor, get_output_state, JUTUL_OUTPUT_TYPE,
    reset_variables!

const MAX_MINISTEP_HISTORY = 3


function nested_state_combination(hist::Vector{Dict{Symbol,Any}},
    w::AbstractVector)
    @assert length(hist) == length(w)
    out = Dict{Symbol,Any}()

    for mdl in keys(hist[end])
        first_sub = hist[end][mdl]
        if !(first_sub isa Dict)
            out[mdl] = first_sub
            continue
        end

        sub_out = Dict{Symbol,Any}()
        for v in keys(first_sub)
            v0 = first_sub[v]

            is_numeric = v0 isa Number ||
                         (v0 isa AbstractArray && eltype(v0) <: Number)

            if is_numeric
                acc = zero(v0) .* 0
                for (st, α) in zip(hist, w)
                    acc .+= α .* st[mdl][v]
                end
                sub_out[v] = acc
            else
                sub_out[v] = v0
            end
        end
        out[mdl] = sub_out
    end
    return out
end

using LinearAlgebra


using LinearAlgebra

# Check if it's numberic
is_numeric(x) = x isa Number ||
                (x isa AbstractArray && eltype(x) <: Number)

# 4. Aitken’s Δ²‐acceleration
function aitken_initial_guess(hist::Vector{Dict{Symbol,Any}})
    s1, s2, s3 = hist
    out = Dict{Symbol,Any}()

    for mdl in keys(s3)
        sub3 = s3[mdl]
        if !(sub3 isa Dict)
            out[mdl] = sub3
            continue
        end

        sub_out = Dict{Symbol,Any}()
        for v in keys(sub3)
            x1 = s1[mdl][v]
            x2 = s2[mdl][v]
            x3 = s3[mdl][v]

            if is_numeric(x1)
                # Δx1 = x2 − x1, Δx2 = x3 − x2, Δ² = Δx2 − Δx1
                Δ1 = x2 .- x1
                Δ2 = x3 .- x2
                Δ² = Δ2 .- Δ1 .+ eps()    # eps protect from  /0
                sub_out[v] = x3 .- (Δ2 .^ 2) ./ Δ²
            else
                # no arithmetic — take the last one
                sub_out[v] = x3
            end
        end

        out[mdl] = sub_out
    end

    return out
end


# 5. “Broyden‐style” quasi‐Newton guess (here: secant‐step approximation)
function broyden_initial_guess(hist::Vector{Dict{Symbol,Any}})
    s1, s2, s3 = hist
    out = Dict{Symbol,Any}()

    for mdl in keys(s3)
        sub3 = s3[mdl]
        if !(sub3 isa Dict)
            out[mdl] = sub3
            continue
        end

        sub_out = Dict{Symbol,Any}()
        for v in keys(sub3)
            x1 = s1[mdl][v]
            x2 = s2[mdl][v]
            x3 = s3[mdl][v]

            if is_numeric(x1)
                # add the simple increment from the last step
                sub_out[v] = x3 .+ (x3 .- x2)
            else
                sub_out[v] = x3
            end
        end

        out[mdl] = sub_out
    end

    return out
end



function simulator_storage(model;
    state0=nothing,
    parameters=setup_parameters(model),
    copy_state=true,
    check=true,
    mode=:forward,
    specialize=false,
    prepare_step_handler=missing,
    kwarg...)
    if mode == :forward
        state_ad = true
        state0_ad = false
    elseif mode == :reverse
        state_ad = false
        state0_ad = true
    else
        state_ad = true
        state0_ad = true
    end
    check && check_output_variables(model)
    sort_secondary_variables!(model)

    isnothing(state0) && (state0 = setup_state(model))
    copy_state && (state0 = deepcopy(state0))

    storage = setup_storage(model;
        state0=state0,
        parameters=parameters,
        state0_ad=state0_ad,
        state_ad=state_ad)

    storage[:recorder] = ProgressRecorder()
    # ─────────────────────────────────────────────────
    storage[:ministates] = Vector{Dict{Symbol,Any}}()
    # ─────────────────────────────────────────────────────────────────────
    initialize_storage!(storage, model; kwarg...)

    if !ismissing(prepare_step_handler)
        pst = prepare_step_storage(prepare_step_handler, storage, model)
        storage[:prepare_step_handler] = (prepare_step_handler, pst)
    end
    return specialize_simulator_storage(storage, model, specialize)
end

function solve_ministep(sim, dt, forces, max_iter, cfg;
    finalize=true,
    prepare=true,
    relaxation=1.0,
    update_explicit=true)

    rec = progress_recorder(sim)
    stor = sim.storage
    hist = stor[:ministates]

    report = JUTUL_OUTPUT_TYPE()
    report[:dt] = dt
    step_reports = JUTUL_OUTPUT_TYPE[]
    cur_time = current_time(rec)

    t_prepare = @elapsed if prepare
        update_before_step!(sim, dt, forces;
            time=cur_time,
            recorder=rec,
            update_explicit=update_explicit)
    end

    # --------------------------------------------------------
    if length(hist) == MAX_MINISTEP_HISTORY
        # w_lr = [-0.5, 0.0, 1.5] 
        # guess_state = nested_state_combination(hist, w_lr)

        # w_diff = [0.0, -1.0, 2.0]
        # guess_state = nested_state_combination(hist, w_diff)

        # w_sma = [0.1, 0.3, 0.6]
        # guess_state = nested_state_combination(hist, w_sma)

        # guess_state = aitken_initial_guess(hist)

        guess_state = broyden_initial_guess(hist)


        last_state = hist[end]
        key = :Pressure
        if haskey(last_state, key)
            Δ = norm(guess_state[key] .- last_state[key]) /
                (norm(last_state[key]) + eps())
            @info "*** Initial-guess Δ($key) = $(round(Δ, sigdigits = 4))"
        end

        reset_variables!(sim, guess_state; type=:state)
        update_secondary_variables!(stor, sim.model)
    end

    step_report = missing
    for it = 1:(max_iter+1)
        do_solve = it <= max_iter
        e, done, step_report = perform_step!(
            sim, dt, forces, cfg;
            iteration=it,
            relaxation=relaxation,
            solve=do_solve,
            executor=simulator_executor(sim),
            prev_report=step_report
        )
        push!(step_reports, step_report)

        if haskey(step_report, :failure_exception)
            throw(step_report[:failure_exception])
        end

        next_iteration!(rec, step_report)
        done && break

        relaxation, early_stop = apply_nonlinear_strategy!(
            sim, dt, forces, it, max_iter, cfg, e, step_reports, relaxation)
        early_stop && break
    end

    report[:steps] = step_reports
    report[:success] = step_report[:converged]
    report[:prepare_time] = t_prepare

    post_hook = cfg[:post_ministep_hook]
    if !ismissing(post_hook)
        report[:success], report = post_hook(report[:success], report, sim,
            dt, forces, max_iter, cfg)
    end

    report[:finalize_time] = @elapsed if finalize
        if report[:success]
            report[:post_update] =
                update_after_step!(sim, dt, forces;
                    time=cur_time + dt)
        else
            reset_state_to_previous_state!(sim)
        end
    end

    # --- ----------------------------------------------------
    if report[:success]
        push!(hist, deepcopy(get_output_state(stor, sim.model)))
        if length(hist) > MAX_MINISTEP_HISTORY
            popfirst!(hist)
        end
        # @info "*** Ministate buffer size = $(length(hist))"
    end
    # ---------------------------------------------------------------------

    return (report[:success], report)
end

end
