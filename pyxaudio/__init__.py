# encoding: utf-8
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

from pyxaudio.ffmpeg import FFmpegSource
from pyxaudio.pulse import PulseSink
from pyxaudio.alsa import AlsaSink

class SourceError(Exception):
    pass

class SinkError(Exception):
    pass


FORMAT_U8 = u"u8"
FORMAT_S16 = u"s16"
FORMAT_S32 = u"s32"
FORMAT_FLOAT = u"float"


sources = {
    "ffmpeg":   FFmpegSource,
    "default":  FFmpegSource
}

sinks = {
    "pulse":    PulseSink,
    "alsa":     AlsaSink,
    "default":  PulseSink
}

def Source(*args, **kwargs):
    return sources["default"](*args, **kwargs)

def Sink(*args, **kwargs):
    return sinks["default"](*args, **kwargs)

class AudioConfig(object):
    def __init__(self, channels=2, rate=44100, format=FORMAT_S16, title=None):
        self.channels = channels
        self.rate = rate
        self.format = format
        self.title = title

