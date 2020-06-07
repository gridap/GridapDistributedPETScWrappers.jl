# interface to the PETSc options database(s), by providing an OPTIONS[T]
# dictionary-like object that is analogous to the Julia Base.ENV object
# for environment variables.

mutable struct Options{T<:Scalar} <: AbstractDict{String,String}; end
const OPTIONS = Dict(T => Options{T}() for T in C.petsc_type)
export OPTIONS, withoptions

const SymOrStr = Union{AbstractString,Symbol}

function Base.setindex!(::Options{T}, v, k::SymOrStr) where {T}
  chk(C.PetscOptionsSetValue(T, string('-',k), string(v)))
  return v
end

function Base.setindex!(::Options{T}, v::Cvoid, k::SymOrStr) where {T}
  chk(C.PetscOptionsClearValue(T, string('-',k)))
  return v
end

# PETSc complains if you don't use an option, remove this?
# allow OPTIONS[k]=v to set options for all PETSc scalar types simultaneously
function Base.setindex!(o::typeof(OPTIONS), v, k::SymOrStr)
  for opts in values(o)
    opts[k] = v
  end
  return v
end

const _optionstr = fill(UInt8(0),1024)
function Base.get(::Options{T}, k::SymOrStr, def) where {T}
  b = Ref{PetscBool}()
  chk(C.PetscOptionsGetString(T, Cstring(Ptr{UInt8}(C_NULL)), string('-',k),
                              pointer(_optionstr), Csize_t(length(_optionstr)),
                              b))
  return b[] != 0 ? unsafe_string(pointer(_optionstr)) : def
end

function Base.haskey(::Options{T}, k::SymOrStr) where {T}
  b = Ref{PetscBool}()
  chk(C.PetscOptionsHasName(T, Cstring(Ptr{UInt8}(C_NULL)), string('-',k), b))
  return b[] != 0
end

Base.similar(::Options) = Dict{String,String}()

Base.pop!(o::Options, k::SymOrStr) = (v = o[k]; o[k] = nothing; v)
Base.pop!(o::Options, k::SymOrStr, def) = haskey(o,k) ? pop!(o,k) : def
Base.delete!(o::Options, k::SymOrStr) = (o[k] = nothing; o)
Base.delete!(o::Options, k::SymOrStr, def) = haskey(o,k) ? delete!(o,k) : def

# need to override show: default show function doesn't work because
# there seems to be no way to iterate over the PETSc options database (grr).
Base.show(io::IO, ::Options{T})  where {T} = print(io, "PETSc{$T} options database")

# temporarily set some options, call f, and then unset them; like withenv
function withoptions(f::Function, ::Type{T}, keyvals) where {T<:Scalar}
  old = Dict{SymOrStr,Any}()
  o = OPTIONS[T]
  for (key,val) in keyvals
    old[key] = get(o,key,nothing)
    val !== nothing ? (o[key]=val) : delete!(o, key)
  end
  try f()
  finally
    for (key,val) in old
      val !== nothing ? (o[key]=val) : delete!(o, key)
    end
  end
end
withoptions(f::Function, ::Type{T}, keyvals::Pair{K}...) where {T<:Scalar,K<:SymOrStr} = withoptions(f, T, keyvals)
withoptions(f::Function, ::Type{T}) where {T<:Scalar} = f() # handle empty keyvals case; see julia#10853
