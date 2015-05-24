# encoding: utf-8

from distutils.core import setup
from Cython.Build import cythonize

setup(
    name="pyxaudio",
    version="0.1",
    description="Basic Cython bindings for FFmpeg, Pulseaudio and Alsa",
    author="Lars Gustäbel",
    author_email="lars@gustaebel.de",
    packages=["pyxaudio"],
    ext_modules=cythonize("pyxaudio/*.pyx"),
    scripts=["beep"]
)
