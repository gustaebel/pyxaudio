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
#
# distutils: libraries=asound

from ._shared import SinkError, encode, decode
from ._shared import FORMAT_U8, FORMAT_S16, FORMAT_S32, FORMAT_FLOAT

from ._sink cimport _Sink


class AlsaError(SinkError):
    pass


cdef class AlsaSink(_Sink):

    #
    # Private attributes.
    #
    cdef snd_pcm_t *handle
    cdef snd_pcm_hw_params_t *params
    cdef snd_pcm_uframes_t frame_size
    cdef snd_pcm_uframes_t buffer_size

    #
    # Public attributes.
    #
    sample_formats = {
        SND_PCM_FORMAT_U8:      FORMAT_U8,
        SND_PCM_FORMAT_S16_LE:  FORMAT_S16,
        SND_PCM_FORMAT_S32_LE:  FORMAT_S32,
        SND_PCM_FORMAT_FLOAT_LE: FORMAT_FLOAT,

        FORMAT_U8:      SND_PCM_FORMAT_U8,
        FORMAT_S16:     SND_PCM_FORMAT_S16_LE,
        FORMAT_S32:     SND_PCM_FORMAT_S32_LE,
        FORMAT_FLOAT:   SND_PCM_FORMAT_FLOAT_LE
    }

    cdef unicode device_name

    #
    # Initialization.
    #
    def __init__(self, unicode device_name=u"default", unicode name=None):
        self.name = name # XXX AlsaSink.name is unused.
        self.device_name = device_name

    def _setup(self, config):
        cdef int ret
        cdef int dir = 0

        self.channels = config.channels
        self.rate = config.rate
        self.format = config.format

        self.frame_size = snd_pcm_format_size(self.sample_formats[self.format], self.channels)
        self.buffer_size = 8192 * self.frame_size

        if self.format not in self.sample_formats:
            raise ValueError("unsupported sample format %r" % self.format)

        bytes_device_name = encode(self.device_name)

        # Open the stream.
        ret = snd_pcm_open(&self.handle, bytes_device_name, SND_PCM_STREAM_PLAYBACK, 0)
        if ret < 0:
            raise AlsaError("unable open device %s (%s)" % (self.device_name, snd_strerror(ret)))

        ret = snd_pcm_hw_params_malloc(&self.params)
        if ret < 0:
            raise AlsaError("unable to initialize (%s)" % snd_strerror(ret))

        ret = snd_pcm_hw_params_any(self.handle, self.params)
        if ret < 0:
            raise AlsaError("unable to initialize (%s)" % snd_strerror(ret))

        ret = snd_pcm_hw_params_set_access(self.handle, self.params, SND_PCM_ACCESS_RW_INTERLEAVED)
        if ret < 0:
            raise AlsaError("unable to initialize (%s)" % snd_strerror(ret))

        ret = snd_pcm_hw_params_set_format(self.handle, self.params, self.sample_formats[self.format])
        if ret < 0:
            raise AlsaError("unable to set sample format (%s)" % snd_strerror(ret))

        ret = snd_pcm_hw_params_set_rate_near(self.handle, self.params, &self.rate, &dir)
        if ret < 0:
            raise AlsaError("unable to set rate (%s)" % snd_strerror(ret))

        ret = snd_pcm_hw_params_set_channels(self.handle, self.params, self.channels)
        if ret < 0:
            raise AlsaError("unable to set channels (%s)" % snd_strerror(ret))

        ret = snd_pcm_hw_params_set_buffer_size_near(self.handle, self.params, &self.buffer_size)
        if ret < 0:
            raise AlsaError("unable to set buffersize (%s)" % snd_strerror(ret))

        ret = snd_pcm_hw_params(self.handle, self.params)
        if ret < 0:
            raise AlsaError("unable to initialize (%s)" % snd_strerror(ret))

        snd_pcm_hw_params_free(self.params)

        ret = snd_pcm_prepare(self.handle)
        if ret < 0:
            raise AlsaError("unable to prepare device (%s)" % snd_strerror(ret))

        self.configured = True

    def _teardown(self):
        self.drain()
        snd_pcm_close(self.handle)

    #
    # Public methods.
    #
    def get_devices(self):
        cdef int error
        cdef void **hints
        cdef void **n
        cdef char *name

        names = []

        error = snd_device_name_hint(-1, "pcm", &hints)
        if error < 0:
            return names

        n = hints
        while n[0] != NULL:
            name = snd_device_name_get_hint(n[0], "NAME")
            if name != b"null":
                names.append(decode(name))
            n += 1

        snd_device_name_free_hint(hints)
        return names

    def write(self, bytes data):
        cdef int ret
        cdef char *buf = data
        cdef int size = len(data) / self.frame_size

        if self.closed:
            raise ValueError("I/O operation on closed file")

        with nogil:
            ret = snd_pcm_writei(self.handle, buf, size)

        if ret != size:
            raise AlsaError("write error (%s)" % snd_strerror(ret))

    def drain(self):
        snd_pcm_drain(self.handle)

    def flush(self):
        snd_pcm_drop(self.handle)

    def close(self):
        if not self.closed:
            self.teardown()
        self.closed = True

