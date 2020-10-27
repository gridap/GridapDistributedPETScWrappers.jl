const build_names = ["RealDouble","RealSingle","ComplexDouble","ComplexSingle"]
arches = Dict()             # dict of dirname => (PETSC_DIR, PETSC_ARCH)
have_petsc = fill(false,4)  # whether or not each version of Petsc is usable
libpetsc_name=Dict()
binary = Dict()
for (i, name) in enumerate(build_names)

  julia_petsc_binary=string("JULIA_PETSC_", name, "_BINARY")
  julia_petsc_dir=string("JULIA_PETSC_", name, "_DIR")
  julia_petsc_arch=string("JULIA_PETSC_", name, "_ARCH")
  julia_petsc_libname=string("JULIA_PETSC_", name, "_LIBNAME")

  env_vars = [julia_petsc_binary,julia_petsc_dir,julia_petsc_arch,julia_petsc_libname]

  if (name != "RealDouble")
    for env_var in env_vars
      if (haskey(ENV, env_var))
        @warn "Ignoring $(env_var). PetscScalar $(name) not yet supported."
      end
    end
    have_petsc[i]=false
  else
    if (haskey(ENV, julia_petsc_binary))
       binary[name]=lowercase(ENV[julia_petsc_binary])
       if !(binary[name]=="system" || binary[name]=="")
         @error """Invalid value for $julia_petsc_binary env variable ($(binary[name]). If you want
         to use a PETSc library installed into your system (e.g., HPC cluster), set this env variable to \"system\"
         """
       end
    else
       binary[name]=nothing
       have_petsc[i]=true
       @info "Using PETSc binary provided by PETSc_jll package for PetscScalar $(name)"
    end

    if haskey(ENV, julia_petsc_dir)  ||
       haskey(ENV, julia_petsc_arch) ||
       haskey(ENV, julia_petsc_arch)

      if (binary[name]=="" || binary[name]==nothing)
        @warn """
              You have $(julia_petsc_dir) and/or $(julia_petsc_arch) and/or $(julia_petsc_libname) set, but $(julia_petsc_binary) is unset or set to the empty string. Thus, the values of these env variables will be ignored.
              """
      elseif (binary[name]=="system")
        if !(haskey(ENV, julia_petsc_dir) && haskey(ENV, string("JULIA_PETSC_", name, "_DIR")))
          error("Must have either both or neither DIR and ARCH for JULIA_PETSC_$name")
        else
          have_petsc[i] = true
          arches[name] = (ENV[julia_petsc_dir], ENV[julia_petsc_arch])
          if (haskey(ENV, julia_petsc_libname))
            libpetsc_name[name]=ENV[julia_petsc_libname]
          else
            libpetsc_name[name]="libpetsc"
          end
        end
      end
    end
  end
end

# create deps.jl file with library locations
open("deps.jl", "w") do f
  for (i, name) in enumerate(build_names)
    if haskey(arches, name)
      PETSC_DIR, PETSC_ARCH = arches[name]
      libname=libpetsc_name[name]
      path = abspath(PETSC_DIR, PETSC_ARCH, "lib", libname)
      println(f, "const deps_file_petsc$name = \"", escape_string(path), "\"")
      @info "Using a system installation of PETSc for PetscScalar $(name)"
      @info "PETSc library will be search for on $(path)"
    else
      println(f, "const deps_file_petsc$name = \"\" ")
    end
  end
  println(f, "const have_petsc = [", have_petsc[1], " ",
                                     have_petsc[2], " ",
                                     have_petsc[3], " ",
                                     have_petsc[4],"]")
end
