<!-- [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://gridap.github.io/GridapDistributed.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://gridap.github.io/GridapDistributed.jl/dev) -->
[![Build Status](https://travis-ci.com/gridap/GridapDistributedPETScWrappers.svg?branch=master)](https://travis-ci.com/gridap/GridapDistributedPETScWrappers.jl)
[![Codecov](https://codecov.io/gh/gridap/GridapDistributedPETScWrappers.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/gridap/GridapDistributedPETScWrappers.jl)

# GridapDistributedPETScWrappers

[GridapDistributed.jl](https://github.com/gridap/GridapDistributed.jl) wrappers for the [PETSc](https://www.mcs.anl.gov/petsc/) library. 🚧 work in progress 🚧 

## Purpose

This package is currently **experimental, under development**. In any case, we warn that the package is not though to be a fully-functional PETSc wrapper written in Julia (for that purpose we refer to the [PETSc.jl](https://github.com/JuliaParallel/PETSc.jl) package, which is recently being revamped). Instead, it provides sufficient (although not necessarily necessary) functionality from PETSc as per-required by `GridapDistributed.jl`. Given that the latter is still under development, `GridapDistributedPETScWrappers.jl` may also vary accordingly to the changing requirements of `GridapDistributed.jl`. Once we have a more clear/definite understanding of what `GridapDistributed.jl` requires from `PETSc`, we may eventually significantly cut down the current code of  `GridapDistributedPETScWrappers.jl`.

The development of this package started originally from JuliaParallel's org `PETSc.jl` (in particular, from commit https://github.com/JuliaParallel/PETSc.jl/commit/3d8c46a127821aa1ff20d5892f50ec75be11c77f, `uptodate` branch). More information can be found in the following issue: https://github.com/gridap/GridapDistributed.jl/issues/22. Not all code which is currently in `GridapDistributedPETScWrappers.jl` is functional. In principle, one can safely use all the the machinery being tested in `test/runtests.jl`, although other parts may also be functional as well.

## Requirements, limitations, warnings

* PETSc version >= v3.10.3 REQUIRED.
  > From this commit of PETSc (petsc/petsc@2ebc710#diff-d46e9870b0b2f6361c8563135bfdaa89eab41a56290d02afb6ca42f5463ea629), the value of PETSC_INT changed from 0 to 16. This has implications on the PETSc julia wrappers, that have to define the associated constant accordingly. Accordingly to PETSc release dates, this change is reflected from v3.10.3 on. 

* We currently only support PETSc compiled with `PetscScalar==double` and `PetscReal==double` (i.e., Julia's `Float64`). This is referred to as `RealDouble` within `GridapDistributedPETScWrappers.jl`. The version of `PETSc.jl` from which we started also supported `RealSingle` and `ComplexDouble`, although no efforts have been spent into supporting these back. On the other hand, either 32-bit or 64-bit integer compilations of PETSc are allowed. The package automatically detects during cache module pre-compilation which is the size of `PetscInt`.

* All `finalizer`s of Julia types wrapping PETSc ones are deactivated. Thus, the latter ones are not destroyed when the former ones are GC'ed. The user may explicitly destroy the latter ones calling `PetscDestroy`. The user may activate `finalizer`s setting the package-wide constant `deactivate_finalizers` to `false`, although this is not recommended because of two reasons, which, to be honest, I do not fully understand:

     1. Tests fail when `finalizer`s are activated, because these cause an `MPI` call to be triggered after `MPI_Finalize` (could not understand why this is the case)
     2. Quoting from a `PETSc.jl` dev doc file: "We can't attach finalizers for distributed objects (i.e. `VecMPI`), as `destroy` needs to be called collectively on all MPI ranks." I guess that the GC may not ensure the same order of execution for all MPI tasks, causing deadlocks and other sort of issues.  

## Installation, usage instructions

`GridapDistributedPETScWrappers.jl` uses, among others, the [`MPI.jl`](https://github.com/JuliaParallel/MPI.jl) Julia package; see configuration documentation for this package available [here](https://juliaparallel.github.io/MPI.jl/stable/configuration/).

There are essentially two possible ways to build `GridapDistributedPETScWrappers.jl` (i.e., `pkg> build GridapDistributedPETScWrappers`):

1. One wants to use MPI+PETSc libraries pre-compiled in Julia registry packages (this is the typical case when one wants to use this package on your local computer). In this case one has to ensure that both `JULIA_MPI_BINARY` and `JULIA_PETSC_RealDouble_BINARY` are either unset or set to the empty string.

2. One wants to use a PETSc library already installed on the system (typically this is the case one is on a HPC cluster). In this case one has to ensure that `MPI.jl` is built such that it uses the same MPI library this installation of the PETSc library is compiled/linked with (see `MPI.jl` instructions referred above). The following environment variables are used to configure how `GridapDistributedPETScWrappers.jl` is built:
   * `JULIA_PETSC_RealDouble_BINARY` has to be set to `"system"`.
   * `JULIA_PETSC_RealDouble_DIR` has to be set to PETSc's DIR.
   * `JULIA_PETSC_RealDouble_ARCH` has to be set to PETSc's ARCH.
   * `JULIA_PETSC_RealDouble_LIBNAME` may optionally be set to the name of PETSc's dynamic library file of the system installation of PETSc (`libpetsc` is used otherwise by default).

<!-- [![Build Status](https://travis-ci.org/JuliaParallel/PETSc.jl.svg?branch=master)](https://travis-ci.org/JuliaParallel/PETSc.jl)
[![codecov.io](http://codecov.io/github/JuliaParallel/PETSc.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaParallel/PETSc.jl?branch=master)
[![Coverage Status](https://coveralls.io/repos/JuliaParallel/PETSc.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/JuliaParallel/PETSc.jl?branch=master)
[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://JuliaParallel.github.io/PETSc.jl/latest)

This package provides a high level interface for PETSc, enabling the use of PETSc as an `AbstractArray`.  
A low level interface is also available in the submodule `PETSc.C`.
The package supports 64-bit integers the `PetscInt` type described in 
the PETSc documentation, and `Float64`, `Float32`, and `Complex128` for the 
`PetscScalar` type.  In a default build of the package, all types can be used
simultaneously, using multiple dispatch to determine which version of PETSc
to use.

This package requires the [MPI.jl package](https://github.com/JuliaParallel/MPI.jl) be installed.  Once it is installed you should be able to run both Julia and Petsc in parallel using MPI for all communication.  The testing verifies that PETSc can be used both serially and in parallel.

To use the package, simply put `using PETSc` at the top of your Julia source file.  The module exports the names of all the functions, as well as the PETSc data type aliases and constants such as `PETSC_DECIDE`.

In general, it is possible to run PETSc in parallel. To do so with 4 processors, do:

```
mpirun -np 4 julia ./name_of_file
```

Note that this launches 4 independent Julia processes.  They are not aware of each other using Julia's built-in parallelism, and MPI is used for all communications.  

To run in serial, do:
```
julia ./name_of_file
```

Even when running serially, the [MPI.jl package](https://github.com/JuliaParallel/MPI.jl) must be installed.


An example of using a Krylov subspace method to solve a linear system is in  `test/test_ksp.jl`, which solves a simple system with a Krylov subspace method and compares the result with a direct solve using Julia's backslash operator.  This works in serial and in parallel.  It requires some variables declared at the top of `runtests.jl` to work.



## To do:
  * Make the script for building PETSc more flexible, e.g. allowing more configuration options like building BLAS or LAPCK, while ensure it remains completely autonomous (needed for Travis testing)
  * Wrap more KSP functions

## Status
### Vector
  The `AbstractArray` for `PetscVec` is implemented.  Some additional PETSc 
  BLAS functions are wrapped as well.
### Matrix
 The AbstractArray interface for `PetscMat` is implemented.  Preallocation 
 is supported through optional keyword arguments to the matrix constructor or
 the `setpreallocation` function.  It possible to set multiple values in the 
  matrix without intermediate assembly using the `assemble` function or by 
 setting the `Mat` object field `assembling` to `false` and calling `setindex`
 repeatedly.

### KSP
 Just enough KSP functions are implimented to do a GMRES solve.  Adding more 
functionality is the current priority.

## Directory Structure
  `/src` : source files.  PETSc.jl is the main file containing initialization, with the functions for each type of Petsc object in its own file.  All constants are declared in `petsc_constants.jl`.

  `/src/generated`: auto generated wrappers from Clang.jl.  Not directly useful, but easy to modify to make useful

  `/test` : contains `runtest.jl`, which does some setup and runs all tests on all three version of Petsc currently supported.  Tests for each type of Petsc object (mirroring the files in `/src`) are contained in separate files.

  `/deps` : builds Petsc if needed.  See description below


## Building PETSc
By default, building the package will build 3 versions of PETSc in the `/deps` 
 directory, and writes the file `lib_locations.jl` to the `/deps` 
 directory to tell the package the location of the libraries.  Note that 
this builds the debug versions of PETSc, which are recommended to use for all 
development.  If you wish to do high performance computations, you should 
build the optimized versions of the library.  See the PETSc website for 
details.

If you wish to build fewer than 3 version of PETSc or to use your own build 
of PETSc rather than having the package build it for you, there a several 
environmental variables that control what the build system will do.
For all the variables listed below, `name` is one of `RealDouble`, `RealSingle`,
or `ComplexDouble`, and specifies which version of the library the variable
describes.

### What to build
If the varibles `JULIA_PETSC_name_DIR` and `JULIA_PETSC_name_ARCH` are set to 
the `PETSC_DIR` and `PETSC_ARCH` of an existing PETSc installation, the build 
system will use that PETSc installation for the version of PETSc specified by
`name`.

If the variable `JULIA_PETSC_name_NOBUILD` exists (the value does not matter),
then the package will not build a version the `name`d version of PETSc.

### How to build it
If the variable `JULIA_PETSC_OPT` exists (the value does not matter), then 
a set of default optimization flags are passed to the PETSc `configure` 
script.

If the variable `JULIA_PETSC_FLAGS` exists and `JULIA_PETSC_OPT` does not, 
its value is used passed to the 
PETSc configure script (for all builds).  The user should *never* specify `--with-64-bit-indices`, `--with-scalar-type` or `--with-precision`, because this 
would break the build process for the different version of PETSc.

If neither of the above variables exist, a standard build is performed.


## Auto Generation Notes
PETSc uses preprocessor variables to decide what code to include when compiling 
the library.  Clang does not know what preprocessor variables were defined at 
compile time, so it does not correctly detect the typealiases `PetscScalar`, `PetscReal`, etc.  To correctly autogenerate wrappers, the proper variables must be passed to Clang with the -D switch.  Note that users will not need to generate their own wrappers because they have already been generated and commit to the repo. -->
