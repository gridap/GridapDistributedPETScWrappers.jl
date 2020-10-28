using MPI
using PETSc_jll
using Libdl

export Scalar
export comm_type
export MPI_Comm
export PetscErrorCode
export PetscBool
export PetscInt
export have_petsc, petsc_libs, petsc_type
const depfile = joinpath(dirname(@__FILE__), "..", "..", "deps", "deps.jl")
isfile(depfile) || error("GridapDistributedPETScWrappers not properly installed. Please run Pkg.build(\"GridapDistributedPETScWrappers\")")
include(depfile)

if (deps_file_petscRealDouble == "")
  const petscRealDouble=PETSc_jll.libpetsc_path
else
  const petscRealDouble=deps_file_petscRealDouble
end
const petscRealSingle=""
const petscComplexDouble=""

const libs=[petscRealDouble]
const expected_petsc_scalar_types=[Float64]
const expected_petsc_real_types=[Float64]


function initialize(libhdl::Ptr{Cvoid})
  PetscInitializeNoArguments_ptr = dlsym(libhdl, :PetscInitializeNoArguments)
  result=ccall(PetscInitializeNoArguments_ptr, PetscErrorCode, ())
  @assert result==0
  return nothing
end

function DataTypeFromString(libhdl::Ptr{Cvoid}, name::AbstractString)
    PetscDataTypeFromString_ptr = dlsym(libhdl, :PetscDataTypeFromString)
    dtype_ref = Ref{UInt32}()
    found_ref = Ref{UInt32}()
    result=ccall(PetscDataTypeFromString_ptr, PetscErrorCode,
             (Cstring, Ptr{UInt32}, Ptr{UInt32}),
             name, dtype_ref, found_ref)
    @assert result==0
    @assert found_ref[] == UInt32(1)
    return dtype_ref[]
end

function PetscDataTypeGetSize(libhdl::Ptr{Cvoid}, dtype::UInt32)
    PetscDataTypeGetSize_ptr = dlsym(libhdl, :PetscDataTypeGetSize)
    datasize_ref = Ref{Csize_t}()
    result=ccall(PetscDataTypeGetSize_ptr, PetscErrorCode,
             (PetscDataType, Ptr{Csize_t}),
             dtype, datasize_ref)
    @assert result==0
    return datasize_ref[]
end

const libtypes = map(libs) do lib
    libhdl = dlopen(lib)
    initialize(libhdl)
    PETSC_REAL = DataTypeFromString(libhdl, "Real")
    PETSC_SCALAR = DataTypeFromString(libhdl, "Scalar")
    PETSC_INT_SIZE = PetscDataTypeGetSize(libhdl, PETSC_INT)

    PetscReal =
        PETSC_REAL == PETSC_DOUBLE ? Cdouble :
        PETSC_REAL == PETSC_FLOAT ? Cfloat :
        error("PETSC_REAL = $PETSC_REAL not supported.")

    PetscScalar =
        PETSC_SCALAR == PETSC_REAL ? PetscReal :
        PETSC_SCALAR == PETSC_COMPLEX ? Comlex{PetscReal} :
        error("PETSC_SCALAR = $PETSC_SCALAR not supported.")

    PetscInt =
        PETSC_INT_SIZE == 4 ? Int32 :
        PETSC_INT_SIZE == 8 ? Int64 :
        error("PETSC_INT_SIZE = $PETSC_INT_SIZE not supported.")

    # TODO: PetscBLASInt, PetscMPIInt ?
    return (lib, PetscScalar, PetscReal, PetscInt)
end

for (i,lib) in enumerate(libs)
  if (expected_petsc_scalar_types[i] != libtypes[i][2])
    error("""Expected PetscScalar ($(expected_petsc_scalar_types[i]))
          does NOT match lib $(lib) PetscScalar ($(libtypes[i][2]))
          """)
  end
  if (expected_petsc_real_types[i] != libtypes[i][3])
    error("""Expected PetscReal ($(expected_petsc_real_types[i]))
          does NOT match lib $(lib) PetscReal ($(libtypes[i][3]))
          """)
  end
end

const PetscInt=libtypes[1][4]

const petsc_libs = [:petscRealDouble, :petscRealSingle, :petscComplexDouble]
const petsc_type = [Float64, Float32, ComplexF64]

const Scalar=Union{Float32, Float64, ComplexF64}

# some auxiliary functions used by ccall wrappers
# get an array of pointers to UInt8s that is the same shape as
# the Symbol array
# does *not* allocate the pointers
function symbol_get_before(sym_arr)
  ptr_arr = Array{Ptr{UInt8}}(undef,length(sym_arr))
#  println("ptr_arr = ", ptr_arr)
#  for i=1:length(sym_arr)
#    println("ptr_arr[$i] = ", ptr_arr[i])
#  end

  return pointer(ptr_arr), ptr_arr
end

# turn array of strings (UInt8 *) and  puts them into Symbol array
function symbol_get_after(ptr, sym_arr)
  ptr_arr = unsafe_wrap(Array, ptr, length(sym_arr))

  for i=1:length(sym_arr)
    sym_arr[i] = Symbol(unsafe_string(ptr_arr[i]))
  end

end

function symbol_set_before(sym_arr)
  str_arr = similar(sym_arr, String)

  for i=1:length(str_arr)
    str_arr[i] = string(sym_arr[i])
  end

end

# TODO: auto-generate these
function PetscObjectComm(::Type{Float64},arg1::Ptr)
   ccall((:PetscObjectComm,petscRealDouble),comm_type,(Ptr{Cvoid},),arg1)
end
function PetscObjectComm(::Type{Float32},arg1::Ptr)
   ccall((:PetscObjectComm,petscRealSingle),comm_type,(Ptr{Cvoid},),arg1)
end
function PetscObjectComm(::Type{ComplexF64},arg1::Ptr)
   ccall((:PetscObjectComm,petscComplexDouble),comm_type,(Ptr{Cvoid},),arg1)
end
