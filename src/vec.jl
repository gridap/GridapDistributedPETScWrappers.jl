# AbstractVector wrapper around PETSc Vec types
export Vec, comm, NullVec

 """
  Construct a high level Vec object from a low level C.Vec.
  The data field is used to protect things from GC.
  A finalizer is attached to deallocate the memory of the underlying C.Vec, unless
  `first_instance` is set to true.
  `assembled` indicates when values are set via `setindex!` and is reset by
   `AssemblyEnd`
   `verify_assembled` when true, calls to `isassembled` verify all processes
   have `assembled` = true, when false, only the local assembly state is
   checked.  This essentially makes the user responsible for assembling
  the vector before passing it into functions that will use it (like KSP
  solves, etc.).

"""
mutable struct Vec{T} <: AbstractVector{T}
  p::C.Vec{T}
  assembled::Bool # whether are all values have been assembled
  verify_assembled::Bool # check whether all processes are assembled
  insertmode::C.InsertMode # current mode for setindex!
  data::Any # keep a reference to anything needed for the Mat
            # -- needed if the Mat is a wrapper around a Julia object,
            #    to prevent the object from being garbage collected.
  function Vec{T}(p::C.Vec{T}, data=nothing; first_instance::Bool=true,
               verify_assembled::Bool=true) where {T}
    v = new{T}(p, false, verify_assembled, C.INSERT_VALUES, data)
    if first_instance
      finalizer(PetscDestroy,v)
    end
    return v
  end
end

function Base.show(io::IO, x::Vec)
  myrank = MPI.Comm_rank(comm(x))
  if myrank == 0
    println("Petsc Vec of length ", length(x))
  end
  if isassembled(x)
    println(io, "Process ", myrank, " entries:")
    x_arr = LocalVector_readonly(x)
    show(io, x_arr)
    restore(x_arr)
  else
    println(io, "Process ", myrank, " not assembled")
  end
end

"""
  Null vectors, used in place of void pointers in the C
  API
"""
global const NullVec = Dict{DataType, Vec}()


if have_petsc[1]
  global const NullVec1 = Vec{Float64}(C.Vec{Float64}(C_NULL), first_instance=false)
  NullVec[Float64] = NullVec1
end
if have_petsc[2]
  global const NullVec2 = Vec{Float32}(C.Vec{Float32}(C_NULL), first_instance=false)
  NullVec[Float32] = NullVec2
end
if have_petsc[3]
  global const NullVec3 = Vec{Complex128}(C.Vec{Complex128}(C_NULL), first_instance=false)
  NullVec[Complex128] = NullVec3

end
 """
  Gets the MPI communicator of a vector.
"""
function comm(v::Vec{T}) where {T}
  return C.PetscObjectComm(T, v.p.pobj)
end


export gettype

 """
  Get the Symbol that is the format of the vector
"""
function gettype(a::Vec{T}) where {T}
  sym_arr = Array{C.VecType}(undef,1)
  chk(C.VecGetType(a.p, sym_arr))
  return sym_arr[1]
end


 """
  Create an empty, unsized vector.
"""
function Vec(::Type{T}, vtype::C.VecType=C.VECMPI;
                comm::MPI.Comm=MPI.COMM_WORLD) where {T}
  p = Ref{C.Vec{T}}()
  chk(C.VecCreate(comm, p))
  chk(C.VecSetType(p[], vtype))
  v = Vec{T}(p[])
  v
end

 """
  Create a vector, specifying the (global) length len or the local length
  mlocal.  Even if the blocksize is > 1, teh lengths are always number of
  elements in the vector, not number of block elements.  Thus
  len % blocksize must = 0.
"""
function Vec(::Type{T}, len::Integer=C.PETSC_DECIDE;
                         vtype::C.VecType=C.VECMPI,  bs=1,
                         comm::MPI.Comm=MPI.COMM_WORLD,
                         mlocal::Integer=C.PETSC_DECIDE) where {T<:Scalar}
  vec = Vec(T, vtype; comm=comm)
  resize!(vec, len, mlocal=mlocal)
  set_block_size(vec, bs)
  vec
end

 """
  Make a PETSc vector out of an array.  If used in parallel, the array becomes
  the local part of the PETSc vector
"""
# make a Vec that is a wrapper around v, where v stores the local data
function Vec(v::Vector{T}; comm::MPI.Comm=MPI.COMM_WORLD) where {T<:Scalar}
  p = Ref{C.Vec{T}}()
  chk(C.VecCreateMPIWithArray(comm, 1, length(v), C.PETSC_DECIDE, v, p))
  pv = Vec{T}(p[], v)
  return pv
end

function set_block_size(v::Vec{T}, bs::Integer) where {T<:Scalar}
  chk(C.VecSetBlockSize(v.p, bs))
