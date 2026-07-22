#!/usr/bin/env bash
set -euxo pipefail

# The package_contents test already asserts the library, module and server
# binary exist. This checks the server binary is actually runnable -- i.e. that
# it resolves its MPI, netCDF and HDF5 shared libraries at run time, which is
# the failure mode a file-existence check cannot catch.
#
# xios_server.exe expects to be launched as part of an MPI job with a client, so
# it is not run standalone; --help is not offered either. Loading it under the
# dynamic linker is enough to prove every NEEDED library resolves.
ldd "${PREFIX}/bin/xios_server.exe"

if ldd "${PREFIX}/bin/xios_server.exe" | grep -q "not found"; then
  echo "ERROR: xios_server.exe has unresolved shared libraries" >&2
  exit 1
fi

echo "XIOS_TEST_OK"
