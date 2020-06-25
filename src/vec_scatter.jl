###########################################################################
export VecScatter

# describes a scatter operation context (input/output index sets etc.)
 mutable struct VecScatter{T}
  p::C.VecScatter{T}

  function VecScatter{T}(p::C.VecScatter{T}) where {T}
    o = new{T}(p)
    #finalizer(VecScatterDestroy, o)
    return o
  end
end

comm(a::VecScatter{T}) where {T} = MPI.Comm(C.PetscObjectComm(T, a.p.pobj))

function VecScatterDestroy(o::VecScatter{T}) where {T}
  PetscFinalized(T) || C.VecScatterDestroy(Ref(o.p))
end

function VecScatter(x::Vec{T}, ix::IS{T}, y::Vec{T}, iy::IS{T}) where {T}
  scatter_c = Ref{C.VecScatter{T}}()
  chk(C.VecScatterCreate(x.p, ix.p, y.p, iy.p, scatter_c))
  return VecScatter{T}(scatter_c[])
end

function Base.copy(i::VecScatter{T}) where {T}
  vs_c = Ref{C.VecScatter{T}}()
  chk(C.VecScatterCopy(i.p, vs_c))
  return VecScatter{T}(vs_c[])
end

###########################################################################
export scatter!

function scatter!(scatter::VecScatter{T}, x::Vec{T}, y::Vec{T}; imode=C.INSERT_VALUES, smode=C.SCATTER_FORWARD) where {T}
  chk(C.VecScatterBegin(scatter.p, x.p, y.p, imode, smode))
  yield() # do async computations while messages are in transit
  chk(C.VecScatterEnd(scatter.p, x.p, y.p, imode, smode))
  return y
end

function scatter!(x::Vec{T}, ix::AbstractVector{I1},
                           y::Vec{T}, iy::AbstractVector{I2};
                          imode=C.INSERT_VALUES, smode=C.SCATTER_FORWARD) where {T,I1,I2}
  scatter = VecScatter(x, IS(T, ix, comm=comm(x)),
                       y, IS(T, iy, comm=comm(y)))
  scatter!(scatter, x, y; imode=imode, smode=smode)
end
