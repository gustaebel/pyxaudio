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

from cpython cimport bool


cdef class _Sink:
    #
    # Public attributes.
    #
    cdef readonly bool closed
    cdef readonly bool configured

    cdef readonly unsigned int channels
    cdef readonly unsigned int rate
    cdef readonly unicode format

    cdef readonly unicode name


