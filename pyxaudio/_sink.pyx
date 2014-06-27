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


cdef class _Sink:

    def __cinit__(self):
        self.closed = False
        self.configured = False

    def __init__(self, unicode name=u"pyxaudio", unicode device=u"default"):
        self.name = name        # name is unused in AlsaSink
        self.device = device    # device is unused in PulseSink

    def setup(self, config):
        if config.channels == self.channels and config.rate == self.rate and config.format == self.format:
            return

        self.teardown()
        self._setup(config)

    def teardown(self):
        if self.configured:
            self._teardown()
            self.configured = False

    def __repr__(self):
        if self.configured:
            return "<%s channels=%r rate=%r format=%r>" % (self.__class__.__name__,
                    self.channels, self.rate, self.format)
        else:
            return "<%s unconfigured>" % self.__class__.__name__


