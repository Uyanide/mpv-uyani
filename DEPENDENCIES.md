# 外部依赖

## 播放

| 依赖                          | 用途                                                            |
| ----------------------------- | --------------------------------------------------------------- |
| mpv 0.41                      | 播放器本体                                                      |
| yt-dlp                        | 播放网络视频                                                    |
| Google Chrome + GNOME Keyring | yt-dlp 读取 cookie (`cookies-from-browser=chrome+gnomekeyring`) |
| curl                          | uosc_danmaku 获取弹幕                                           |

## 字体

字体文件需要在系统中安装:

| 字体          | 用途            |
| ------------- | --------------- |
| Noto Sans CJK | 字幕默认字体    |
| danmaku       | 弹幕字体 (见下) |

弹幕使用一个虚拟字体名 `danmaku`, 由 fontconfig 定义 (`~/.config/fontconfig/fonts.conf`), 例如:

```xml
<alias>
  <family>danmaku</family>
  <prefer>
    <family>Noto Sans</family>
    <family>Noto Sans CJK SC</family>
    <family>Noto Sans CJK JP</family>
    <family>Noto Sans CJK KR</family>
    <family>Symbola</family>
  </prefer>
</alias>
```

这样做是因为 libass 不能渲染彩色 emoji 字体, 弹幕里的 emoji (主要来自巴哈姆特动画疯) 只能用 Symbola 这样的单色字体显示. 把 Symbola 只放在 `danmaku` 里, 这样系统其他地方的彩色 emoji 不受影响.

为什么不用…:

- `fontname=Symbola`: libass 缺字时先退到默认字体族 (即 `osd-font`), 然后才轮到 fontconfig 系统回退. 默认字体族总能找到中文, 所以每次都会打警告 `[osd/libass] fontselect: Using default font family: (Symbola, 700, 0) -> ...`. 另外拉丁字母和假名会用 Symbola 的衬线体渲染, 和中文混排很难看.
- `fontname=Symbola,Noto Sans CJK SC`: libass 不支持逗号分隔的回退列表, 会把整串当作一个字体名, 找不到, emoji 全部报 `failed to find any fallback with glyph ...` 并显示不出来.

libass 只有 fontconfig 的替换规则 (`<prefer>` / `<accept>`) 能提供不报警的回退, 所以绕不开 fontconfig.

## 测试 (`tools/verify.sh`)

| 依赖    | 用途       |
| ------- | ---------- |
| ffmpeg  | 生成测试片 |
| python3 | 测试网络流 |