end

function get_blocksize(v::Vec{T}) where {T<:Scalar}
  bs = Ref{PetscInt}()
  chk(C.VecGetBlockSize(v.p, bs))
  return Int(bs[])
end

export VecGhost, VecLocal, restore


 """
  Make a PETSc vector with space for ghost values.  ghost_idx are the
  global indices that will be copied into the ghost space.
"""
# making mlocal the position and mglobal the keyword argument is inconsistent
# with the other Vec constructors, but it makes more sense here
function VecGhost(::Type{T}, mlocal::Integer,
                  ghost_idx::Array{I,1}; comm=MPI.COMM_WORLD, m=C.PETSC_DECIDE, bs=1, vtype=C.VECMPI) where {T<:Scalar, I <: Integer}

    nghost = length(ghost_idx)
    ghost_idx2 = [ PetscInt(i -1) for i in ghost_idx]

    vref = Ref{C.Vec{T}}()
    if bs == 1
      chk(C.VecCreateGhost(comm, mlocal, m, nghost, ghost_idx2, vref))
    elseif bs > 1
      chk(C.VecCreateGhostBlock(comm, bs, mlocal, mlocal, m, nghost, ghost_idx2, vref))
    else
      println(stderr, "WARNING: unsupported block size requested, bs = ", bs)
    end

    chk(C.VecSetType(vref[], vtype))

    return Vec{T}(vref[])
end

 """
  Create a VECSEQ that contains both the local and the ghost values of the
  original vector.  The underlying memory for the orignal and output vectors
  alias.
"""
function VecLocal( v::Vec{T}) where {T<:Scalar}

  vref = Ref{C.Vec{T}}()
  chk(C.VecGhostGetLocalForm(v.p, vref))
  # store v to use with Get/Restore LocalForm
  # Petsc reference counting solves the gc problem
  return Vec{T}(vref[], v)
end

#TODO: use restore for all types of restoring a local view
 """
  Tell Petsc the VecLocal is no longer needed
"""
function restore(v::Vec{T}) where {T}

  vp = v.data
  vref = Ref(v.p)
  chk(C.VecGhostRestoreLocalForm(vp.p, vref))
end


 """
  The Petsc function to deallocate Vec objects
"""
function PetscDestroy(vec::Vec{T}) where {T}
  if !PetscFinalized(T)  && !isfinalized(vec)
    C.VecDestroy(Ref(vec.p))
    vec.p = C.Vec{T}(C_NULL)  # indicate the vector is finalized
  end
end

 """
  Determine whether a vector has already been finalized
"""
function isfinalized(vec::Vec)
  return isfinalized(vec.p)
end

function isfinalized(vec::C.Vec)
  return vec.pobj == C_NULL
end

global const is_nullvec = isfinalized  # another name for doing the same check

 """
  Use the PETSc routine for printing a vector to stdout
"""
function petscview(vec::Vec{T}) where {T}
  viewer = C.PetscViewer{T}(C_NULL)
  chk(C.VecView(vec.p, viewer))
end

function Base.resize!(x::Vec, m::Integer=C.PETSC_DECIDE; mlocal::Integer=C.PETSC_DECIDE)
  if m == mlocal == C.PETSC_DECIDE
    throw(ArgumentError("either the length (m) or local length (mlocal) must be specified"))
  end

  chk(C.VecSetSizes(x.p, mlocal, m))
  x
end

###############################################################################
export ghost_begin!, ghost_end!, scatter!, ghost_update!
# ghost vectors: essential methods
 """
  Start communication to update the ghost values (on other processes) from the local
  values
"""
function ghost_begin!(v::Vec{T}; imode=C.INSERT_VALUES,
                               smode=C.SCATTER_FORWARD) where {T<:Scalar}
    chk(C.VecGhostUpdateBegin(v.p, imode, smode))
    return v
end

 """
  Finish communication for updating ghost values
"""
function ghost_end!(v::Vec{T}; imode=C.INSERT_VALUES,
                               smode=C.SCATTER_FORWARD) where {T<:Scalar}
    chk(C.VecGhostUpdateEnd(v.p, imode, smode))
    return v
end

# ghost vectors: helpful methods
 """
  Convenience method for calling both ghost_begin! and ghost_end!
"""
function scatter!(v::Vec{T}; imode=C.INSERT_VALUES, smode=C.SCATTER_FORWARD) where {T<:Scalar}

  ghost_begin!(v, imode=imode, smode=smode)
  ghost_end!(v, imode=imode, smode=smode)
end

