function make_mat(dims=(3,4))
    mat = PETSc.Mat(ST, dims...)
    vt1 = RC(complex(3., 3.))
    vt2 = RC(complex(5., 5.))
    mat[1,1] = vt1
    mat[1,2] = vt2
    PETSc.assemble(mat)
    return mat
end

@testset "Mat{$ST}" begin

  @testset "Preallocator" begin
    for mt in [PETSc.C.MATMPIAIJ,PETSc.C.MATMPIBAIJ,PETSc.C.MATMPISBAIJ]
      @test_throws ArgumentError PETSc.Mat(ST, 3, 4, mtype=mt, nnz=collect(1:10))
      @test_throws ArgumentError PETSc.Mat(ST, 3, 4, mtype=mt, onnz=collect(1:10))
    end
    for mt in [PETSc.C.MATBLOCKMAT,PETSc.C.MATSEQAIJ,PETSc.C.MATSEQBAIJ,PETSc.C.MATSEQSBAIJ]
      @test_throws ArgumentError PETSc.Mat(ST, 3, 4, mtype=mt, nnz=collect(1:10))
    end
  end

#   @testset "Shell Matrix" begin
# #    if ST == Float64  # until Clang works correctly
#       ctx = (2, 4)
#       mat = MatShell(ST, 3, 3, ctx)
#       ctx_ret = getcontext(mat)
# #      println("typeof(ctx) = ", typeof(ctx))
# #      println("typeof(ctx_ret) = ", typeof(ctx_ret))
#       @test ctx_ret == ctx
#
#       f_ptr = cfunction(mymult, PETSc.C.PetscErrorCode, (PETSc.C.Mat{ST}, PETSc.C.Vec{ST}, PETSc.C.Vec{ST}))
#       setop!(mat, PETSc.C.MATOP_MULT, f_ptr)
#       x = Vec(ST[1.0, 2, 3])
#       b = mat*x
#       @test_broken b == ST[1.0, 4.0, 9.0]
# #    end
#
#   end  # end testset Shell Matrix

  vt1 = RC(complex(3., 3.))
  vt2 = RC(complex(5., 5.))
  @testset "Utility functions" begin
    mat = make_mat()

    @test size(mat) == (3,4)
    @test sizelocal(mat) == (3,4)
    @test lengthlocal(mat) == 12
    val_ret = mat[1,1]
    vt1 = RC(complex(3., 3.))
    @test val_ret ≈ vt1
    vt1 = RC(complex(4., 4.))
    mat[1,2] = vt1
    PETSc.assemble(mat)

    mtype = PETSc.gettype(mat)
    @test mtype == PETSc.C.MATMPIAIJ

    mat_copy = Mat(mat.p)
    @test mat_copy == mat

    # test set/get index
    vt1 = RC(complex(3., 3.))
    vt2 = RC(complex(5., 5.))
    mat[1,1] = vt1
    mat[1,2] = vt2
    PETSc.assemble(mat)
    val_ret = mat[1,1]
    @test val_ret ≈ vt1
    vt1 = RC(complex(4., 4.))
    mat[1,2] = vt1
    PETSc.assemble(mat)

    #test nnz
    @test nnz(mat) == 2

    rows, cols = localranges(mat)
    @test rows == 1:size(mat, 1)
    @test cols == 1:size(mat, 2)

    @test PETSc.isfinalized(mat) == false
    PETSc.PetscDestroy(mat)
    @test PETSc.isfinalized(mat) == true
  end
  @testset "real and imag" begin
    mat  = make_mat()
    rmat = PETSc.Mat(ST, 3, 4)
    rmat[1,1] = RC(complex(3., 0.))
    rmat[1,2] = RC(complex(5., 0.))
    PETSc.assemble(rmat)
    @test real(mat)[1,1] == rmat[1,1]
    @test real(mat)[1,2] == rmat[1,2]
    if ST <: Complex
        @test imag(mat)[1,1] == rmat[1,1]
        @test imag(mat)[1,2] == rmat[1,2]
    end
  end
  @testset "diag and trace" begin
    dmat = similar(make_mat(),3,3)
    dmat[1,1] = vt1
    assemble(dmat)
    d = diag(dmat)
    @test d[1] == vt1
    @test tr(dmat) == vt1
  end
  @testset "similar and resize" begin
    mat = similar(make_mat())
    @test size(mat) == (3,4)
    @test mat[1,1] != vt1
    @test size(similar(mat, ST)) == (3,4)
    @test size(similar(mat, 4, 4)) == (4,4)
    @test size(similar(mat, (4, 4))) == (4,4)
    @test mat[1,1] != make_mat()[1,1]
    @test_throws ArgumentError resize!(mat)
    @test_throws ArgumentError resize!(mat,5,mlocal=2)
  end
  @testset "copy and conj" begin
    mat = similar(make_mat((4,4)))
    @test size(mat) == (4,4)
    mat2 = copy(mat)
    @test mat2[1,1] ≈ mat[1, 1]
    @test conj(conj(mat))[1,1] ≈ mat[1,1]
  end
  @testset "getting Mat info, inserting and assembling" begin
    mat = make_mat()
    @test PETSc.getinfo(mat).block_size == 1
    @test isassembled(mat)

    mat2 = similar(mat, ST, 4, 4)
    mat2[1,2] = vt1
    mat2[1,3] = vt2
    PETSc.assemble(mat2)

    @test mat2[1,2] == vt1
    @test mat2[1,3] == vt2
    mat3 = Mat( ST, 3, 3)

    function increasing_diag()
      (m,n) = size(mat3)
      dim = min(m, n)
      for i=1:dim
        i_float = Float64(i)
        mat3[i,i] = RC(complex(i_float, i_float))
      end
    end

    assemble(increasing_diag, mat3)

    (m,n) = size(mat3)
    dim = min(m, n)

    for i=1:dim
      i_float = Float64(i)
      @test mat3[i,i] ≈ RC(complex(i_float, i_float))
    end
  end
  @testset "transpose and transpose!" begin
    mat = make_mat((3,3))
    ctmat = copy(mat)
    #@test_broken transpose!(transpose!(copy(ctmat))) == mat
    @test transpose(transpose(ctmat)) == mat
  end
  vt = RC(complex(3., 3.))
  @testset "array indexing" begin
    vals = RC(complex.(rand(3, 2), rand(3,2)))
    idx = Array(1:3)
    idy = Array(1:2)
    @testset "view indexing" begin
      mat = PETSc.Mat(ST, 3, 3)
      mat[idx, idy] = vals
      assemble(mat)
      matj = zeros(ST, 3,3)
      matj[1:3, 1:2] = vals
      @test mat == matj
      @test mat[idx,idy] ≈ vals
    end
    @testset "y indexing" begin
      mat = PETSc.Mat(ST, 3, 3)
      vals = RC( complex.(rand(3), rand(3)))
      mat[1, idx] = vals
      assemble(mat)
      matj = zeros(ST, 3,3)
      matj[1, idx] = vals
      @test mat == matj

      #vals_ret = mat[1, idx]
      #@test vals_ret.' ≈ vals[idx]
    end
    @testset "x indexing" begin
      mat = PETSc.Mat(ST, 3, 3)
      vals = RC( [Complex(rand(), rand()) for i=1:3] )
      mat[idx, 1] = vals
      assemble(mat)
      matj = zeros(ST, 3,3)
      matj[idx, 1] = vals
      @test mat == matj
      vals_ret = mat[idx, 1]
      @test vals_ret ≈ vals
    end
    @testset "x,y set and fetch" begin
      mat = PETSc.Mat(ST, 3, 3)
      mat[idx, idy] = vt
      assemble(mat)
      matj = zeros(ST, 3,3)
      matj[1:3, 1:2] .= vt
      @test mat == matj

      mat = PETSc.Mat(ST, 3,3)
      vals = rand(ST, 3,3)
      mat[1:3, 1:3] = vals
      assemble(mat)
      @test mat == vals
    end
    @testset "x set and fetch" begin
      mat = PETSc.Mat(ST, 3, 3)
      mat[idx, 1] .= vt
      assemble(mat)
      matj = zeros(ST, 3,3)
      matj[1:3, 1] .= vt
      @test mat == matj
    end
    @testset "y set and fetch" begin
      mat = PETSc.Mat(ST, 3, 3)
      mat[1, idy] .= vt
      assemble(mat)
      matj = zeros(ST, 3,3)
      matj[1, 1:2] .= vt
      @test mat == matj
    end
  end

  @testset "SubMatrix" begin
    mat = PETSc.Mat(ST, 6, 6, nz=6)
    for i=1:6
      for j=1:6
        mat[i,j] = i*6 + j
      end
    end
    assemble(mat, PETSc.C.MAT_FLUSH_ASSEMBLY)
