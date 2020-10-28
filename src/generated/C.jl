module C

using Compat
export PetscInt
using MPI

# These three constants where originally in defs.jl.
# I had to changed them here because I swapped the
# order of the next two includes
const MPI_COMM_SELF=MPI.COMM_SELF
const MPI_Comm=MPI.Comm
const comm_type=MPI.Comm

include("libPETSc_commonRealDouble.jl")
include("defs.jl")
if have_petsc[1]
  include("PETScRealDouble.jl")
end
if have_petsc[2]
  include("PETScRealSingle.jl")
end
if have_petsc[3]
  include("PETScComplexDouble.jl")
end
include("error.jl")
include("defs2.jl")
include("c_funcs.jl")
end