# is there a way to specify all varargs must be same type?
# this can't be named scatter! because of ambiguity with the index set scatter!
 """
  Convenience method for calling ghost_begin! and ghost_end! for multiple vectors
"""
function ghost_update!(v...; imode=C.INSERT_VALUES, smode=C.SCATTER_FORWARD)

  for i in v
    ghost_begin!(i, imode=imode, smode=smode)
  end

  for i in v
    ghost_end!(i, imode=imode, smode=smode)
  end

  return v
end



###############################################################################
export lengthlocal, sizelocal, localpart

Base.convert(::Type{C.Vec}, v::Vec) = v.p

import Base.length
 """
  Get the global length of the vector
"""
function length(x::Vec)
  sz = Ref{PetscInt}()
  chk(C.VecGetSize(x.p, sz))
  Int(sz[])
end

 """
  Get the global size of the vector
"""
Base.size(x::Vec) = (length(x),)

 """
  Get the length of the local portion of the vector
"""
function lengthlocal(x::Vec)
  sz = Ref{PetscInt}()
  chk(C.VecGetLocalSize(x.p, sz))
  sz[]
end

"""
  Get the local size of the vector
"""
sizelocal(x::Vec) = (lengthlocal(x),)

"""
  Get local size of the vector
"""
sizelocal(t::AbstractArray{T,n}, d) where {T,n} = (d>n ? 1 : sizelocal(t)[d])

 """
  Get the range of global indices that define the local part of the vector.
  Internally, this calls the Petsc function VecGetOwnershipRange, and has
  the same limitations as that function, namely that some vector formats do
  not have a well defined contiguous range.
"""
function localpart(v::Vec)
  # this function returns a range from the first to the last indicies (1 based)
  # this is different than the Petsc VecGetOwnershipRange function where
  # the max value is one more than the number of entries
  low = Ref{PetscInt}()
  high = Ref{PetscInt}()
  chk(C.VecGetOwnershipRange(v.p, low, high))
  return (low[]+1):(high[])
end

"""
  Similar to localpart, but returns the range of block indices
"""
function localpart_block(v::Vec)
  low = Ref{PetscInt}()
  high = Ref{PetscInt}()
  chk(C.VecGetOwnershipRange(v.p, low, high))
  bs = get_blocksize(v)
  low_b = div(low[], bs); high_b = div(high[]-1, bs)
  ret = (low_b+1):(high_b+1)

  return ret
end


function Base.similar(x::Vec{T}) where {T}
  p = Ref{C.Vec{T}}()
  chk(C.VecDuplicate(x.p, p))
  Vec{T}(p[])
end

Base.similar(x::Vec{T}, ::Type{T}) where {T} = similar(x)
function Base.similar(x::Vec{T}, T2::Type) where {T}
  VType = gettype(x)
  Vec(T2, length(x), VType; comm=comm(x), mlocal=lengthlocal(x))
end

function Base.similar(x::Vec{T}, T2::Type, len::Union{Int,Dims{1}}) where {T}
  VType = gettype(x)
  len[1]==length(x) && T2==T ? similar(x) : Vec(T2, len[1], vtype=VType; comm=comm(x))
end

function Base.similar(x::Vec{T}, len::Union{Int,Dims{1}}) where {T}
  VType = gettype(x)
  len[1]==length(x) ? similar(x) : Vec(T, len[1], vtype=VType; comm=comm(x))
end

function Base.copy(x::Vec)
  AssemblyBegin(x)
  y = similar(x)
  AssemblyEnd(x)
  chk(C.VecCopy(x.p, y.p))
  y
end

###############################################################################
export localIS, local_to_global_mapping, set_local_to_global_mapping, has_local_to_global_mapping

"""
  Constructs index set mapping from local indexing to global indexing, based
  on localpart()
"""
function localIS(A::Vec{T}) where {T}

  rows = localpart(A)
  rowis = IS(T, rows, comm=comm(A))
  return rowis
end

"""
  Like localIS, but returns a block index IS
"""
function localIS_block(A::Vec{T}) where {T}
  rows = localpart_block(A)
  bs = get_blocksize(A)
  rowis = ISBlock(T, bs, rows, comm=comm(A))
#  set_blocksize(rowis, get_blocksize(A))
  return rowis
end
"""
  Construct ISLocalToGlobalMappings for the vector.  If a block vector,
  create a block index set
"""
function local_to_global_mapping(A::Vec)

  # localIS creates strided index sets, which require only constant
  # memory
  if get_blocksize(A) == 1
    rowis = localIS(A)
  else
    rowis = localIS_block(A)
  end
  row_ltog = ISLocalToGlobalMapping(rowis)

  return row_ltog
end

# need a better name
"""
  Registers the ISLocalToGlobalMapping with the Vec
"""
function set_local_to_global_mapping(A::Vec{T}, rmap::ISLocalToGlobalMapping{T}) where {T}

  chk(C.VecSetLocalToGlobalMapping(A.p, rmap.p))
