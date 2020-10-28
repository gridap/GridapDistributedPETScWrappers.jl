include("runtests_setup.jl")
println("testing types: ", GridapDistributedPETScWrappers.C.petsc_type)
for (i, ST) in enumerate(GridapDistributedPETScWrappers.C.petsc_type)
  if GridapDistributedPETScWrappers.have_petsc[i]
    println("testing datatype ", ST)
  # @testset "Scalar type $ST" begin # uncomment when nested test results can be printed
    include("error.jl")
    include("ksp.jl")
    include("vec.jl")
    include("is.jl")
    include("mat.jl")
    #include("ts.jl")
  end
  # end
end

#@test GridapDistributedPETScWrappers.petsc_sizeof(GridapDistributedPETScWrappers.C.PETSC_BOOL) == 4
