# these functions work directly with the C interface, offering better
# performance than the high level interface, particularly for indexing

##### Vec #####

  function VecCreate(::Type{T}; comm=MPI.COMM_WORLD) where {T}
    vref = Ref{Vec{T}}()
    chk(VecCreate(comm, vref))
    return vref[]
  end


  function SetValues(vec::Vec{T},idx::AbstractVector{PetscInt},
                                vals::AbstractVector{T},
                                flag::Integer=INSERT_VALUES) where {T}

    chk(VecSetValues(vec, length(idx), idx, vals, InsertMode(flag)))
  end


  function AssemblyBegin(obj::Vec)

    chk(VecAssemblyBegin(obj))
  end

  function AssemblyEnd(obj::Vec)
    chk(VecAssemblyEnd(obj))
  end

  function GetValues(vec::Vec{T}, idx::AbstractArray{PetscInt,1},
                             y::AbstractArray{T,1}) where{T}

    chk(VecGetValues(vec, length(idx), idx, y))

  end


##### Mat #####

function MatCreateShell(arg2::Integer,arg3::Integer,arg4::Integer,arg5::Integer, arg6::Ptr{Cvoid}, dtype::Type{T}=Float64;arg1::MPI.Comm=MPI.COMM_WORLD) where{T}
  # arg6 is the user provided context
    arg7 = Ref{Mat{dtype}}()
    chk(MatCreateShell(arg1, arg2, arg3, arg4, arg5, arg6, arg7))

    return Mat(arg7[])
end

#= # this function signature is not distinct from the auto generated one
function MatShellSetOperation(arg1::Mat,arg2::MatOperation,arg3::Ptr{Cvoid})
# arg3 is a function pointer, and must have the signature:
# void fname(Mat, vec, vec) for MATOP_MULT
    chk(MatShellSetOperation(arg1, arg2, arg3))
end
=#

for (T, P) in ( (Float64, petscRealDouble), (Float32, petscRealSingle), (ComplexF64, petscComplexDouble) )
  @eval begin
    function MatShellGetContext(arg1::Mat{$T})
    # get the user provided context for the matrix shell
        arg2 = Ref{Ptr{Cvoid}}()
        # this doesn't work because the Petsc developers were sloppy with their
        # void pointers
    #    chk(MatShellGetContext(arg1, arg2))
        chk(ccall((:MatShellGetContext,$P),PetscErrorCode,(Mat{$T},Ref{Ptr{Cvoid}}),arg1,arg2))
        return arg2[]  # turn it into a julia object here?
    end
  end
end

  function SetValues(vec::Mat,idi::AbstractArray{PetscInt},idj::AbstractArray{PetscInt},array::AbstractArray{ST},flag::Integer=INSERT_VALUES) where {ST}
    # remember, only matrices can be inserted into a Petsc matrix
    # if array is a 3 by 3, then idi and idj are vectors of length 3

#    @assert length(idi)*length(idj) == length(array)

    # do check here to ensure array is the right shape (remember tranpose)
    chk(MatSetValues(vec, length(idi), idi, length(idj), idj, array, InsertMode(flag)))

  end

  function SetValuesBlocked(mat::Mat, idi::AbstractArray{PetscInt}, idj::AbstractArray{PetscInt}, v::AbstractArray{ST}, flag::Integer=INSERT_VALUES) where {ST}

    chk(MatSetValuesBlocked(mat, length(idi), idi, length(idj), idj, v, InsertMode(flag)))
  end

  function MatSetOption(mat::Mat,arg2::MatOption,arg3::Bool)
    chk(MatSetOption(mat, arg2, PetscBool(arg3)))
  end

  function AssemblyBegin(obj::Mat,flg=MAT_FINAL_ASSEMBLY)
    chk(MatAssemblyBegin(obj, MatAssemblyType(flg)))
  end

  function AssemblyEnd(obj::Mat,flg=MAT_FINAL_ASSEMBLY)
    chk(MatAssemblyEnd(obj, MatAssemblyType(flg)))
  end


  function GetValues(obj::Mat, idxm::AbstractArray{PetscInt, 1}, idxn::AbstractArray{PetscInt, 1}, v::AbstractArray{ST}) where {ST}
    # do check here to ensure v is the right shape
    chk(MatGetValues(obj, length(idxm), idxm, length(idxn), idxn, v))
end