end

"""
  Check if the local to global mapping has been registered
"""
function has_local_to_global_mapping(A::Vec{T}) where {T}

  rmap_ref = Ref{C.ISLocalToGlobalMapping{T}}()
  chk(C.VecGetLocalToGlobalMapping(A.p, rmap_re))

  rmap = rmap_ref[]

  return rmap.pobj != C_NULL
end


##########################################################################
import Base: setindex!
export assemble, isassembled, AssemblyBegin, AssemblyEnd

# for efficient vector assembly, put all calls to x[...] = ... inside
# assemble(x) do ... end
 """
  Start communication to assemble stashed values into the vector

  The MatAssemblyType is not needed for vectors, but is provided for
  compatibility with the Mat case.

  Unless vec.verify_assembled == false, users must *never* call the
  C functions VecAssemblyBegin, VecAssemblyEnd and VecSetValues, they must
  call AssemblyBegin, AssemblyEnd, and setindex!.
"""
function AssemblyBegin(x::Vec, t::C.MatAssemblyType=C.MAT_FINAL_ASSEMBLY)
  chk(C.VecAssemblyBegin(x.p))
end

"""
  Generic fallback for AbstractArray, no-op
"""
function AssemblyBegin(x::AbstractArray, t::C.MatAssemblyType=C.MAT_FINAL_ASSEMBLY)

end
 """
  Finish communication for assembling the vector
"""
function AssemblyEnd(x::Vec, t::C.MatAssemblyType=C.MAT_FINAL_ASSEMBLY)
  chk(C.VecAssemblyEnd(x.p))
  x.assembled = true
end

"""
  Check if a vector is assembled (ie. does not have stashed values).  If
  `x.verify_assembled`, the assembly state of all processes is checked,
  otherwise only the local process is checked. `local_only` forces only
  the local process to be checked, regardless of `x.verify_assembled`.
"""
function isassembled(x::Vec, local_only=false)
  myrank = MPI.Comm_rank(comm(x))
  if x.verify_assembled && !local_only
    val = MPI.Allreduce(Int8(x.assembled), MPI.LAND, comm(x))
  else
    val = x.assembled
  end

  return Bool(val)
end

"""
  Generic fallback for AbstractArray, no-op
"""
function AssemblyEnd(x::AbstractArray, t::C.MatAssemblyType=C.MAT_FINAL_ASSEMBLY)

end

isassemble(x::AbstractArray) = true
# assemble(f::Function, x::Vec) is defined in mat.jl

 """
  Like setindex, but requires the indices be 0-base
"""
function setindex0!(x::Vec{T}, v::Array{T}, i::Array{PetscInt}) where {T}
  n = length(v)
  if n != length(i)
    throw(ArgumentError("length(values) != length(indices)"))
  end
  #    println("  in setindex0, passed bounds check")
  chk(C.VecSetValues(x.p, n, i, v, x.insertmode))
  x.assembled = false
  x
end

function setindex!(x::Vec{T}, v::Number, i::Integer) where {T}
  # can't call VecSetValue since that is a static inline function
  setindex0!(x, T[ v ], PetscInt[ i - 1 ])
  v
end

# set multiple entries to a single value
setindex!(x::Vec, v::Number, I::AbstractArray{T}) where {T<:Integer} = assemble(x) do
  for i in I
    x[i] = v
  end
  x
end

function Base.fill!(x::Vec{T}, v::Number) where {T}
  chk(C.VecSet(x.p, T(v)))
  return x
end

function setindex!(x::Vec, v::Number, I::AbstractRange{T}) where {T<:Integer}
  if abs(step(I)) == 1 && minimum(I) == 1 && maximum(I) == length(x)
    fill!(x, v)
    return v
  else
    # use invoke here to avoid a recursion loop
    return invoke(setindex!, Tuple{Vec,typeof(v),AbstractVector{T}}, x,v,I)
  end
end

#TODO: make this a single call to VecSetValues
setindex!(x::Vec, V::AbstractArray, I::AbstractArray{T}) where {T<:Real} =
assemble(x) do
  if length(V) != length(I)
    throw(ArgumentError("length(values) != length(indices)"))
  end
  # possibly faster to make a PetscScalar array from V, and
  # a copy of the I array shifted by 1, to call setindex0! instead?
  c = 1
  for i in I
    x[i] = V[c]
    c += 1
  end
  x
end

# logical indexing
setindex!(A::Vec, x::Number, I::AbstractArray{Bool}) = assemble(A) do
  for i = 1:length(I)
    if I[i]
      A[i] = x
    end
  end
  A
