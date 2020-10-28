@testset "Error Handling{$ST}" begin
  msg = GridapDistributedPETScWrappers.PetscErrorMessage(73)
  @test msg == "Object is in wrong state"
  @test_throws GridapDistributedPETScWrappers.PetscError GridapDistributedPETScWrappers.chk(76)
end
