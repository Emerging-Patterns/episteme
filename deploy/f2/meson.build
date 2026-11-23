# The F2 reader's compiled part: the tail pass (native/f2pass.cu) built with
# the CUDA toolkit's compiler and installed, with its ctypes bridge, as the
# Python package f2pass. The reader's own modules (f2serve.py, model.py, ...)
# are run from this directory and are not installed.
#
# The compiler is the nvcc meson finds on PATH (it reads no environment
# variable for it) and must be of the toolkit whose cuBLAS is linked: put
# that toolkit's bin first, `PATH=/usr/local/cuda/bin:$PATH uv sync ...`. A
# library built by another release's nvcc loads, and its kernels are then
# refused by the device ("invalid device function").
project('episteme-f2', 'cpp', 'cuda',
  version: '0.1.0',
  default_options: ['buildtype=release', 'cuda_std=c++17'])

py = import('python').find_installation(pure: false)
cuda = dependency('cuda', version: '>=12', modules: ['cublas'])
nvcc = meson.get_compiler('cuda')
if nvcc.version().split('.')[0] != cuda.version().split('.')[0]
  error('nvcc @0@ is not of the CUDA @1@ toolkit that was found: put that toolkit\'s bin first on PATH'.format(nvcc.version(), cuda.version()))
endif
# where the toolkit keeps cuBLAS, beside its compiler: the library looks there when the process has not loaded it yet
fs = import('fs')
libdir = fs.parent(fs.parent(find_program(nvcc.cmd_array()[0]).full_path())) / 'lib64'
into = py.get_install_dir() / 'f2pass'

shared_module('f2pass', 'native/f2pass.cu',
  name_prefix: 'lib',
  dependencies: cuda,
  install: true,
  install_rpath: libdir,
  install_dir: into)

# the bridge is the package's __init__ (kept under another name here, so that
# this directory's own modules do not import the source in its place)
configure_file(input: 'native/f2pass.py', output: '__init__.py', copy: true, install: true, install_dir: into)
