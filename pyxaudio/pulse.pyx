# -----------------------------------------------------------------------
#
# pyxaudio - Basic Cython bindings for FFmpeg and Pulseaudio
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
#
# distutils: libraries=pulse-simple

import os

from ._shared import SinkError, encode
from ._shared import FORMAT_U8, FORMAT_S16, FORMAT_S32, FORMAT_FLOAT

from ._sink cimport _Sink


class PulseError(SinkError):
    pass


cdef class PulseSink(_Sink):

    #
    # Private attributes.
    #
    cdef pa_simple *stream

    #
    # Public attributes.
    #
    sample_formats = {
        PA_SAMPLE_U8:       FORMAT_U8,
        PA_SAMPLE_S16LE:    FORMAT_S16,
        PA_SAMPLE_S32LE:    FORMAT_S32,
        PA_SAMPLE_FLOAT32LE: FORMAT_FLOAT,

        FORMAT_U8:      PA_SAMPLE_U8,
        FORMAT_S16:     PA_SAMPLE_S16LE,
        FORMAT_S32:     PA_SAMPLE_S32LE,
        FORMAT_FLOAT:   PA_SAMPLE_FLOAT32LE
    }

    #
    # Initialization.
    #
    def __init__(self, unicode name=u"pyxaudio"):
        self.name = name

    def _setup(self, config):
        cdef int error
        cdef pa_sample_spec ss

        self.channels = config.channels
        self.rate = config.rate
        self.format = config.format

        if self.format not in self.sample_formats:
            raise ValueError("unsupported sample format %r" % self.format)

        bytes_name = encode(self.name)

        if hasattr(config, "title"):
            bytes_stream_name = encode(config.title)
        elif hasattr(config, "url"):
            bytes_stream_name = encode(os.path.basename(config.url))
        else:
            bytes_stream_name = b"playback"

        ss.format = self.sample_formats[self.format]
        ss.channels = self.channels
        ss.rate = self.rate

        # Open the stream.
        self.stream = pa_simple_new(NULL, bytes_name, PA_STREAM_PLAYBACK,
                NULL, bytes_stream_name, &ss, NULL, NULL, &error)
        if self.stream == NULL:
            raise PulseError(pa_strerror(error))

        self.configured = True

    def _teardown(self):
        self.drain()
        pa_simple_free(self.stream)

    #
    # Public methods.
    #
    def get_devices(self):
        raise NotImplementedError

    def write(self, bytes data):
        cdef int ret, error
        cdef char *buf = data
        cdef int size = len(data)

        if self.closed:
            raise ValueError("I/O operation on closed file")

        with nogil:
            ret = pa_simple_write(self.stream, buf, size, &error)

        if ret < 0:
            raise PulseError(pa_strerror(error))

    def drain(self):
        cdef int error

        if self.closed:
            raise ValueError("I/O operation on closed file")

        if pa_simple_drain(self.stream, &error) < 0:
            raise PulseError(pa_strerror(error))

    def flush(self):
        cdef int error

        if self.closed:
            raise ValueError("I/O operation on closed file")

        if pa_simple_flush(self.stream, &error) < 0:
            raise PulseError(pa_strerror(error))

    def close(self):
        if not self.closed:
            self.teardown()
        self.closed = True

