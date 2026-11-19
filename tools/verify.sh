#!/usr/bin/env bash
# 用本仓库作为配置目录播放合成测试片, 断言生效的属性值。
# 用法: tools/verify.sh            (会短暂弹出 mpv 窗口)
# 环境变量: VERIFY_MEDIA=<目录>    测试片存放位置 (默认新建临时目录)
set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
MEDIA=${VERIFY_MEDIA:-$(mktemp -d)}
mkdir -p "$MEDIA"
rm -rf "$MEDIA/watch_later"   # 避免上次运行保存的进度让本次从片尾续播
fails=0

gen() { # gen <文件名> <ffmpeg 编码参数...>
    local f="$MEDIA/$1"; shift
    [ -s "$f" ] || ffmpeg -loglevel error -y -f lavfi -i "$1" -t 3 "${@:2}" "$f"
}
gen h264_1080.mkv testsrc2=s=1920x1080:r=24 -c:v libx264 -pix_fmt yuv420p
gen h264_720.mkv  testsrc2=s=1280x720:r=24  -c:v libx264 -pix_fmt yuv420p
gen vp9_10bit.webm testsrc2=s=1920x1080:r=24 -c:v libvpx-vp9 -b:v 1M -profile:v 2 -pix_fmt yuv420p10le
gen wide.mkv      testsrc2=s=1920x800:r=24   -c:v libx264 -pix_fmt yuv420p
mkdir -p "$MEDIA/long"   # 单独目录: 不让 autocreate-playlist 把它加进其他用例的播放列表
gen long/long.mkv testsrc2=s=320x240:r=5     -c:v libx264 -pix_fmt yuv420p -t 200

srt() { # srt <编码> <输出文件> <第一条字幕>: 生成多条字幕, 长度足够让编码检测可靠
    [ -s "$2" ] && return
    {
        printf '1\n00:00:00,000 --> 00:00:03,000\n%s\n\n' "$3"
        local i
        for i in 2 3 4 5 6 7 8; do
            printf '%d\n00:00:%02d,000 --> 00:00:%02d,500\n%s (%d)\n\n' "$i" "$((i + 1))" "$((i + 1))" "$3" "$i"
        done
    } | iconv -f UTF-8 -t "$1" > "$2" || { rm -f "$2"; echo "iconv 失败: $2" >&2; exit 2; }
}

# 音频、字幕测试素材
if [ ! -s "$MEDIA/lang.mkv" ]; then   # 内封: 音轨 eng/jpn, 字幕 eng/zh-Hant/zh-Hans
    srt UTF-8 "$MEDIA/in-eng.srt" 'English line'
    srt UTF-8 "$MEDIA/in-cht.srt" '這是繁體字幕'
    srt UTF-8 "$MEDIA/in-chs.srt" '这是简体字幕'
    ffmpeg -loglevel error -y -f lavfi -i testsrc2=s=1280x720:r=24 -f lavfi -i sine=440 -f lavfi -i sine=880 \
        -i "$MEDIA/in-eng.srt" -i "$MEDIA/in-cht.srt" -i "$MEDIA/in-chs.srt" -t 3 \
        -map 0 -map 1 -map 2 -map 3 -map 4 -map 5 -c:v libx264 -c:a aac -c:s srt \
        -metadata:s:a:0 language=eng -metadata:s:a:1 language=jpn \
        -metadata:s:s:0 language=eng -metadata:s:s:1 language=zh-Hant -metadata:s:s:2 language=zh-Hans \
        "$MEDIA/lang.mkv"
fi
mkdir -p "$MEDIA/ext/subs" "$MEDIA/ext/audios" "$MEDIA/big5" "$MEDIA/music"
[ -s "$MEDIA/ext/ep01.mkv" ] || ffmpeg -loglevel error -y -i "$MEDIA/h264_720.mkv" -c copy "$MEDIA/ext/ep01.mkv"
[ -s "$MEDIA/ext/audios/ep01.jpn.mka" ] ||
    ffmpeg -loglevel error -y -f lavfi -i sine=660 -t 3 -c:a aac "$MEDIA/ext/audios/ep01.jpn.mka"
