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

    cdef AVSampleFormat sample_fmt
    cdef int audio_stream
    cdef bytes data
    cdef bool eof
    cdef float time_base
    cdef float packet_duration

    #
    # Properties.
    #
    property closed:
        def __get__(self):
            return self.ctx == NULL

    #
    # Public attributes.
    #
    cdef readonly unicode url
    cdef readonly dict tags
    cdef readonly bool seekable

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
        self.tags = {}
        self.seekable = False
        self.eof = False

    def __dealloc__(self):
        if self.ctx != NULL:
            avformat_close_input(&self.ctx)
        if self.swrctx != NULL:
            swr_free(&self.swrctx)

    def __init__(self, unicode url, unicode sample_format=None):
        cdef int ret
        cdef const AVCodec *codec
        cdef bytes encoded_url = encode(url)
        cdef char *encoded_url_ptr = encoded_url

        self.url = url

        # Open the stream.
        with nogil:
            ret = avformat_open_input(&self.ctx, encoded_url_ptr, NULL, NULL)
        if ret < 0:
            raise FFmpegError("unable to open url")

        # Read a few packets to get stream information.
        with nogil:
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
        codec = avcodec_find_decoder(self.stream.codecpar.codec_id)
        self.avctx = avcodec_alloc_context3(codec)
        avcodec_parameters_to_context(self.avctx, self.stream.codecpar)
        ret = avcodec_open2(self.avctx, codec, NULL)
        if ret < 0:
            raise FFmpegError("unable to open decoder")

        # Guess the channel layout if it is unset.
        if self.avctx.ch_layout.order == 0:
            av_channel_layout_default(&self.avctx.ch_layout, self.avctx.ch_layout.nb_channels)
            if self.avctx.ch_layout.order == 0:
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
            ret = swr_alloc_set_opts2(&self.swrctx,
                    &self.avctx.ch_layout, self.sample_fmt, self.avctx.sample_rate,
                    &self.avctx.ch_layout, self.avctx.sample_fmt, self.avctx.sample_rate,
                    0, NULL)

            if ret < 0:
                raise FFmpegError("unable to open resampler")

            ret = swr_init(self.swrctx)
            if ret < 0:
                raise FFmpegError("unable to initialize resampler")

        # Gather audio information.
        self.rate = self.avctx.sample_rate
        self.channels = self.avctx.ch_layout.nb_channels
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
        # FIXME 2014-07-22 Apparently, ffmpeg cannot extract metadata from
        # ogg/vorbis files.
        cdef unicode key, value
        cdef AVDictionaryEntry *tag = NULL
        while True:
            tag = av_dict_get(self.ctx.metadata, "", tag, AV_DICT_IGNORE_SUFFIX)
            if tag == NULL:
                break
            key = self._decode(tag.key).strip().lower()
            value = self._decode(tag.value).strip()
            if value:
                self.tags[key] = value

    #
    # Private methods.
    #
    cdef unicode _decode(self, bytes s):
        return s.decode("utf8", "surrogateescape")

    cdef void _read_next_frame(self):
        cdef int ret, length, got_frame
        cdef AVPacket* packet
        cdef AVFrame *frame = av_frame_alloc()

        # Initialize the packet structure.
        packet = av_packet_alloc()

        # Read only packets from the audio stream.
        while 1:
            with nogil:
                ret = av_read_frame(self.ctx, packet)
            if ret < 0:
                # XXX av_free_packet necessary here?
                self.eof = True
                return

            if packet.stream_index == self.audio_stream:
                break

        # Update the stream position.
        self.position = float(packet.pts) * self.time_base
        self.packet_duration = float(packet.duration) * self.time_base

        # Decode the packet into the frame.
        with nogil:
            ret = avcodec_receive_frame(self.avctx, frame)
            got_frame = ret == 0
            avcodec_send_packet(self.avctx, packet)

        if got_frame:
            # A complete frame was produced.
            size = av_samples_get_buffer_size(NULL,
                    self.avctx.ch_layout.nb_channels, frame.nb_samples,
                    self.sample_fmt, 1)

            if size >= 0:
                if self.swrctx != NULL:
                    # Reorder planar audio data or convert to a different
                    # sample layout.
                    self.data += self._convert(frame, size)
                else:
                    self.data += (<char*>frame.data[0])[:size]

        # Free the referenced data from the frame structure.
        av_frame_unref(frame)

        if packet.data != NULL:
            av_packet_unref(packet)
        av_frame_free(&frame)

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

    def __iter__(self):
        while not self.eof:
            self._read_next_frame()
            if self.data:
                yield self.data
            self.data = b""

    def seek(self, float position):
        # XXX The seeking accuracy seems to differ considerably between
        # different formats and files (~2s). In order to conduct an accurate
        # seek, we seek a few frames before the actual timestamp and decode
        # from there after the av_seek_frame() call. If there is a better way,
        # I'd be happy to take advice.
        cdef int ret
        cdef int64_t timestamp

        if self.closed:
            raise ValueError("I/O operation on closed file")

        if not self.seekable:
            raise FFmpegError("stream is not seekable")

        if position < 0 or position > self.duration:
            raise FFmpegError("position argument out of range")

        # Empty the output buffer.
        self.data = b""

        # One second should give us enough room.
        self.position = max(0, position - 1)

        # Convert the position to the stream-specific time base.
        timestamp = av_rescale_q(<int64_t>(self.position * AV_TIME_BASE),
                AV_TIME_BASE_Q, self.stream.time_base)

        # Execute the seek request.
        ret = av_seek_frame(self.ctx, self.audio_stream, timestamp, 0)
        if ret != 0:
            raise FFmpegError("unable to seek")

        # Decode packets up to the actual position.
        while self.position + self.packet_duration < position:
            self.data = b""
            self._read_next_frame()

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

    def __repr__(self):
        return "<%s %r>" % (self.__class__.__name__, self.url)


av_log_set_level(AV_LOG_QUIET)
avformat_network_init()

