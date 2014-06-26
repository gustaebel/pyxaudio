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

from libc.stdint cimport uint8_t, uint32_t, uint64_t

from cpython cimport bool

cdef extern from "pulse/def.h":
    enum pa_stream_direction_t:
        PA_STREAM_PLAYBACK

    ctypedef uint64_t pa_usec_t

    struct pa_buffer_attr:
        uint32_t maxlength
        uint32_t tlength
        uint32_t prebuf
        uint32_t minreq
        uint32_t fragsize

cdef extern from "pulse/sample.h":
    ctypedef enum pa_sample_format_t:
        PA_SAMPLE_U8
        PA_SAMPLE_S16LE
        PA_SAMPLE_S32LE
        PA_SAMPLE_FLOAT32LE

    struct pa_sample_spec:
        pa_sample_format_t format
        uint32_t rate
        uint8_t channels

cdef extern from "pulse/channelmap.h":
    struct pa_channel_map:
        pass

cdef extern from "pulse/simple.h":
    struct pa_simple:
        pa_buffer_attr *attr

    pa_simple *pa_simple_new(const char*, const char*, pa_stream_direction_t, const char*, const char*, const pa_sample_spec*, const pa_channel_map*, const pa_buffer_attr*, int*)
    int pa_simple_write(pa_simple*, const void*, size_t, int*) nogil
    int pa_simple_drain(pa_simple*, int*)
    int pa_simple_flush(pa_simple*, int*)
    void pa_simple_free(pa_simple*)

    pa_usec_t pa_simple_get_latency(pa_simple*, int*)

cdef extern from "pulse/error.h":
    const char *pa_strerror(int)

