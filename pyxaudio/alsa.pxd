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

from cpython cimport bool


cdef extern from "alsa/asoundlib.h":
    ctypedef unsigned long snd_pcm_uframes_t
    ctypedef long snd_pcm_sframes_t

    ctypedef struct snd_pcm_t:
        pass

    ctypedef struct snd_pcm_hw_params_t:
        pass

    enum snd_pcm_stream_t:
        SND_PCM_STREAM_PLAYBACK

    enum snd_pcm_access_t:
        SND_PCM_ACCESS_RW_INTERLEAVED

    ctypedef enum snd_pcm_format_t:
        SND_PCM_FORMAT_U8
        SND_PCM_FORMAT_S16_LE
        SND_PCM_FORMAT_S32_LE
        SND_PCM_FORMAT_FLOAT_LE

    int snd_pcm_open(snd_pcm_t**, const char*, snd_pcm_stream_t, int)
    int snd_pcm_close(snd_pcm_t*)

    const char *snd_strerror(int)

    int snd_pcm_hw_params_malloc(snd_pcm_hw_params_t**)
    void snd_pcm_hw_params_free(snd_pcm_hw_params_t*)

    int snd_pcm_hw_params_any(snd_pcm_t*, snd_pcm_hw_params_t*)
    int snd_pcm_hw_params_set_access(snd_pcm_t*, snd_pcm_hw_params_t*, snd_pcm_access_t)
    int snd_pcm_hw_params_set_format(snd_pcm_t*, snd_pcm_hw_params_t*, snd_pcm_format_t)
    int snd_pcm_hw_params_set_rate_near(snd_pcm_t*, snd_pcm_hw_params_t*, unsigned int*, int*)
    int snd_pcm_hw_params_set_channels(snd_pcm_t*, snd_pcm_hw_params_t*, unsigned int)
    int snd_pcm_hw_params_set_buffer_size_near(snd_pcm_t*, snd_pcm_hw_params_t*, snd_pcm_uframes_t*)

    int snd_pcm_hw_params(snd_pcm_t*, snd_pcm_hw_params_t*)
    int snd_pcm_prepare(snd_pcm_t*)

    snd_pcm_sframes_t snd_pcm_writei(snd_pcm_t*, const void*, snd_pcm_uframes_t) nogil

    int snd_pcm_drop(snd_pcm_t*)
    int snd_pcm_drain(snd_pcm_t*)

    ssize_t snd_pcm_format_size(snd_pcm_format_t format, size_t samples)

cdef extern from "alsa/control.h":
    int snd_device_name_hint(int, const char*, void***)
    int snd_device_name_free_hint(void**)
    char *snd_device_name_get_hint(const void*, const char*)

