# -----------------------------------------------------------------------
#
# pyxaudio - Basic Cython bindings for FFmpeg, Pulseaudio and Alsa
#
# Copyright (C) 2014 Lars Gustäbel <lars@gustaebel.de>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
# -----------------------------------------------------------------------

import os
import wave

from ._shared import SinkError
from ._shared import FORMAT_U8, FORMAT_S16, FORMAT_S32, FORMAT_FLOAT

from ._sink cimport _Sink



class FileError(SinkError):
    pass


cdef class FileSink(_Sink):

    #
    # Private attributes.
    #
    cdef object wave

    #
    # Public attributes.
    #
    sample_formats = {
        FORMAT_U8,
        FORMAT_S16,
        FORMAT_S32,
        FORMAT_FLOAT
    }

    #
    # Initialization.
    #
    def _setup(self, config):
        if self.name is None:
            raise FileError("missing name argument")

        self.channels = config.channels
        self.rate = config.rate
        self.format = config.format

        self.wave = wave.open(self.name, "wb")
        self.wave.setnchannels(self.channels)
        self.wave.setframerate(self.rate)

        if self.format == FORMAT_U8:
            self.wave.setsampwidth(1)
        elif self.format == FORMAT_S16:
            self.wave.setsampwidth(2)
        elif self.format == FORMAT_S32:
            self.wave.setsampwidth(4)
        else:
            raise ValueError("unsupported sample format %r" % self.format)

        self.configured = True

    def _teardown(self):
        self.wave.close()

    #
    # Public methods.
    #
    def get_devices(self):
        raise NotImplementedError

    def write(self, bytes data):
        if self.closed:
            raise ValueError("I/O operation on closed file")
        self.wave.writeframes(data)

    def flush(self):
        if self.closed:
            raise ValueError("I/O operation on closed file")

    def close(self):
        if not self.closed:
            self.teardown()
        self.closed = True