srt BIG5 "$MEDIA/ext/subs/ep01.cht.srt" '這是外掛繁體字幕'
srt GBK  "$MEDIA/ext/subs/ep01.chs.srt" '这是外挂简体字幕'
[ -s "$MEDIA/big5/ep02.mkv" ] || ffmpeg -loglevel error -y -i "$MEDIA/h264_720.mkv" -c copy "$MEDIA/big5/ep02.mkv"
srt BIG5 "$MEDIA/big5/ep02.cht.srt" '這是繁體中文字幕, 測試編碼'
[ -s "$MEDIA/music/song.flac" ] ||
    ffmpeg -loglevel error -y -f lavfi -i sine=440 -t 3 -c:a flac "$MEDIA/music/song.flac"
[ -s "$MEDIA/music/song.lrc" ] || printf '[00:00.00]歌词测试\n[00:02.00]第二行\n' > "$MEDIA/music/song.lrc"

probe() { # probe <mpv 参数...>; 输出探针的 KEY=VALUE 行
    timeout 60 mpv --config-dir="$REPO" --ao=null --really-quiet \
        --watch-later-dir="$MEDIA/watch_later" --no-resume-playback --no-save-watch-history \
        --script-opts-append=uosc_danmaku-history_path="$MEDIA/danmaku-history.json" \
        --msg-level=all=error,probe=info --script="$REPO/tools/probe.lua" "$@" 2>&1 |
        sed -n 's/^\[probe\] //p'
}