#    petscview(mat)
    isx = IS(ST, [1, 2, 3])
    isy = IS(ST, [1, 2])
    smat = PETSc.SubMat(mat, isx, isx)
    val = RC(complex(2.0, 2.0))

    smat[1,1] =val
    SubMatRestore(smat)
    assemble(mat)
    @test mat[1,1] == val
  end
  @testset "test ranges and colon" begin
    idy = Array(1:2)
    @testset "submatrix" begin
      mat = PETSc.Mat(ST, 3, 3)
      mat[1:3, 1:2] .= vt
      assemble(mat)
      matj = zeros(ST, 3,3)
      matj[1:3, 1:2] .= vt
      @test mat == matj
    end
    @testset "on an axis with range" begin
      mat = PETSc.Mat(ST, 3, 3)
      mat[:, idy] .= vt
      assemble(mat)
      matj = zeros(ST, 3,3)
      matj[:, 1:2] .= vt
      @test mat == matj
    end
    @testset "on a column" begin
      vals = [1, 2, 3]
      mat = PETSc.Mat(ST, 3, 3)
      mat[:, 1] .= vt
      assemble(mat)
      matj = zeros(ST, 3,3)
      matj[:, 1] .= vt
      @test mat == matj
    end
  end

  @testset "full and fill" begin
    vt = RC(complex(1.,1.))
    mat = PETSc.Mat(ST, 3, 3)
    fill!(mat, vt)
    assemble(mat)
    @test mat == fill(vt,(3,3))
    matjd = Array(mat)
    @test mat == matjd
  end

  function check_mats(a, b)
    for i=1:size(a, 2)
      for j=1:size(a, 1)
        @test a[i, j] ≈ b[i,j]
      end
    end
  end
  @testset "0-based indexing " begin
    mat = PETSc.Mat(ST, 3, 3)
    matj = zeros(ST, 3, 3)
    idx = PetscInt[1, 2]
    idy = PetscInt[0, 1]
    vals = ST[1.0 2.0; 3.0 4.0]
    set_values!(mat, idx, idy, vals)
    set_values!(matj, idx, idy, vals)
    assemble(mat)
    check_mats(mat, matj)

    maprow, mapcol = local_to_global_mapping(mat)
    set_local_to_global_mapping(mat, maprow, mapcol)
    vals = 2*vals
    set_values_local!(mat, idx, idy, vals)
    set_values_local!(matj, idx, idy, vals)
    assemble(mat)
    check_mats(mat, matj)

    bs=2
    mat = PETSc.Mat(ST, 6, 6, bs=bs)
    matj = zeros(ST, 12, 12)
    idx = [0, 1]
    idy = [0, 1, 2]
    vals = rand(ST, bs*length(idx), bs*length(idy))
    set_values_blocked!(mat, idx, idy, vals)
    assemble(mat)
    for j=1:length(idy)
      start_idy = idy[j]*bs
      for i=1:length(idx)
        start_idx = idx[i]*bs
        for k=1:bs
          for p=1:bs
            colidx = start_idy + k
            rowidx = start_idx + p
            @test mat[rowidx, colidx] ≈ vals[(i-1)*bs + p, (j-1)*bs + k]
          end
        end
      end
    end

    vals = 2*vals
    maprow, mapcol = local_to_global_mapping(mat)
    set_local_to_global_mapping(mat, maprow, mapcol)
    set_values_blocked_local!(mat,  idx, idy, vals)
    assemble(mat)
    for j=1:length(idy)
      start_idy = idy[j]*bs
      for i=1:length(idx)
        start_idx = idx[i]*bs
        for k=1:bs
          for p=1:bs
            colidx = start_idy + k
            rowidx = start_idx + p
            @test mat[rowidx, colidx] ≈ vals[(i-1)*bs + p, (j-1)*bs + k]
          end
        end
      end
    end

  end

  @testset "Sparse Matrix conversion" begin
    A = sprand(10, 10, 0.1)
    B = Mat(A)
    assemble(B)
    @test A == B
    info = PETSc.getinfo(B)
    @test info.mallocs == 0

    A2 = Array(A)
    B2 = Mat(B)
    assemble(B2)
    @test A2 == B2
    info = PETSc.getinfo(B2)
    @test info.mallocs == 0

    dtol = 1e-16
    A3 = ST[1. 2 3; 4 5 6; 7 8 dtol/10]
    B3 = Mat(A3, droptol=dtol)
    assemble(B3)
    A3b = copy(A3)
    A3b[3, 3] = 0
    @test A3b == B3
    info = PETSc.getinfo(B3)
    @test info.nz_used == 8
  end

  @testset "test conversion of values to a new type" begin
    mata = PETSc.Mat(ST, 3, 3)
    matb = PETSc.Mat(ST, 3, 3)
    mataj = zeros(ST, 3, 3)
    matbj = zeros(ST, 3, 3)
    vec = PETSc.Vec(ST, 3)
    vecj = zeros(ST, 3)
    cnt = 1
    for i=1:3
      for j=1:3
        cnt_f = RC(complex(Float64(cnt), Float64(cnt)))
        cnt_f2 = RC(complex(Float64(cnt + 9), Float64(cnt + 9)))

        mata[i,j] = cnt_f
        mataj[i,j] = cnt_f
        matb[i,j] = cnt_f2
        matbj[i,j] = cnt_f2
        cnt += 1
      end
      vec[i] = RC(complex(Float64(i), i))
      vecj[i] = RC(complex(Float64(i), i))
      assemble(vec)
    end

    assemble(mata)
    assemble(matb)

    @testset "matrix-vector product" begin
      result = mata*vec
      resultj = mataj*vecj
      @test result == resultj

      #result = mata.'*vec
      #resultj = mataj.'*vecj
      #@test result == resultj

      result = mata'*vec
      resultj = mataj'*vecj
      @test result == resultj
    end
    @testset "binary matrix operations" begin
      result = mata + matb
      assemble(result)
      resultj = mataj + matbj
      @test result == resultj
      result = mata - matb
      assemble(result)
      resultj = mataj - matbj
      @test result == resultj
      result = mata * matb
      assemble(result)
      resultj = mataj * matbj
      @test result == resultj
    end
    @testset "matrix operations with numbers" begin
      result = 2*mata
      assemble(result)
      resultj = 2*mataj

      @test result == resultj
      result = mata/2
      assemble(result)
      resultj = mataj/2
      @test result == resultj

      result = 2 .\ mata
      assemble(result)
      resultj = 2 .\ mataj
      @test result == resultj

      result  = -mata
      resultj = -mataj
      @test result == resultj
    end
  end

  @testset "Testing {c}transpose mults" begin
    mat1  = PETSc.Mat(ST,3,3,mtype=PETSc.C.MATSEQAIJ)
    mat2  = PETSc.Mat(ST,3,3,mtype=PETSc.C.MATSEQAIJ)
    mat1j = zeros(ST,3,3)
    mat2j = zeros(ST,3,3)
    vt1 = RC(complex(3., 0.))
    vt2 = RC(complex(5., 5.))
    vt3 = RC(complex(4., 4.))
    vt4 = RC(complex(10., 0.))
    vt5 = RC(complex(1., 0.))
    mat1[1,1] = vt1
    mat1[1,2] = vt2
    mat1[2,1] = conj(vt2)
    mat1[1,3] = vt3
    mat1[3,1] = conj(vt3)
    mat1[2,2] = vt4
    mat1[3,3] = vt5
    mat1j[1,1] = vt1
    mat1j[1,2] = vt2
    mat1j[2,1] = conj(vt2)
    mat1j[1,3] = vt3
    mat1j[3,1] = conj(vt3)
    mat1j[2,2] = vt4
    mat1j[3,3] = vt5
    mat2[1,1] = vt1
    mat2[1,2] = vt2
    mat2[2,1] = vt2
    mat2[1,3] = vt3
    mat2[3,1] = vt3
    mat2[2,2] = vt4
    mat2[3,3] = vt5
    mat2j[1,1] = vt1
    mat2j[1,2] = vt2
    mat2j[2,1] = vt2
    mat2j[1,3] = vt3
    mat2j[3,1] = vt3
    mat2j[2,2] = vt4
    mat2j[3,3] = vt5
    PETSc.assemble(mat1)
    PETSc.assemble(mat2)
    @test ishermitian(mat1)
    @test issymmetric(mat2)

    #mat3 = mat1.'*mat2
    #mat3j = mat1j.'*mat2j
    #assemble(mat3)
    #@test mat3 == mat3j

    #mat4 = mat1*mat2.'
    #mat4j = mat1j*mat2j.'
    #assemble(mat4)
    #@test mat4 == mat4j
  end

  @testset "MatRow" begin
    matj = [1. 0 0; 0 2 3; 4 5 6];
    mat = Mat(matj)
    assemble(mat)
    val = 1
    for i=1:3
      row_i = PETSc.MatRow(mat, i)
      @test length(row_i) == i
      for j=1:length(row_i)
        @test PETSc.getval(row_i, j) ≈ val
        val += 1
      end
      restore(row_i)
    end

    row = PETSc.MatRow(mat, 1)
    @test PETSc.getcol(row, 1) == 1
    restore(row)
    @test PETSc.count_row_nz(mat, 1) == 1

    row = PETSc.MatRow(mat, 2)
    @test PETSc.getcol(row, 1) == 2
    @test PETSc.getcol(row, 2) == 3
    restore(row)
    @test PETSc.count_row_nz(mat, 2) == 2

    row = PETSc.MatRow(mat, 3)
    @test PETSc.getcol(row, 1) == 1
    @test PETSc.getcol(row, 2) == 2
    @test PETSc.getcol(row, 3) == 3
    restore(row)
    @test PETSc.count_row_nz(mat, 3) == 3
  end

  @testset "kron" begin
    function testrun(Aj, Bj)
      # A and B are julia matrices of some kind
      A = Mat(Aj); B = Mat(Bj)
      assemble(A); assemble(B)
      Cj = kron(Aj, Bj)
      C = kron(A, B)
      assemble(C)
      m, n = size(C)
      C2 = C[1:m, 1:n]
      @test C2 ≈ Cj
    end

    # case 1
    Aj = ST[1. 0 0; 0 1 0; 0 0 1]
    testrun(Aj, Aj)

    # case 2
    Aj = ST[1. 2 0; 3 4 5; 0 6 7]
    testrun(Aj, Aj)


    n = 10
    Aj = rand(ST, n, n)
    testrun(Aj, Aj)


    m = 3
    n = 2
    Aj = rand(ST, m, n)
    testrun(Aj, Aj)


    m1 = 3
    n1 = 2
    m2 = 4
    n2 = 5
    Aj = rand(ST, m1, n1)
    Bj = rand(ST, m2, n2)
    testrun(Aj, Bj)

    m1 = 5
    m2 = 7
    n1 = 8
    n2 = 10
    Aj = sprand(m1, n1, 0.01)
    Bj = sprand(m2, n2, 0.01)
    testrun(Aj, Bj)

    function testkron(Aj, Bj)
      m1, n1 = size(Aj)
      m2, n2 = size(Bj)
      Cj = kron(Aj, Bj)
      C = PETSc.PetscKron(Aj, Bj)
      assemble(C)
      C_full = C[1:(m1*m2), 1:(n1*n2)]
      Cj_full = Array(Cj)
    #  @test Cj_full ≈ C_full
    end

#    println("\n----- Case 1 -----")
    Aj = sparse(Matrix{Float64}(I, 3, 3))
    testkron(Aj, Aj)

#    println("\n----- Case 2 -----")
    Aj = sparse([1. 2 0; 3 4 5; 0 6 7])
    testkron(Aj, Aj)

#    println("\n----- Case 3 -----")
    Aj = sparse([1. 2 3; 4 5 6; 7 8 9])
    Bj = sparse([10. 11 12 13; 14 15 16 17; 18 19 20 21])
    testkron(Aj, Bj)

#    println("\n----- Case 4 -----")
    Aj = sparse([1. 2 ; 4 5 ; 7 8 ])
    Bj = sparse([10. 11 12 13 22; 14 15 16 17 23; 18 19 20 21 24])
    testkron(Aj, Bj)

#    println("\n----- Case 5 -----")
    Aj = sprand(10, 15, 0.01)
    Bj = sprand(7, 21, 0.01)
    testkron(Aj, Bj)

  end
end