end
for T in (:(Array{T2}),:(AbstractArray{T2})) # avoid method ambiguities
  @eval setindex!(A::Vec, X::$T, I::AbstractArray{Bool}) where {T2<:Scalar} = assemble(A) do
    c = 1
    for i = 1:length(I)
      if I[i]
        A[i] = X[c]
        c += 1
      end
    end
    A
  end
end

##########################################################################
import Base.getindex

# like getindex but for 0-based indices i
function getindex0(x::Vec{T}, i::Vector{PetscInt}) where {T}
  v = similar(i, T)
  chk(C.VecGetValues(x.p, length(i), i, v))
  v
end

getindex(x::Vec, i::Integer) = getindex0(x, PetscInt[i-1])[1]

getindex(x::Vec, I::AbstractVector{PetscInt}) =
  getindex0(x, PetscInt[ (i-1) for i in I ])

##########################################################################
# more indexing
# 0-based (to avoid temporary copies)
export set_values!, set_values_blocked!, set_values_local!, set_values_blocked_local!

#TODO: in 0.5, use boundscheck macro to verify stride=1

function set_values!(x::Vec{T}, idxs::StridedVecOrMat{PetscInt},
                                 vals::StridedVecOrMat{T}, o::C.InsertMode=x.insertmode) where {T <: Scalar}

  chk(C.VecSetValues(x.p, length(idxs), idxs, vals, o))
end

function set_values!(x::Vec{T}, idxs::StridedVecOrMat{I},
                                         vals::StridedVecOrMat{T}, o::C.InsertMode=x.insertmode) where {T <: Scalar, I <: Integer}

  # convert idxs to PetscInt
  p_idxs = PetscInt[ i for i in idxs]
  set_values!(x, p_idxs, vals, o)
end

function set_values!(x::AbstractVector, idxs::AbstractArray, vals::AbstractArray,
                     o::C.InsertMode=C.INSERT_VALUES)

  if o == C.INSERT_VALUES
    for i=1:length(idxs)
      x[idxs[i] + 1] = vals[i]
    end
  elseif o == C.ADD_VALUES
    for i=1:length(idxs)
      x[idxs[i] + 1] += vals[i]
    end
  else
    throw(ArgumentError("Unsupported InsertMode"))
  end
end


function set_values_blocked!(x::Vec{T}, idxs::StridedVecOrMat{PetscInt},
                                          vals::StridedVecOrMat{T}, o::C.InsertMode=x.insertmode) where {T <: Scalar}

  chk(C.VecSetValuesBlocked(x.p, length(idxs), idxs, vals, o))
end

function set_values_blocked!(x::Vec{T},
                             idxs::StridedVecOrMat{I}, vals::StridedVecOrMat{T},
                             o::C.InsertMode=x.insertmode) where {T <: Scalar, I <: Integer}

  p_idxs = PetscInt[ i for i in idxs]
  set_values_blocked!(x, p_idxs, vals, o)
end

# julia doesn't have blocked vectors, so skip


function set_values_local!(x::Vec{T}, idxs::StridedVecOrMat{PetscInt},
                                       vals::StridedVecOrMat{T}, o::C.InsertMode=x.insertmode) where {T <: Scalar}

  chk(C.VecSetValuesLocal(x.p, length(idxs), idxs, vals, o))
end

function set_values_local!(x::Vec{T},
                           idxs::StridedVecOrMat{I}, vals::StridedVecOrMat{T},
                           o::C.InsertMode=x.insertmode) where {T <: Scalar, I <: Integer}

  p_idxs = PetscInt[ i for i in idxs]
  set_values_local!(x, p_idxs, vals, o)
end

# for julia vectors, local = global
function set_values_local!(x::AbstractArray, idxs::AbstractArray,
                           vals::AbstractArray, o::C.InsertMode=C.INSERT_VALUES)

  if o == C.INSERT_VALUES
    for i=1:length(idxs)
      x[idxs[i] + 1] = vals[i]
    end
  elseif o == C.ADD_VALUES
    for i=1:length(idxs)
      x[idxs[i] + 1] += vals[i]
    end
  else
    throw(ArgumentError("Unsupported InsertMode"))
  end

end


function set_values_blocked_local!(x::Vec{T},
                                   idxs::StridedVecOrMat{PetscInt},
                                   vals::StridedVecOrMat{T}, o::C.InsertMode=x.insertmode) where {T <: Scalar}

  chk(C.VecSetValuesBlockedLocal(x.p, length(idxs), idxs, vals, o))
end


function set_values_blocked_local!(x::Vec{T},
                           idxs::StridedVecOrMat{I}, vals::StridedVecOrMat{T},
                           o::C.InsertMode=x.insertmode) where {T <: Scalar, I <: Integer}

  p_idxs = PetscInt[ i for i in idxs]
  set_values_blocked_local!(x, p_idxs, vals, o)
