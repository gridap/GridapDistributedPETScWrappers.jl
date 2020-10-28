using GridapDistributedPETScWrappers
using GridapDistributedPETScWrappers.C
using MPI
using LinearAlgebra
using SparseArrays
using Test

# determine scalar type of current run
global ST = Float64  # scalar type

function RC(x::Number)
# used to test real, complex
  if ST == Float64
    return Float64(real(x))
  elseif ST == Float32
    return Float32(real(x))
  else  # scalar_type == 3
    return complex(x)
  end
end

function RC(x::AbstractArray)
# used to test real, complex
  if ST == Float64
    tmp = similar(x, ST)
    for i=1:length(x)
      tmp[i] = Float64(real(x[i]))
    end
    return tmp
  elseif ST == Float32
    tmp = similar(x, ST)
    for i=1:length(x)
      tmp[i] = ST(real(x[i]))
    end
    return tmp
  else  # scalar_type == 3
    return x
  end
end

# convert to PetscReal
function RT(x::Number)
  if ST == Float64 || ST == Complex128
    return Float64(x)
  else
    return Float32(x)
  end

end

function mymult(A::GridapDistributedPETScWrappers.C.Mat{T}, x::GridapDistributedPETScWrappers.C.Vec, b::GridapDistributedPETScWrappers.C.Vec) where {T}
# matrix multiplication function for the shell matrix A
# A performs the action of A = diagm(1:sys_size)

  bigx = Vec{T}(x, first_instance=false)
  bigb = Vec{T}(b, first_instance=false)
  localx = LocalVector_readonly(bigx)
  localb = LocalVector(bigb)
  for i=1:length(localx)
    localb[i] = i*localx[i]
  end

  restore(localx)
  restore(localb)
  return GridapDistributedPETScWrappers.C.PetscErrorCode(0)
end
