@testset "C functions {$ST}" begin

 v_ptr = GridapDistributedPETScWrappers.C.VecCreate(ST)
 chk(GridapDistributedPETScWrappers.C.VecSetType(v_ptr, GridapDistributedPETScWrappers.C.VECMPI))
 b = Vec{ST}(v_ptr)
 resize!(b, mlocal=sys_size)
 global_indices = first(localpart(b))-1:last(localpart(b))-1  # zero based
  for i=1:sys_size
    idxm = [global_indices[i] ]
    val = [ rhs[i] ]
    GridapDistributedPETScWrappers.C.SetValues(b.p, idxm, val)
  end

  GridapDistributedPETScWrappers.C.AssemblyBegin(b.p)
  GridapDistributedPETScWrappers.C.AssemblyEnd(b.p)

   for i=1:sys_size
    idxm = [global_indices[i] ]
    val = ST[ 0.0 ]
    GridapDistributedPETScWrappers.C.GetValues(b.p, idxm, val)
    @test val[1] == rhs[i]
  end

  # matrix
  A = Mat(ST, mlocal=sys_size, nlocal=sys_size)
  row_range, col_range = localranges(A)

  for i=1:sys_size
    for j=1:sys_size
      row_idx = GridapDistributedPETScWrappers.C.PetscInt[ row_range[i] - 1 ]
      col_idx = GridapDistributedPETScWrappers.C.PetscInt[ row_range[j] - 1 ]
      val = ST[ A_julia[i, j] ]
      GridapDistributedPETScWrappers.C.SetValues(A.p, row_idx, col_idx, val)
    end
  end

  GridapDistributedPETScWrappers.C.AssemblyBegin(A.p)
  GridapDistributedPETScWrappers.C.AssemblyEnd(A.p)

  for i=1:sys_size
    for j=1:sys_size
      row_idx = GridapDistributedPETScWrappers.C.PetscInt[ row_range[i] - 1 ]
      col_idx = GridapDistributedPETScWrappers.C.PetscInt[ row_range[j] - 1 ]
      val = ST[ 0.0 ]
      GridapDistributedPETScWrappers.C.GetValues(A.p, row_idx, col_idx, val)
      @test val[1] == A_julia[i, j]
    end
  end

  idx = collect(first(row_range)-1:last(row_range)-1)
  vals = collect(1:(sys_size*sys_size))
  vals2 = convert(Array{ST, 1}, vals)
  GridapDistributedPETScWrappers.C.SetValues(A.p, idx, idx, vals2)
  GridapDistributedPETScWrappers.C.AssemblyBegin(A.p)
  GridapDistributedPETScWrappers.C.AssemblyEnd(A.p)


  for i=1:sys_size
    for j=1:sys_size
      row_idx = GridapDistributedPETScWrappers.C.PetscInt[ row_range[i] - 1 ]
      col_idx = GridapDistributedPETScWrappers.C.PetscInt[ row_range[j] - 1 ]
      val = ST[ 0.0 ]
      GridapDistributedPETScWrappers.C.GetValues(A.p, row_idx, col_idx, val)
      @test val[1] == (i + (j-1)*sys_size)
    end
  end



  # block matrix
  B = Mat(ST, mlocal=sys_size, nlocal=sys_size, bs=sys_size, mtype=GridapDistributedPETScWrappers.C.MATMPIBAIJ)
  idx = GridapDistributedPETScWrappers.C.PetscInt[comm_rank]
  GridapDistributedPETScWrappers.C.SetValues(B.p, idx, idx, vals2)
  GridapDistributedPETScWrappers.C.AssemblyBegin(B.p)
  GridapDistributedPETScWrappers.C.AssemblyEnd(B.p)
  for i=1:sys_size
    for j=1:sys_size
      row_idx = GridapDistributedPETScWrappers.C.PetscInt[ row_range[i] - 1 ]
      col_idx = GridapDistributedPETScWrappers.C.PetscInt[ row_range[j] - 1 ]
      val = ST[ 0.0 ]
      GridapDistributedPETScWrappers.C.GetValues(A.p, row_idx, col_idx, val)
      @test val[1] == (i + (j-1)*sys_size)
    end
  end

  # shell matrix
  # if ST == Float64
  #   ctx = (1, 2, 3)
  #   ctx_ptr = pointer_from_objref(ctx)
  #   c_ptr = GridapDistributedPETScWrappers.C.MatCreateShell(sys_size, sys_size, GridapDistributedPETScWrappers.C.PETSC_DETERMINE, GridapDistributedPETScWrappers.C.PETSC_DETERMINE, ctx_ptr)
  #   C = Mat{ST}(c_ptr)
  #
  #
  #   f_ptr = cfunction(mymult, GridapDistributedPETScWrappers.C.PetscErrorCode, (GridapDistributedPETScWrappers.C.Mat{ST}, GridapDistributedPETScWrappers.C.Vec{ST}, GridapDistributedPETScWrappers.C.Vec{ST}))
  #   GridapDistributedPETScWrappers.C.MatShellSetOperation(C.p, GridapDistributedPETScWrappers.C.MATOP_MULT, f_ptr)
  #
  #   ctx_ret = GridapDistributedPETScWrappers.C.MatShellGetContext(C.p)
  #   @test unsafe_pointer_to_objref(ctx_ret) == ctx
  #
  #   x = Vec(ST[1:sys_size;])
  #   xlocal = LocalVector(x)
  #   b = Vec(zeros(ST, sys_size))
  #   *(C, x, b)
  #   gc()  # avoid a finalizer problem
  #   blocal = LocalVector(b)
  #   for i=1:length(blocal)
  #     @test blocal[i] == ST(i*i)
  #   end
  #
  #   restore(blocal)
  # end
end