end

# julia doesn't have blocked vectors, so skip







###############################################################################
import Base: abs, exp, log, conj, conj!
export abs!, exp!, log!
for (f,pf) in ((:abs,:VecAbs), (:exp,:VecExp), (:log,:VecLog),
  (:conj,:VecConjugate))
  fb = Symbol(string(f, "!"))
  @eval begin
    function $fb(x::Vec)
      chk(C.$pf(x.p))
      x
    end
    $f(x::Vec) = $fb(copy(x))
  end
end

export chop!
function chop!(x::Vec, tol::Real)
  chk(C.VecChop(x.p, tol))
#  chk(ccall((:VecChop, petsc), PetscErrorCode, (pVec, PetscReal), x, tol))
  x
end

for (f, pf, sf) in ((:findmax, :VecMax, :maximum), (:findmin, :VecMin, :minimum))
  @eval begin
    function Base.$f(x::Vec{T}) where {T<:Real}
      i = Ref{PetscInt}()
      v = Ref{T}()
      chk(C.$pf(x.p, i, v))
      (v[], i[]+1)
    end
    Base.$sf(x::Vec{T}) where {T<:Real} = $f(x)[1]
  end
end
# For complex numbers, VecMax and VecMin apparently return the max/min
# real parts, which doesn't match Julia's maximum/minimum semantics.
function LinearAlgebra.norm(x::Union{Vec{T},Vec{Complex{T}}}, p::Real) where {T<:Real}
  v = Ref{T}()
  n = p == 1 ? C.NORM_1 : p == 2 ? C.NORM_2 : p == Inf ? C.NORM_INFINITY :
  throw(ArgumentError("unrecognized Petsc norm $p"))
  chk(C.VecNorm(x.p, n, v))
  v[]
end

#if VERSION >= v"0.5.0-dev+8353" # JuliaLang/julia#13681
#  import Base.normalize!
#else
#  export normalize!
#end

 """
  computes v = norm(x,2), divides x by v, and returns v
"""
#function normalize!(x::Union{Vec{T},Vec{Complex{T}}}) where {T<:Real}
#  v = Ref{T}()
#  chk(C.VecNormalize(x.p, v))
#  v[]
#end

function LinearAlgebra.dot(x::Vec{T}, y::Vec{T}) where {T}
  d = Ref{T}()
  chk(C.VecDot(y.p, x.p, d))
  return d[]
end

# unconjugated dot product (called for x'*y)
#function LinearAlgebra.At_mul_B(x::Vec{T}, y::Vec{T}) where {T<:Complex}
#  d = Array(1)
#  chk(C.VecTDot(x.p, y.p, d))
#  return d
#end

# pointwise operations on pairs of vectors (TODO: support in-place variants?)
import Base: broadcast
#for (f,pf) in ((:max,:VecPointwiseMax), (:min,:VecPointwiseMin),
#  (:.*,:VecPointwiseMult), (:./,:VecPointwiseDivide))
#  @eval function broadcast(::typeof($f), x::Vec, y::Vec)
#    w = similar(x)
#    chk(C.$pf(w.p, x.p, y.p))
#    w
#  end
#end

import Base: +, -, *, /, \
export scale!
function scale!(x::Vec{T}, s::Number) where {T}
  chk(C.VecScale(x.p, T(s)))
  x
end
scale(x::Vec{T},s::Number) where {T} = scale!(copy(x),s)
(*)(x::Vec, a::Number...) = scale(x, prod(a))
(*)(a::Number, x::Vec) = scale(x, a)
(/)(x::Vec, a::Number) = scale(x, inv(a))
(\)(a::Number, x::Vec) = scale(x, inv(a))
function Base.broadcast(::typeof(/), a::Number, x::Vec)
  y = copy(x)
  chk(C.VecReciprocal(y.p))
  if a != 1.0
    scale!(y, a)
  end
  y
end

function (+)(x::Vec{T}, a::Number...) where {T<:Scalar}
  y = copy(x)
  chk(C.VecShift(y.p, T(sum(a))))
  return y
end
(+)(a::Number, x::Vec{T}) where {T<:Scalar} = x + a
(-)(x::Vec{T}, a::Number) where {T<:Scalar} = x + (-a)
(-)(x::Vec) = scale(x, -1)
function (-)(a::Number, x::Vec{T}) where {T<:Scalar}
  y = -x
  chk(C.VecShift(y.p, T(a)))
  return y
end

import Base: ==
function (==)(x::Vec, y::Vec)
  b = Ref{PetscBool}()
  chk(C.VecEqual(x.p, y.p, b))
  b[] != 0
end

