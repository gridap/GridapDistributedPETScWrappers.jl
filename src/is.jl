# index sets and vector scatters

###########################################################################
export IS, ISBlock # index sets
# Note: we expose a 1-base Julian index interface, but internally
# PETSc's indices are 0-based.
#TODO: support block versions
mutable struct IS{T}
  p::C.IS{T}
  function IS{T}(p::C.IS{T}) where {T}
    o = new{T}(p)
    #finalizer(PetscDestroy,o)
    return o
  end
end

comm(a::IS{T}) where{T} = MPI.Comm(C.PetscObjectComm(T, a.p.pobj))

function PetscDestroy(o::IS{T}) where{T}
  PetscFinalized(T) || C.ISDestroy(Ref(o.p))
end

# internal constructor, takes array of zero-based indices:
function IS_(::Type{T}, idx::Array{PetscInt}; comm::MPI.Comm=MPI.COMM_WORLD) where {T<:Scalar}
  is_c = Ref{C.IS{T}}()
  chk(C.ISCreateGeneral(comm, length(idx), idx, C.PETSC_COPY_VALUES, is_c))
  return IS{T}(is_c[])
end

IS(::Type{T}, idx::AbstractArray{I}; comm::MPI.Comm=MPI.COMM_WORLD) where {I<:Integer, T<:Scalar} =
  IS_(T, PetscInt[i-1 for i in idx]; comm=comm)

function IS(::Type{T}, idx::AbstractRange{I}; comm::MPI.Comm=MPI.COMM_WORLD) where {I<:Integer, T<:Scalar}
  is_c = Ref{C.IS{T}}()
  chk(C.ISCreateStride(comm, length(idx), first(idx)-1, step(idx), is_c))
  return IS{T}(is_c[])
end

# there is no Strided block index set, so convert everything to an array
function ISBlock(::Type{T}, bs::Integer,  idx::AbstractArray{I}; comm=MPI.COMM_WORLD) where {I<:Integer, T<:Scalar}
  idx_0 = PetscInt[i-1 for i in idx]
  return ISBlock_(T, bs, idx_0, comm=comm)
end

function ISBlock_(::Type{T}, bs::Integer, idx::AbstractArray{PetscInt};comm=MPI.COMM_WORLD) where {T}
  is_c = Ref{C.IS{T}}()
  chk(C.ISCreateBlock(comm, bs, length(idx), idx, C.PETSC_COPY_VALUES, is_c))
  return IS{T}(is_c[])
end


function Base.copy(i::IS{T}) where {T}
  is_c = Ref{C.IS{T}}()
  chk(C.ISDuplicate(i.p, is_c))
  return IS{T}(is_c[])
end

function Base.length(i::IS)
  len = Ref{PetscInt}()
  chk(C.ISGetSize(i.p, len))
  return Int(len[])
end

function lengthlocal(i::IS)
  len = Ref{PetscInt}()
  chk(C.ISGetLocalSize(i.p, len))
  return Int(len[])
end

import Base.==
function ==(i::IS{T}, j::IS{T}) where {T}
  b = Ref{PetscBool}()
  chk(C.ISEqual(i.p, j.p, b))
  return b[] != 0
end

function Base.sort!(i::IS)
  chk(C.ISSort(i.p))
  return i
end
Base.sort(i::IS) = sort!(copy(i))

function Base.issorted(i::IS)
  b = Ref{PetscBool}()
  chk(C.ISSorted(i.p, b))
  return b[] != 0
end

function Base.union(i::IS{T}, j::IS{T}) where {T}
  is_c = Ref{C.IS{T}}()
  chk(C.ISExpand(i.p, j.p, is_c))
  return IS{T}(is_c[])
end

function Base.setdiff(i::IS{T}, j::IS{T}) where {T}
  is_c = Ref{C.IS{T}}()
  chk(C.ISDifference(i.p, j.p, is_c))
  return IS{T}(is_c[])
end

function Base.extrema(i::IS) where {T}
  min = Ref{PetscInt}()
  max = Ref{PetscInt}()
  chk(C.ISGetMinMax(i.p, min, max))
  return (Int(min[])+1, Int(max[])+1)
end
Base.minimum(i::IS) = extrema(i)[1]
Base.maximum(i::IS) = extrema(i)[2]

function Base.convert(::Type{Vector{T}}, idx::IS) where {T<:Integer}
  pref = Ref{Ptr{PetscInt}}()
  chk(C.ISGetIndices(idx.p, pref))
  inds = Int[i+1 for i in unsafe_wrap(Array, pref[], lengthlocal(idx))]
  chk(C.ISRestoreIndices(idx.p, pref))
  return inds
end
Base.Set(i::IS) = Set(Vector{Int}(i))
Base.Vector{T}(i::IS) where T<:Integer = convert(Vector{T},i)
export set_blocksize, get_blocksize

function set_blocksize(is::IS, bs::Integer)
  chk(C.ISSetBlockSize(is.p, bs))
end

function get_blocksize(is::IS)
  bs = Ref{PetscInt}()
  chk(C.ISGetBlockSize(is.p, bs))
  return Int(bs[])
end

function petscview(is::IS{T}) where {T}
  viewer = C.PetscViewer{T}(C_NULL)
  chk(C.ISView(is.p, viewer))
end


###############################################################################
# we expose a 1 based API, but internally ISLoalToGlobalMappings are zero based

export ISLocalToGlobalMapping

mutable struct ISLocalToGlobalMapping{T}
  p::C.ISLocalToGlobalMapping{T}
  function ISLocalToGlobalMapping{T}(p::C.ISLocalToGlobalMapping{T}) where {T}
    o = new{T}(p)
    #finalizer(PetscDestroy,o)
    return o
  end
end


# zero based, not exported
function _ISLocalToGlobalMapping(::Type{T}, indices::AbstractArray{PetscInt}, bs=1; comm=MPI_COMM_WORLD, copymode=C.PETSC_COPY_VALUES) where {T}

  isltog = Ref{C.ISLocalToGlobalMapping}()
  chk(C.ISLocalToGlobalMappingCreate(comm, bs, length(indices), indices, copymode, isltog))

  return ISLocalToGlobalMapping(isltog[])
end

# one based, exported
#TODO: add a data argument to ISLocalToGlobalMapping, to store intermediate
# array for copymode = don't copy
function ISLocalToGlobalMapping(::Type{T}, indices::AbstractArray{I}, bs=1; comm=MPI_COMM_WORLD, copymode=C.PETSC_COPY_VALUES) where {T, I <: Integer}

  indices_0 = PetscInt[ i-1 for i in indices]
  return _ISLocalToGlobalMapping(t, indices, bs=bs, comm=comm, copymode=copymode)

end

function ISLocalToGlobalMapping(is::IS{T})  where {T}

  isltog = Ref{C.ISLocalToGlobalMapping{T}}()
  chk(C.ISLocalToGlobalMappingCreateIS(is.p, isltog))
  return ISLocalToGlobalMapping{T}(isltog[])
end


comm(a::ISLocalToGlobalMapping{T}) where {T} = MPI.Comm(C.PetscObjectComm(T, a.p.pobj))

function PetscDestroy(o::ISLocalToGlobalMapping{T}) where {T}
  PetscFinalized(T) || C.ISLocalToGlobalMappingDestroy(Ref(o.p))
end

function petscview(is::ISLocalToGlobalMapping{T}) where {T}
  viewer = C.PetscViewer{T}(C_NULL)
  chk(C.ISLocalToGlobalMappingView(is.p, viewer))
end