expect() { # expect <用例名> <探针输出> <KEY=正则>...
    local name=$1 output=$2; shift 2
    local kv key re val
    for kv in "$@"; do
        key=${kv%%=*} re=${kv#*=}
        val=$(printf '%s\n' "$output" | awk -v k="$key=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }')
        if printf '%s\n' "$val" | grep -qxE "$re"; then
            printf 'ok    %-22s %s=%s\n' "$name" "$key" "$val"
        else
            printf 'FAIL  %-22s %s=%s (期望 /%s/)\n' "$name" "$key" "$val" "$re"
            fails=$((fails + 1))
        fi
    done
}

A4K_DIR='~~/shaders/anime4k'
A4K_FAST="$A4K_DIR/Anime4K_Clamp_Highlights.glsl:$A4K_DIR/Anime4K_Restore_CNN_M.glsl:$A4K_DIR/Anime4K_Upscale_CNN_x2_M.glsl:.+:$A4K_DIR/Anime4K_Upscale_CNN_x2_S.glsl"
A4K_HQ="$A4K_DIR/Anime4K_Clamp_Highlights.glsl:$A4K_DIR/Anime4K_Restore_CNN_VL.glsl:$A4K_DIR/Anime4K_Upscale_CNN_x2_VL.glsl:.+:$A4K_DIR/Anime4K_Upscale_CNN_x2_M.glsl"

# 配置本身
errs=$(timeout 60 mpv --config-dir="$REPO" --ao=null --frames=1 --no-resume-playback \
    --watch-later-dir="$MEDIA/watch_later" --no-save-watch-history --msg-level=all=error \
    "$MEDIA/h264_720.mkv" 2>&1 | grep -iE 'error|fail' | tr '\n' ' ')
expect config-load "config-errors=$errs" 'config-errors='

# 第三方脚本
out=$(probe "$MEDIA/h264_720.mkv")
expect scripts "$out" 'script-loaded/uosc=yes' 'script-loaded/uosc_danmaku=yes' 'script-loaded/thumbfast=yes' \
    'script-loaded/hold_speed=yes'

# 核心播放
out=$(probe "$MEDIA/h264_1080.mkv")
expect local-1080p "$out" 'hwdec-current=vulkan|nvdec' 'demuxer-readahead-secs=1\.0+'

out=$(probe "$MEDIA/vp9_10bit.webm")
expect vp9-10bit "$out" 'hwdec-current=vulkan|nvdec'

out=$(probe --vf=fps=60/1.001 "$MEDIA/h264_1080.mkv")   # 模拟 uosc_danmaku 的 vf_fps
expect danmaku-fps-vf "$out" 'vf=.*fps.*' 'hwdec-current=.+'

port=$((20000 + RANDOM % 20000))
python3 -m http.server -b 127.0.0.1 -d "$MEDIA" "$port" >/dev/null 2>&1 &
srv=$!
sleep 1
out=$(probe "http://127.0.0.1:$port/h264_1080.mkv")
kill "$srv"
expect http-stream "$out" 'demuxer-readahead-secs=120\.0+' 'demuxer-max-bytes=1073741824|1\.0+ GiB'

# Smooth Motion 的命令行参数 (除环境变量外)
out=$(probe --video-sync=audio --interpolation=no --hwdec=nvdec-copy "$MEDIA/h264_1080.mkv")
expect mpv-sm-args "$out" 'hwdec-current=nvdec-copy' 'interpolation=no' 'glsl-shaders='

# 画质
out=$(probe "$MEDIA/h264_1080.mkv")
expect picture-1080p "$out" 'glsl-shaders=' 'deband=yes' 'scale=ewa_lanczossharp' \
    'video-sync=audio' 'interpolation=no'

out=$(probe "$MEDIA/h264_720.mkv")
expect picture-720p "$out" 'glsl-shaders='

# Ctrl+1 开 Fast → Ctrl+2 直接换成 HQ → Ctrl+2 关; 再 Ctrl+1 开 Fast → Ctrl+1 关
A4K_TEXT='${?glsl-shaders==:关}${!glsl-shaders==:开}'
out=$(probe --script-opts-append='probe-keys=Ctrl+1 Ctrl+2 Ctrl+2 Ctrl+1 Ctrl+1' \
    --script-opts-append="probe-expand=$A4K_TEXT" \
    "$MEDIA/h264_1080.mkv")
expect anime4k-toggle "$out" "after1-glsl-shaders=$A4K_FAST" 'after1-expand=开' \
    "after2-glsl-shaders=$A4K_HQ" 'after2-expand=开' \
    'after3-glsl-shaders=' 'after3-expand=关' \
    "after4-glsl-shaders=$A4K_FAST" 'after5-glsl-shaders='

# input.conf 引用的每个着色器文件都存在
missing=$(grep -o '~~/shaders/[^":]*\.glsl' "$REPO/input.conf" | sort -u | sed "s|^~~|$REPO|" \
    | while read -r f; do [ -f "$f" ] || printf '%s ' "${f#$REPO/}"; done)
expect shader-files "missing=$missing" 'missing='

# 音频
out=$(probe "$MEDIA/lang.mkv")
expect audio-defaults "$out" 'audio-exclusive=no' 'audio-samplerate=0' 'replaygain=no'
expect alang "$out" 'current-tracks/audio/lang=jpn'

out=$(probe "$MEDIA/ext/ep01.mkv")
expect external-audio "$out" 'current-tracks/audio/external=yes' 'current-tracks/audio/lang=jpn'

# 字幕
out=$(probe "$MEDIA/lang.mkv")
expect slang-embedded "$out" 'current-tracks/sub/lang=zh-Hans' 'sub-text=这是简体字幕'

out=$(probe "$MEDIA/ext/ep01.mkv")
expect slang-external-gbk "$out" 'current-tracks/sub/external=yes' 'current-tracks/sub/lang=chs' \
    'sub-text=这是外挂简体字幕'

out=$(probe "$MEDIA/big5/ep02.mkv")
expect big5-codepage "$out" 'current-tracks/sub/lang=cht' 'sub-text=這是繁體中文字幕, 測試編碼'

out=$(probe "$MEDIA/music/song.flac")
expect lrc-lyrics "$out" 'current-tracks/sub/external=yes' 'sub-text=歌词测试'

out=$(probe "$MEDIA/wide.mkv")
expect pgs-fix-wide "$out" 'stretch-image-subs-to-screen=yes'
out=$(probe "$MEDIA/h264_1080.mkv")
expect pgs-fix-16x9 "$out" 'stretch-image-subs-to-screen=no'

# 界面
out=$(probe --script-opts-append='probe-keys=MBTN_RIGHT' \
    --script-opts-append='probe-expand=${user-data/uosc/menu/type}|${playback-time/full}' "$MEDIA/h264_720.mkv")
expect menu-open "$out" 'after1-expand=menu\|[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}'

# 右键菜单的结构, 以及菜单和控制栏引用的 uosc / uosc_danmaku 命令是否存在 (防止 submodule 更新后改名)
menu=$(sed -n 's/^\([^ ]*\) \+\([^#]*\)#! *\(.*\)$/\2\t\3/p' "$REPO/input.conf")
top=$(printf '%s\n' "$menu" | cut -f2 | sed 's/ *>.*//' | awk '!seen[$0]++' | paste -sd,)
expect menu-structure "top=$top" 'top=打开,轨道,画面,弹幕,工具,退出'
missing=
for b in $(printf '%s\n' "$menu" | grep -o 'script-binding uosc/[a-z-]*' | sed 's|.*/||'); do
    grep -q "bind_command('$b'" "$REPO"/vendor/uosc/src/uosc/main.lua || missing="$missing uosc/$b"
done
for m in $(printf '%s\n' "$menu" | grep -o 'script-message-to uosc_danmaku [a-z_]*' | cut -d' ' -f3) danmaku-delay; do
    grep -rq "register_script_message(\"$m\"" "$REPO"/vendor/uosc_danmaku || missing="$missing danmaku:$m"
done
for btn in $(grep -o 'button:[a-z_]*' "$REPO/script-opts/uosc.conf" | cut -d: -f2); do
    grep -A1 '"set-button",' "$REPO"/vendor/uosc_danmaku/modules/menu.lua | grep -q "\"$btn\"," ||
        missing="$missing button:$btn"
done
expect menu-targets "missing=$missing" 'missing='

# 键位与弹幕
# 都在暂停状态下按键, 避免 3 秒的测试片放完、跳到 autocreate-playlist 加入的下一个文件
out=$(probe --pause --script-opts-append='probe-keys=SPACE SPACE +SPACE -SPACE' \
    --script-opts-append='probe-expand=${pause} ${speed}' "$MEDIA/lang.mkv")
expect hold-space "$out" 'after1-expand=no 1' 'after2-expand=yes 1' 'after3-expand=no 3' 'after4-expand=yes 1'

out=$(probe --pause --script-opts-append='probe-keys=ü + + Ü *' \
    --script-opts-append='probe-expand=${speed}' "$MEDIA/lang.mkv")
expect speed-keys "$out" 'after1-expand=0\.9' 'after3-expand=1\.1' 'after4-expand=0\.55' 'after5-expand=1\.1'

out=$(probe --pause --script-opts-append='probe-keys=UP DOWN DOWN y Alt+RIGHT Alt+LEFT Alt+LEFT j Ctrl+d' \
    --script-opts-append='probe-expand=${volume}|${sub-delay}|${video-rotate}|${sid}|${user-data/uosc_danmaku/danmaku-switch-on}' \
    --script-opts-append='probe-bindings=MBTN_LEFT MBTN_RIGHT WHEEL_UP WHEEL_DOWN Ctrl+D Alt+d ~' "$MEDIA/lang.mkv")
expect misc-keys "$out" 'after1-expand=105\|.*' 'after3-expand=95\|.*' 'after4-expand=95\|-100 ms\|.*' \
    'after5-expand=.*\|90\|.*' 'after7-expand=.*\|270\|.*' 'after8-expand=.*\|no\|false' 'after9-expand=.*\|no\|true' \
    'binding/MBTN_LEFT=cycle pause' 'binding/MBTN_RIGHT=script-binding uosc/menu' \
    'binding/WHEEL_UP=no-osd add volume  10;.*' 'binding/WHEEL_DOWN=no-osd add volume -10;.*' \
    'binding/Ctrl+D=.*open_add_total_menu' 'binding/Alt+d=.*open_search_danmaku_menu' 'binding/~=script-binding console/enable'

out=$(probe --pause --script-opts-append='probe-keys=Shift+UP Shift+DOWN' \
    --script-opts-append='probe-expand=${=time-pos}' "$MEDIA/long/long.mkv")
expect seek-85 "$out" 'after1-expand=85(\.0+)?' 'after2-expand=0(\.0+)?'

out=$(probe --pause --script-opts-append='probe-expand=${playlist-count}' --script-opts-append='probe-keys=p' \
    "$MEDIA/h264_720.mkv")
expect autocreate-playlist "$out" 'after1-expand=[2-9]'

echo
if [ "$fails" -eq 0 ]; then echo "全部通过"; else echo "$fails 项失败"; exit 1; fi