function (==)(x::Vec, y::AbstractArray)
  flag = true
  x_arr = LocalVector(x)
  for i=1:length(x_arr)  # do localpart, then MPI reduce
    flag = flag && x_arr[i] == y[i]
  end
  restore(x_arr)

  buf = Int8[flag]
  # process 0 is root
  recbuf = MPI.Reduce(buf, MPI.LAND, 0, comm(x))

  if  MPI.Comm_rank(comm(x)) == 0
    buf[1] = recbuf[1]
  end

  MPI.Bcast!(buf, 1, 0, comm(x))

  return convert(Bool, buf[1])
end

function Base.sum(x::Vec{T}) where {T}
  s = Ref{T}()
  chk(C.VecSum(x.p, s))
  s[]
end

###############################################################################
# map and friends
import Base: map!, map
#map() should be inherited from base

function map!(f, c)
  map!(f, c, c)
end

"""
Applys f element-wise to src to populate dest.  If src is a ghost vector,
then f is applied to the ghost elements as well as the local elements.
"""
function map!(f::F, dest::Vec{T}, src::Vec) where {T,F}
  if length(dest) < length(src)
    throw(ArgumentError("Length of dest must be >= src"))
  end
  if localpart(dest)[1] != localpart(src)[1]
    throw(ArgumentError("start of local part of src and dest must be aligned"))
  end

  dest_arr = LocalVector(dest)
  src_arr = LocalVector_readonly(src)
  try
    for (idx, val) in enumerate(src)
      dest[idx] = f(val)
    end
  finally
    restore(dest_arr)
    restore(src_arr)
  end
end

"""
  Multiple source vector map.  All vectors must have the local and global
  lengths.  If some a ghost vectors and some are not, the map is applied
  only to the local part
"""
function map!(f::F, dest::Vec{T}, src1::Vec{T}, src2::Vec{T2},  src_rest::Vec{T2}...) where {F,T,T2}

  # annoying workaround for #13651
  srcs = (src1, src2, src_rest...)
  # check lengths
  dest_localrange = localpart(dest)
  dest_len = length(dest)
  for src in srcs
    srclen = length(src)
    srcrange_local = localpart(src)
    if dest_len < srclen
      throw(ArgumentError("Length of destination must be greater than source"))
    end

    if dest_localrange[1] != srcrange_local[1]
      throw(ArgumentError("start of local part of src and dest must be aligned"))
    end
  end

  # extract the arrays
  n = length(srcs)
  len = 0
  len_prev = 0
  src_arrs = Array{LocalVectorRead{T2},1}(undef,n)
  use_length_local = false

  dest_arr = LocalVector(dest)
  try
    for (idx, src) in enumerate(srcs)
      src_arrs[idx] = LocalVector_readonly(src)

      # check of length of arrays are same or not
      len = length(src_arrs[idx])
      if len != len_prev && idx != 1 && !use_length_local
        use_length_local = true
      end
      len_prev = len
    end

    # if not all same, do only the local part (which must be the same for all)
    if use_length_local
      min_length = lenth(src1)
    else
      min_length = length(src_arrs[1])
    end
      # do the map
      vals = Array{T,1}(undef,n)
      for i=1:min_length  # TODO: make this the minimum array length
        for j=1:n  # extract values
          vals[j] = src_arrs[j][i]
        end
        dest_arr[i] = f(vals...)
      end
  finally # restore the arrays
    for src_arr in src_arrs
      restore(src_arr)
    end
    restore(dest_arr)
  end
end

##########################################################################
export axpy!, aypx!, axpby!, axpbypcz!
import LinearAlgebra.BLAS.axpy!
import LinearAlgebra.BLAS.axpby!

# y <- alpha*x + y
function axpy!(alpha::Number, x::Vec{T}, y::Vec{T}) where {T}
  chk(C.VecAXPY(y.p, T(alpha), x.p))
  y
end
# w <- alpha*x + y
function axpy!(alpha::Number, x::Vec{T}, y::Vec{T}, w::Vec{T}) where {T}
  chk(C.VecWAXPY(w.p, T(alpha), x.p, y.p))
  y
end
# y <- alpha*y + x
function aypx!(x::Vec{T}, alpha::Number, y::Vec{T}) where {T}
  chk(C.VecAYPX( y.p, T(alpha), x.p))
  y
end
# y <- alpha*x + beta*y
function axpby!(alpha::Number, x::Vec{T}, beta::Number, y::Vec{T}) where {T}
  chk(C.VecAXPBY(y.p, T(alpha), T(beta), x.p))
  y
end
# z <- alpha*x + beta*y + gamma*z
function axpbypcz!(alpha::Number, x::Vec{T}, beta::Number, y::Vec{T},
  gamma::Number, z::Vec{T}) where {T}
  chk(C.VecAXPBYPCZ(z.p, T(alpha), T(beta), T(gamma), x.p, y.p))
  z
