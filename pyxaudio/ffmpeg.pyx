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
# distutils: libraries=avcodec avformat avutil swresample

import sys
import collections

from ._shared import SourceError, encode
from ._shared import FORMAT_U8, FORMAT_S16, FORMAT_S32, FORMAT_FLOAT

audio_info = collections.namedtuple("audio_info", ("type", "description", "channels", "rate", "format"))
stream_info = collections.namedtuple("stream_info", ("position", "duration"))


class FFmpegError(SourceError):
    pass


sample_formats = {
    AV_SAMPLE_FMT_U8:   FORMAT_U8,
    AV_SAMPLE_FMT_S16:  FORMAT_S16,
    AV_SAMPLE_FMT_S32:  FORMAT_S32,
    AV_SAMPLE_FMT_FLT:  FORMAT_FLOAT,

    FORMAT_U8:      AV_SAMPLE_FMT_U8,
    FORMAT_S16:     AV_SAMPLE_FMT_S16,
    FORMAT_S32:     AV_SAMPLE_FMT_S32,
    FORMAT_FLOAT:   AV_SAMPLE_FMT_FLT
}


cdef class FFmpegSource:

    #
    # Private attributes.
    #
    cdef AVFormatContext *ctx
    cdef AVCodecContext *avctx
    cdef SwrContext *swrctx
    cdef AVStream *stream
    cdef AVFrame *frame

    cdef AVSampleFormat sample_fmt
    cdef int audio_stream
    cdef bytes data
    cdef bool eof
    cdef float time_base

    #
    # Public attributes.
    #
    cdef readonly unicode url
    cdef readonly dict tags
    cdef readonly bool seekable
    cdef readonly bool closed

    cdef readonly unicode codec_name
    cdef readonly unicode codec_long_name
    cdef readonly int rate
    cdef readonly int channels
    cdef readonly unicode format

    cdef readonly float position
    cdef readonly object duration # allow None

    #
    # Initialization.
    #
    def __cinit__(self):
        # Initialize C structures and default attributes.
        self.data = b""
        self.frame = av_frame_alloc()

        self.tags = {}
        self.seekable = False
        self.closed = False
        self.eof = False

    def __dealloc__(self):
        # FIXME is that all?
        swr_free(&self.swrctx)
        av_frame_free(&self.frame)

    def __init__(self, unicode url, unicode sample_format=None):
        # FIXME do proper clean up in case of errors
        cdef int ret
        cdef AVCodec *codec

        self.url = url
        bytes_url = encode(url)

        # Open the stream.
        ret = avformat_open_input(&self.ctx, bytes_url, NULL, NULL)
        if ret < 0:
            raise FFmpegError("unable to open url")

        # Read a few packets to get stream information.
        ret = avformat_find_stream_info(self.ctx, NULL)
        if ret < 0:
            raise FFmpegError("unable to read")

        # Use the (first) audio stream in the file (usually it is 0 except for
        # video files).
        self.audio_stream = av_find_best_stream(self.ctx, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0)
        if self.audio_stream < 0:
            raise FFmpegError("no audio stream found")

        # Start up the decoder.
        self.stream = self.ctx.streams[self.audio_stream]
        self.avctx = self.stream.codec
        codec = avcodec_find_decoder(self.avctx.codec_id)
        ret = avcodec_open2(self.avctx, codec, NULL)
        if ret < 0:
            raise FFmpegError("unable to open decoder")

        # Guess the channel layout if it is unset.
        if self.avctx.channel_layout == 0:
            self.avctx.channel_layout = av_get_default_channel_layout(self.avctx.channels)
            if self.avctx.channel_layout == 0:
                raise FFmpegError("unable to guess channel layout")

        # Set up the resampler (e.g. to convert planar to packed audio).
        if sample_format is not None:
            if sample_format not in sample_formats:
                raise ValueError("unsupported sample format %r" % sample_format)
            self.sample_fmt = sample_formats[sample_format]
        elif av_sample_fmt_is_planar(self.avctx.sample_fmt):
            self.sample_fmt = av_get_packed_sample_fmt(self.avctx.sample_fmt)
        else:
            self.sample_fmt = self.avctx.sample_fmt

        if self.sample_fmt == AV_SAMPLE_FMT_DBL:
            self.sample_fmt = AV_SAMPLE_FMT_FLT

        if self.sample_fmt != self.avctx.sample_fmt:
            self.swrctx = swr_alloc_set_opts(NULL,
                    self.avctx.channel_layout, self.sample_fmt, self.avctx.sample_rate,
                    self.avctx.channel_layout, self.avctx.sample_fmt, self.avctx.sample_rate,
                    0, NULL)

            if self.swrctx == NULL:
                raise FFmpegError("unable to open resampler")

            ret = swr_init(self.swrctx)
            if ret < 0:
                raise FFmpegError("unable to initialize resampler")

        # Gather audio information.
        self.rate = self.avctx.sample_rate
        self.channels = self.avctx.channels
        self.format = sample_formats[self.sample_fmt]

        # Gather decoder information.
        self.codec_name = codec.name.decode("ascii")
        self.codec_long_name = codec.long_name.decode("ascii")

        # Gather stream information.
        self.seekable = self.ctx.pb.seekable == 1
        self.position = 0
        self.duration = float(self.ctx.duration) / AV_TIME_BASE if self.ctx.duration > 0 else None
        self.time_base = <float>self.stream.time_base.num / <float>self.stream.time_base.den

        # Collect metadata tags.
        cdef AVDictionaryEntry *tag = NULL
        while True:
            tag = av_dict_get(self.ctx.metadata, "", tag, AV_DICT_IGNORE_SUFFIX)
            if tag == NULL:
                break
            self.tags[self._decode(tag.key)] = self._decode(tag.value)

    #
    # Private methods.
    #
    cdef unicode _decode(self, bytes s):
        return s.decode("utf8", "surrogateescape")

    cdef void _read_next_frame(self):
        cdef int ret, length, got_frame
        cdef AVPacket packet

        # Initialize the packet structure.
        av_init_packet(&packet)

        # Read only packets from the audio stream.
        while 1:
            with nogil:
                ret = av_read_frame(self.ctx, &packet)
            if ret < 0:
                # XXX av_free_packet necessary here?
                self.eof = True
                return

            if packet.stream_index == self.audio_stream:
                break

        # Update the stream position.
        self.position = float(packet.pts) * self.time_base

        while packet.size > 0:
            # Decode the packet into the frame.
            with nogil:
                length = avcodec_decode_audio4(self.avctx, self.frame, &got_frame, &packet)
            if length < 0:
                # The packet could not be decoded, ignore this.
                break

            # Advance the packet data.
            packet.data += length
            packet.size -= length

            if got_frame:
                # A complete frame was produced.
                size = av_samples_get_buffer_size(NULL,
                        self.avctx.channels, self.frame.nb_samples,
                        self.sample_fmt, 1)

                if self.swrctx != NULL:
                    # Reorder planar audio data or convert to a different
                    # sample layout.
                    self.data += self._convert(self.frame, size)
                else:
                    self.data += (<char*>self.frame.data[0])[:size]

            # Free the referenced data from the frame structure.
            av_frame_unref(self.frame)

        if packet.data != NULL:
            av_free_packet(&packet)

    cdef bytes _convert(self, AVFrame *frame, int size):
        cdef int ret
        cdef bytes bytes_buf

        cdef uint8_t *buf = <uint8_t*>malloc(size)
        if buf == NULL:
            raise FFmpegError("memory error")

        with nogil:
            ret = swr_convert(self.swrctx, &buf, size, <const uint8_t**>frame.extended_data, frame.nb_samples)
        if ret < 0:
            raise FFmpegError("unable to resample frame")

        bytes_buf = buf[:size]
        free(buf)
        return bytes_buf

    #
    # Public methods.
    #
    def read(self, int n):
        if self.closed:
            raise ValueError("I/O operation on closed file")

        while not self.eof and n > len(self.data):
            self._read_next_frame()

        data = self.data[:n]
        self.data = self.data[n:]
        return data

    def seek(self, float position):
        cdef int ret
        cdef int64_t timestamp

        if self.closed:
            raise ValueError("I/O operation on closed file")

        if not self.seekable:
            raise FFmpegError("stream is not seekable")

        if position < 0 or position > self.duration:
            raise FFmpegError("invalid position argument")

        # Convert the position to the stream-specific time base.
        timestamp = av_rescale_q(<int64_t>(position * AV_TIME_BASE),
                AV_TIME_BASE_Q, self.stream.time_base)

        # Execute the seek request.
        ret = av_seek_frame(self.ctx, self.audio_stream, timestamp, 0)
        if ret != 0:
            raise FFmpegError("unable to seek")

        # Force set the position attribute. This will be correct once the first
        # new packet is decoded.
        self.position = position
        self.data = b""

    def get_config(self):
        return self.channels, self.rate, self.format

    def get_audio_info(self):
        return audio_info(
                self.codec_name, self.codec_long_name,
                self.channels, self.rate, self.format)

    def get_stream_info(self):
        return stream_info(self.position, self.duration)

    def get_metadata(self):
        return self.tags.copy()

    def close(self):
        if not self.closed:
            avformat_close_input(&self.ctx)
            self.closed = True

    def __repr__(self):
        return "<%s %r>" % (self.__class__.__name__, self.url)


av_log_set_level(AV_LOG_QUIET)
avformat_network_init()
av_register_all()

