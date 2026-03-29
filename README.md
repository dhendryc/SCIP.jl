# SCIP.jl

[![Build Status](https://github.com/scipopt/SCIP.jl/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/scipopt/SCIP.jl/actions?query=workflow%3ACI)
[![codecov](https://codecov.io/gh/scipopt/SCIP.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/scipopt/SCIP.jl)

[SCIP.jl](https://github.com/scipopt/SCIP.jl) is a Julia interface to the
[SCIP](https://scipopt.org) solver.

It has two components:

 - a thin wrapper around the complete C API
 - an interface to [MathOptInterface](https://github.com/jump-dev/MathOptInterface.jl)

## Affiliation

This wrapper is maintained by the [SCIP project](https://www.scipopt.org/) with
the help of the JuMP community.

## Getting help

If you need help, please ask a question on the [JuMP community forum](https://jump.dev/forum).

If you have a reproducible example of a bug, please [open a GitHub issue](https://github.com/scipopt/SCIP.jl/issues/new).

## License

`SCIP.jl` is licensed under the [MIT License](https://github.com/scipopt/SCIP.jl/blob/master/LICENSE).

The underlying solver, [scipopt/scip](https://github.com/scipopt/scip), is
licensed under the [Apache 2.0 license](https://github.com/scipopt/scip/blob/master/LICENSE).

## Installation

Install SCIP using `Pkg.add`:
```julia
julia> import Pkg

julia> Pkg.add("SCIP")
```

In addition to installing the SCIP.jl package, this will also download and
install the SCIP binaries. You do not need to install SCIP separately.

## Custom installations

If you want a custom SCIP installation, you must manually install the SCIP
binaries.

Binaries are available for download at [https://www.scipopt.org/#download](https://www.scipopt.org/#download).

Once the binaries are installed, set the `SCIPOPTDIR` environment variable to
temporarily point to the installation path (that is, depending on your operating
system, `$SCIPOPTDIR/lib/libscip.so`, `$SCIPOPTDIR/lib/libscip.dylib`, or
`$SCIPOPTDIR/bin/libscip.dll` must exist). Then, install `SCIP.jl` using `Pkg.add`
and `Pkg.build` from the Julia command line:
```julia
julia> ENV["SCIPOPTDIR"] = raw"C:\Program Files\SCIPOptSuite 9.1.1" # for Windows

julia> import Pkg

julia> Pkg.add("SCIP")

julia> Pkg.build("SCIP")
```

### SCIP-SDP (mixed integer conic / PSD cone)

To use [SCIP-SDP](https://www.opt.tu-darmstadt.de/scipsdp/) for problems with semidefinite (PSD) constraints, compile and install SCIP-SDP yourself, then set the **`SCIP_SDP_OPTDIR`** environment variable to the installation path (separate from `SCIPOPTDIR`) and run `Pkg.build("SCIP")`. The package will then use the SCIP-SDP library and support the PSD cone.

- **Without** `SCIP_SDP_OPTDIR`: the package uses the default SCIP (JLL or `SCIPOPTDIR`) and does not support PSD constraints.
- **With** `SCIP_SDP_OPTDIR`: the package uses the SCIP-SDP build and supports `MOI.VectorOfVariables` in `MOI.PositiveSemidefiniteConeTriangle`.

SCIP-SDP can run in two modes (set before optimize):

- **Branch-and-bound with SDP relaxation** (default): `relaxing/SDP/freq = 1`
- **Outer approximation** (cutting planes only): `relaxing/SDP/freq = -1` and `lp/solvefreq = 1`

Set these via `MOI.RawOptimizerAttribute`, e.g. `MOI.set(model, MOI.RawOptimizerAttribute("relaxing/SDP/freq"), -1)`.

```bash
export SCIP_SDP_OPTDIR="/path/to/SCIP-SDP/build"   # or install prefix; must contain lib/libscipsdp.dylib (macOS) or lib/libscipsdp.so (Linux)
julia --project -e 'using Pkg; Pkg.build("SCIP")'
```

**Building SCIP (or SCIP-SDP) as a dependency of another package**

SCIP’s build runs when that package is built (e.g. when you `Pkg.build()` the parent project or first load a dependency that uses SCIP). The build script must **see the environment variable in the same process** that runs the build. If it doesn’t (e.g. you set it in one terminal but build from an IDE or a different shell), the script will skip the custom build and you’ll get the default JLL (no SCIP-SDP). The build script prints what it’s doing so you can confirm.

**Foolproof: set the variable and run the build in one command** (so the same process sees it):

```bash
cd /path/to/your_project
SCIP_SDP_OPTDIR="/path/to/SCIP-SDP/build" julia --project=. -e 'using Pkg; Pkg.build()'
```

Or set in the shell and then run Julia in that same shell:

```bash
export SCIP_SDP_OPTDIR="/path/to/SCIP-SDP/build"
cd /path/to/your_project
julia --project=. -e 'using Pkg; Pkg.build()'
```

Or set from Julia in the same session before building:

```julia
ENV["SCIP_SDP_OPTDIR"] = "/path/to/SCIP-SDP/build"
using Pkg; Pkg.build("SCIP")   # or Pkg.build() to build the whole project
```

When the build runs you should see either `SCIP build: SCIP_SDP_OPTDIR = "..."` and then success, or `SCIP build: Neither SCIPOPTDIR nor SCIP_SDP_OPTDIR is set` if the variable wasn’t visible. Set `JULIA_SCIP_BUILD_VERBOSE=0` to suppress these messages.

**If SCIP was already built without `SCIP_SDP_OPTDIR`**, the build script may not run again (Julia treats the package as already built). Force a rebuild by either:
- **Remove and re-add:** `] rm SCIP` then `] add SCIP`, set `SCIP_SDP_OPTDIR` in the same process, then `] build SCIP` (or build your project), or
- **Delete cached deps:** remove the file `deps/deps.jl` inside the SCIP.jl package in your Julia depot (e.g. `~/.julia/scratchspaces/.../SCIP/.../deps/deps.jl` or under your project’s artifact/depot), then run `] build SCIP` with `SCIP_SDP_OPTDIR` set.

**If the build does not enable SCIP-SDP** even with `SCIP_SDP_OPTDIR` set:

1. **Path**: `SCIP_SDP_OPTDIR` must be the directory that contains a `lib/` (or `bin/`) subdirectory with `libscipsdp.dylib` (macOS) or `libscipsdp.so` (Linux). For in-tree builds this is often the `build` directory (e.g. `SCIP-SDP/build`).
2. **Rebuild**: With `SCIP_SDP_OPTDIR` set in the environment, run `Pkg.build("SCIP")` from your project (e.g. `julia --project=. -e 'using Pkg; Pkg.build("SCIP")'`). If SCIP is a dependency, its package dir is in your Julia depot; you can delete that copy’s `deps/deps.jl` and run `Pkg.build("SCIP")` again to force the build to run.
3. **Load errors**: If the library exists but loading fails, check dependencies (e.g. on macOS run `otool -L $SCIP_SDP_OPTDIR/lib/libscipsdp.dylib`) and ensure any required libraries (BLAS, Lapack, etc.) are on your library path.

## Use with JuMP

Use SCIP with JuMP as follows:

```julia
using JuMP, SCIP
model = Model(SCIP.Optimizer)
set_attribute(model, "display/verblevel", 0)
set_attribute(model, "limits/gap", 0.05)
```

## Options

See the [SCIP documentation](https://www.scipopt.org/doc/html/PARAMETERS.php)
for a list of supported options.

## MathOptInterface API

The SCIP optimizer supports the following constraints and attributes.

List of supported objective functions:

 * [`MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Float64}}`](@ref)

List of supported variable types:

 * [`MOI.Reals`](@ref)

List of supported constraint types:

 * [`MOI.ScalarAffineFunction{Float64}`](@ref) in [`MOI.EqualTo{Float64}`](@ref)
 * [`MOI.ScalarAffineFunction{Float64}`](@ref) in [`MOI.GreaterThan{Float64}`](@ref)
 * [`MOI.ScalarAffineFunction{Float64}`](@ref) in [`MOI.Interval{Float64}`](@ref)
 * [`MOI.ScalarAffineFunction{Float64}`](@ref) in [`MOI.LessThan{Float64}`](@ref)
 * [`MOI.ScalarNonlinearFunction`](@ref) in [`MOI.EqualTo{Float64}`](@ref)
 * [`MOI.ScalarNonlinearFunction`](@ref) in [`MOI.GreaterThan{Float64}`](@ref)
 * [`MOI.ScalarNonlinearFunction`](@ref) in [`MOI.Interval{Float64}`](@ref)
 * [`MOI.ScalarNonlinearFunction`](@ref) in [`MOI.LessThan{Float64}`](@ref)
 * [`MOI.ScalarQuadraticFunction{Float64}`](@ref) in [`MOI.EqualTo{Float64}`](@ref)
 * [`MOI.ScalarQuadraticFunction{Float64}`](@ref) in [`MOI.GreaterThan{Float64}`](@ref)
 * [`MOI.ScalarQuadraticFunction{Float64}`](@ref) in [`MOI.Interval{Float64}`](@ref)
 * [`MOI.ScalarQuadraticFunction{Float64}`](@ref) in [`MOI.LessThan{Float64}`](@ref)
 * [`MOI.VariableIndex`](@ref) in [`MOI.EqualTo{Float64}`](@ref)
 * [`MOI.VariableIndex`](@ref) in [`MOI.GreaterThan{Float64}`](@ref)
 * [`MOI.VariableIndex`](@ref) in [`MOI.Integer`](@ref)
 * [`MOI.VariableIndex`](@ref) in [`MOI.Interval{Float64}`](@ref)
 * [`MOI.VariableIndex`](@ref) in [`MOI.LessThan{Float64}`](@ref)
 * [`MOI.VariableIndex`](@ref) in [`MOI.ZeroOne`](@ref)
 * [`MOI.VectorAffineFunction{Float64}`](@ref) in [`MOI.Indicator{MOI.ACTIVATE_ON_ONE,MOI.LessThan{Float64}}`](@ref)
 * [`MOI.VectorOfVariables`](@ref) in [`MOI.SOS1{Float64}`](@ref)
 * [`MOI.VectorOfVariables`](@ref) in [`MOI.SOS2{Float64}`](@ref)
 * When built with SCIP-SDP (`SCIP_SDP_OPTDIR`): [`MOI.VectorOfVariables`](@ref) in [`MOI.PositiveSemidefiniteConeTriangle`](@ref)

List of supported model attributes:

 * [`MOI.HeuristicCallback`](@ref)
 * [`MOI.NLPBlock()`](@ref)
 * [`MOI.ObjectiveSense()`](@ref)
 * [`MOI.UserCutCallback()`](@ref)

## Design considerations

### Wrapping the public API

All of the public API methods are wrapped and available within the `SCIP`
package. This includes the `scip_*.h` and `pub_*.h` headers that are collected
in `scip.h`, as well as all default constraint handlers (`cons_*.h`.)

The wrapped functions do not transform any data structures and work on the *raw*
pointers (for example, `SCIP*` in C, `Ptr{SCIP_}` in Julia). Convenience wrapper
functions based on Julia types are added as needed.

### Memory management

Programming with SCIP requires dealing with variable and constraint objects that
use [reference counting](https://www.scipopt.org/doc/html/OBJ.php) for memory
management.

The `SCIP.Optimizer` wrapper type collects lists of `SCIP_VAR*` and `SCIP_CONS*`
under the hood, and it releases all references when it is garbage collected
itself (via `finalize`).

When adding a variable (`add_variable`) or a constraint (`add_linear_constraint`),
an integer index is returned. This index can be used to retrieve the `SCIP_VAR*`
or `SCIP_CONS*` pointer via `get_var` and `get_cons` respectively.

### Supported nonlinear operators

Supported operators in nonlinear expressions are as follows:

 * `+`
 * `-`
 * `*`
 * `/`
 * `^`
 * `sqrt`
 * `exp`
 * `log`
 * `abs`
 * `cos`
 * `sin`