end

# y <- y + \sum_i alpha[i] * x[i]
function axpy!(y::V, alpha::AbstractArray, x::AbstractArray{V}) where {V<:Vec}
  n = length(x)
  length(alpha) == n || throw(BoundsError())
  _x = [X.p for X in x]
  _alpha = eltype(y)[a for a in alpha]
  C.VecMAXPY(y.p, n, _alpha, _x)
  y
end

##########################################################################
# element-wise vector operations:
# import Base: .*, ./, .^, +, -

#for (f,pf) in ((:.*,:VecPointwiseMult), (:./,:VecPointwiseDivide), (:.^,:VecPow))
#  @eval function ($f)(x::Vec, y::Vec)
#    z = similar(x)
#    chk(C.$pf(z.p, x.p, y.p))
#    return z
#  end
#end

for (f,s) in ((:+,1), (:-,-1))
  @eval function ($f)(x::Vec{T}, y::Vec{T}) where {T}
    z = similar(x)
    chk(C.VecWAXPY(z.p, T($s), y.p, x.p))
    return z
  end
end


##############################################################################
export LocalVector, LocalVector_readonly, restore

 """
  Object representing the local part of the array, accessing the memory directly.
  Supports all the same indexing as a regular Array
"""
mutable struct LocalVector{T <: Scalar, ReadOnly} <: DenseArray{T, 1}
  a::Array{T, 1}  # the array object constructed around the pointer
  ref::Ref{Ptr{T}}  # reference to the pointer to the data
  pobj::C.Vec{T}
  isfinalized::Bool  # has this been finalized yet
  function LocalVector{T,ReadOnly}(a::Array{T}, ref::Ref, ptr) where {T,ReadOnly}
    varr = new{T,ReadOnly}(a, ref, ptr, false)
    # backup finalizer, shouldn't ever be used because users must call
    # restore before their changes will take effect
    finalizer(restore, varr)
    return varr
  end

end

const LocalVectorRead{T}=LocalVector{T, true}
const LocalVectorWrite{T}=LocalVector{T, false}

"""
  Get the LocalVector of a vector.  Users must call restore when
  finished updating the vector
"""
function LocalVector(vec::Vec{T}) where {T}

  len = lengthlocal(vec)

  ref = Ref{Ptr{T}}()
  chk(C.VecGetArray(vec.p, ref))
  a = unsafe_wrap(Array, ref[], len)
  return LocalVector{T, false}(a, ref, vec.p)
end

"""
  Get the LocalVector of a vector.  Users must call restore when
  finished updating the vector
"""
function LocalVector(vec::Vec{T},len::Int) where {T}
  ref = Ref{Ptr{T}}()
  chk(C.VecGetArray(vec.p, ref))
  a = unsafe_wrap(Array, ref[], len)
  return LocalVector{T, false}(a, ref, vec.p)
end


"""
  Tell Petsc the LocalVector is no longer being used
"""
function restore(varr::LocalVectorWrite{T}) where {T}

  if !varr.isfinalized && !PetscFinalized(T) && !isfinalized(varr.pobj)
    ptr = varr.ref
    chk(C.VecRestoreArray(varr.pobj, ptr))
  end
  varr.isfinalized = true
end

"""
  Get the LocalVector_readonly of a vector.  Users must call restore when
  finished with the object.
"""
function LocalVector_readonly(vec::Vec{T}) where {T}

  len = lengthlocal(vec)

  ref = Ref{Ptr{T}}()
  chk(C.VecGetArrayRead(vec.p, ref))
  a = unsafe_wrap(Array, ref[], len)
  return LocalVector{T, true}(a, ref, vec.p)
end

function restore(varr::LocalVectorRead{T}) where {T}

  if !varr.isfinalized && !PetscFinalized(T) && !isfinalized(varr.pobj)
    ptr = [varr.ref[]]
    chk(C.VecRestoreArrayRead(varr.pobj, ptr))
  end
  varr.isfinalized = true
end

Base.size(varr::LocalVector) = size(varr.a)
# indexing
getindex(varr::LocalVector, i) = getindex(varr.a, i)
setindex!(varr::LocalVectorWrite, v, i) = setindex!(varr.a, v, i)
Base.unsafe_convert(::Type{Ptr{T}}, a::LocalVector{T}) where {T} = Base.unsafe_convert(Ptr{T}, a.a)
Base.stride(a::LocalVector, d::Int64) = stride(a.a, d)
Base.similar(a::LocalVector, T::Type=eltype(a), dims::Dims{1}=size(a)) = similar(a.a, T, dims)

function (==)(x::LocalVector, y::AbstractArray)
  return x.a == y
end
