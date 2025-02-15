# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder, Pkg

name = "ADIOS2"
version = v"2.8.0"

# Newest version (2022-03-08):
# commit: e2e94f2943e79df6c69239b6aa4cdee62bb6c0f9
# sha256: 00dd6243dc9b445b5e33fb044f592f2b6f6d99bd04ec7963782dd323d2684a02

# Collection of sources required to complete build
sources = [
    ArchiveSource("https://github.com/ornladios/ADIOS2/archive/refs/tags/v2.8.0.tar.gz",
                  "5af3d950e616989133955c2430bd09bcf6bad3a04cf62317b401eaf6e7c2d479"),
    DirectorySource("./bundled"),
]

# Bash recipe for building across all platforms
script = raw"""
cd $WORKSPACE/srcdir
cd ADIOS2-*
# Don't define clock_gettime on macOS
atomic_patch -p1 ${WORKSPACE}/srcdir/patches/clock_gettime.patch
atomic_patch -p1 ${WORKSPACE}/srcdir/patches/shlwapi.patch
# Don't use `ERROR` as identifier; it is reserved on Windows.
# Already implemented on master.
atomic_patch -p1 ${WORKSPACE}/srcdir/patches/fatalerror.patch

mkdir build
cd build
archopts=
if [[ "$target" == *-apple-* ]]; then
    # MPICH's pkgconfig file "mpich.pc" lists these options:
    #     Libs:     -framework OpenCL -Wl,-flat_namespace -Wl,-commons,use_dylibs -L${libdir} -lmpi -lpmpi -lm    -lpthread
    #     Cflags:   -I${includedir}
    # cmake doesn't know how to handle the "-framework OpenCL" option
    # and wants to use "-framework" as a stand-alone option. This fails
    # gloriously, and cmake concludes that MPI is not available.
    archopts="-DMPI_C_ADDITIONAL_INCLUDE_DIRS='' -DMPI_C_LIBRARIES='-Wl,-flat_namespace;-Wl,-commons,use_dylibs;-lmpi;-lpmpi' -DMPI_CXX_ADDITIONAL_INCLUDE_DIRS='' -DMPI_CXX_LIBRARIES='-Wl,-flat_namespace;-Wl,-commons,use_dylibs;-lmpi;-lpmpi'"
elif [[ "$target" == x86_64-w64-mingw32 ]]; then
    # - The MSMPI Fortran bindings are missing a function; see
    #   <https://github.com/microsoft/Microsoft-MPI/issues/7>
    echo 'void __guard_check_icall_fptr(unsigned long ptr) {}' >cfg_stub.c
    gcc -c cfg_stub.c
    ar -crs libcfg_stub.a cfg_stub.o
    cp libcfg_stub.a $prefix/lib
    # - cmake's auto-detection for MPI doesn't work on Windows.
    # - The SST and Table ADIOS2 components don't build on Windows
    #   (reported in <https://github.com/ornladios/ADIOS2/issues/2705>)
    export FFLAGS="-I$prefix/src -I$prefix/include -fno-range-check"
    archopts="-DMPI_GUESS_LIBRARY_NAME=MSMPI -DMPI_C_LIBRARIES=msmpi64 -DMPI_CXX_LIBRARIES=msmpi64 -DMPI_Fortran_LIBRARIES='msmpifec64;msmpi64;cfg_stub' -DADIOS2_USE_SST=OFF -DADIOS2_USE_Table=OFF"
elif [[ "$target" == *-mingw* ]]; then
    archopts="-DMPI_GUESS_LIBRARY_NAME=MSMPI -DADIOS2_USE_SST=OFF -DADIOS2_USE_Table=OFF"
fi
# Fortran is not supported with Clang
# DataMan has linker error on Windows
cmake \
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN} \
    -DCMAKE_FIND_ROOT_PATH=$prefix \
    -DADIOS2_HAVE_ZFP_CUDA=OFF \
    -DADIOS2_USE_Blosc=ON \
    -DADIOS2_USE_DataMan=OFF \
    -DADIOS2_USE_Fortran=OFF \
    -DADIOS2_USE_MPI=ON \
    -DADIOS2_USE_PNG=ON \
    -DADIOS2_USE_ZeroMQ=ON \
    -DADIOS2_BUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF \
    -DMPI_HOME=$prefix \
    ${archopts} \
    -DADIOS2_INSTALL_GENERATE_CONFIG=OFF \
    -DCMAKE_INSTALL_PREFIX=$prefix \
    ..
cmake --build . --config RelWithDebInfo --parallel $nproc
cmake --build . --config RelWithDebInfo --parallel $nproc --target install
install_license ../Copyright.txt ../LICENSE
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = supported_platforms()
# 32-bit architectures are not supported; see
# <https://github.com/ornladios/ADIOS2/issues/2704>
platforms = filter(p -> nbits(p) ≠ 32, platforms)
platforms = expand_cxxstring_abis(platforms)
# Windows doesn't build with libcxx="cxx03"
platforms = expand_gfortran_versions(platforms)

# The products that we will ensure are always built
products = [
    # ExecutableProduct("adios_deactivate_bp", :adios_deactivate_bp),
    # ExecutableProduct("adios_iotest", :adios_iotest),
    # ExecutableProduct("adios_reorganize", :adios_reorganize),
    # ExecutableProduct("adios_reorganize_mpi", :adios_reorganize_mpi),
    # ExecutableProduct("bp4dbg", :bp4dbg),
    ExecutableProduct("bpls", :bpls),
    # ExecutableProduct("sst_conn_tool", :sst_conn_tool),

    LibraryProduct("libadios2_c", :libadios2_c),
    LibraryProduct("libadios2_c_mpi", :libadios2_c_mpi),
    LibraryProduct("libadios2_core", :libadios2_core),
    LibraryProduct("libadios2_core_mpi", :libadios2_core_mpi),
    LibraryProduct("libadios2_cxx11", :libadios2_cxx11),
    LibraryProduct("libadios2_cxx11_mpi", :libadios2_cxx11_mpi),

    # Missing on Apple:
    # LibraryProduct("libadios2_taustubs", :libadios2_taustubs),

    # Missing on Windows:
    # LibraryProduct("libadios2_atl", :libadios2_atl),
    # LibraryProduct("libadios2_dill", :libadios2_dill),
    # LibraryProduct("libadios2_evpath", :libadios2_evpath),
    # LibraryProduct("libadios2_ffs", :libadios2_ffs),
]

# Dependencies that must be installed before this package can be built
dependencies = [
    Dependency(PackageSpec(name="Blosc_jll")),
    Dependency(PackageSpec(name="Bzip2_jll"); compat="1.0.8"),
    Dependency(PackageSpec(name="CompilerSupportLibraries_jll", uuid="e66e0078-7015-5450-92f7-15fbd957f2ae")),
    # We cannot use HDF5 because we need an HDF5 configuration with MPI support
    # Dependency(PackageSpec(name="HDF5_jll")),
    Dependency(PackageSpec(name="MPICH_jll"); platforms=filter(!Sys.iswindows, platforms)),
    Dependency(PackageSpec(name="MicrosoftMPI_jll"); platforms=filter(Sys.iswindows, platforms)),
    Dependency(PackageSpec(name="ZeroMQ_jll")),
    Dependency(PackageSpec(name="libpng_jll")),
    Dependency(PackageSpec(name="zfp_jll")),
]

# Build the tarballs, and possibly a `build.jl` as well.
# GCC 4 is too old for Windows; it doesn't have <regex.h>
# GCC 5 is too old for FreeBSD; it doesn't have `std::to_string`
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               julia_compat="1.6", preferred_gcc_version=v"6")
