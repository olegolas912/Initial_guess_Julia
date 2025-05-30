![output](https://github.com/user-attachments/assets/d84baf60-71bb-4efd-b7f4-be0960f9205e)# Acceleration of convergence for conventional numerical schemes in reservoir modelling

This project implements advanced state estimation techniques for reservoir simulation using the [JutulDarcy](https://github.com/sintefmath/JutulDarcy.jl) framework. The implementation focuses on improving convergence and performance through various initial guess strategies for nonlinear iterations.

## Features

- Multiple state estimation strategies:
  - Linear combination of previous states
  - Simple Moving Average (SMA)
  - Linear regression based weighting
  - Aitken's Δ² acceleration
  - Broyden-style quasi-Newton method

## Project Structure

```
MsProject/
├── src/
│   ├── MsProject.jl             # Main module file
│   ├── simulator_linear_comb.jl # Implementation of state estimation methods
│   └── simulator_test.jl        # Testing module
├── demo/
│   ├── egg_new.jl               # Demo using the Egg model
│   └── egg_orig.jl              # Original implementation for comparison
├── Project.toml                 # Project dependencies
├── Manifest.toml                # Locked dependencies
└── setup_env.jl                 # Environment setup script
```

## Dependencies

The project requires the following Julia packages:
- Jutul
- JutulDarcy
- GLMakie
- DelimitedFiles
- HYPRE
- LinearAlgebra

## Setup

1. Clone the repository
2. Run the setup_env.jl script to configure the environment:
```julia
include("setup_env.jl")
```

## Usage

To run a simulation with the enhanced state estimation:

```julia
using MsProject
using Jutul, JutulDarcy

# Load your reservoir model
case = setup_case_from_data_file("path/to/your/model.DATA")

# Run simulation with state tracking
ws, states = simulate_reservoir(case, 
    timesteps=:none,
    output_substates=true,
    cutting_criterion=nothing)
```

## State Estimation Methods

### 1. Linear Combination
Combines previous states using weighted coefficients:
```julia
w = [w₁, w₂, w₃]  # weights for three previous states
```

### 2. Aitken's Δ² Acceleration
Implements Aitken's acceleration method for faster convergence using difference quotients.

### 3. Broyden-style Quasi-Newton
Uses a secant approximation based on previous iterations:
```julia
x_{n+1} = x_n + (x_n - x_{n-1})
```

## Results
![output](https://github.com/user-attachments/assets/cdce92ff-0173-4226-a58f-df8181048bd4)

## Extensions

The codebase is designed to be extensible. New state estimation methods can be added by implementing additional functions in `simulator_linear_comb.jl`.
