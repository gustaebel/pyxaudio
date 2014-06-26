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

from libc.stdint cimport uint8_t, uint64_t, int64_t
from libc.stdlib cimport malloc, free

from cpython cimport bool

cdef extern from "libavutil/rational.h":
    struct AVRational:
        int num
        int den

cdef extern from "libavutil/avutil.h":
    int AV_TIME_BASE
    AVRational AV_TIME_BASE_Q

    enum AVMediaType:
        AVMEDIA_TYPE_AUDIO

cdef extern from "libavutil/channel_layout.h":
    int AV_CH_LAYOUT_STEREO

    int64_t av_get_default_channel_layout(int)

cdef extern from "libavutil/dict.h":
    int AV_DICT_IGNORE_SUFFIX

    struct AVDictionary:
        pass

    struct AVDictionaryEntry:
        char *key
        char *value

    AVDictionaryEntry *av_dict_get(AVDictionary*, const char*, const AVDictionaryEntry*, int)

cdef extern from "libavutil/frame.h":
    AVFrame *av_frame_alloc()
    void av_frame_unref(AVFrame*)
    void av_frame_free(AVFrame**)

cdef extern from "libavutil/log.h":
    void av_log_set_level(int)

    int AV_LOG_QUIET
    int AV_LOG_VERBOSE

cdef extern from "libavutil/mathematics.h":
    int64_t av_rescale_q(int64_t, AVRational, AVRational)

cdef extern from "libavutil/samplefmt.h":
    enum AVSampleFormat:
        AV_SAMPLE_FMT_U8
        AV_SAMPLE_FMT_S16
        AV_SAMPLE_FMT_S32
        AV_SAMPLE_FMT_FLT
        AV_SAMPLE_FMT_DBL

    int av_samples_get_buffer_size(int*, int, int, AVSampleFormat, int)
    int av_sample_fmt_is_planar(AVSampleFormat)
    AVSampleFormat av_get_packed_sample_fmt(AVSampleFormat)

cdef extern from "libavcodec/avcodec.h":
    struct AVCodec:
        const char *name
        const char *long_name

    enum AVCodecID:
        pass

    struct AVCodecContext:
        AVCodec *codec
        AVCodecID codec_id
        AVSampleFormat sample_fmt
        int sample_rate
        int channels
        uint64_t channel_layout

    struct AVFrame:
        uint8_t **data
        uint8_t **extended_data
        int nb_samples
        int sample_rate
        int channels
        uint64_t channel_layout
        int *linesize

    struct AVPacket:
        uint8_t *data
        int size
        int stream_index
        int64_t pts

    void av_init_packet(AVPacket*)
    void av_free_packet(AVPacket*)

    AVCodec *avcodec_find_decoder(AVCodecID)
    int avcodec_decode_audio4(AVCodecContext*, AVFrame*, int*, AVPacket*) nogil
    int avcodec_open2(AVCodecContext*, AVCodec*, AVDictionary**)

cdef extern from "libavformat/avio.h":
    struct AVIOContext:
        int seekable

cdef extern from "libavformat/avformat.h":
    struct AVStream:
        AVCodecContext *codec
        AVRational time_base

    struct AVFormatContext:
        AVStream **streams
        AVDictionary *metadata
        int64_t duration
        AVIOContext *pb

    struct AVInputFormat:
        pass

    void av_register_all()
    int avformat_network_init()

    int avformat_open_input(AVFormatContext**, const char*, AVInputFormat*, AVDictionary**)
    void avformat_close_input(AVFormatContext**)

    int av_read_frame(AVFormatContext*, AVPacket*) nogil
    int av_seek_frame(AVFormatContext*, int, int64_t, int)

    int avformat_find_stream_info(AVFormatContext*, AVDictionary**)
    int av_find_best_stream(AVFormatContext*, AVMediaType, int, int, AVCodec**, int)

cdef extern from "libswresample/swresample.h":
    struct SwrContext:
        pass

    void swr_free(SwrContext**)
    SwrContext *swr_alloc_set_opts(SwrContext*, int64_t, AVSampleFormat, int, int64_t, AVSampleFormat, int, int, void*)
    int swr_init(SwrContext*)
    int swr_convert(SwrContext*, uint8_t**, int, const uint8_t**, int) nogil

