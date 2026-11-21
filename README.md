# MPV-Uyani

极度精简和实用主义的个人 mpv 配置. 外部依赖见 [DEPENDENCIES.md](DEPENDENCIES.md).

适配 macOS 与 Linux.

## 特性

- [uosc](https://github.com/tomasklaen/uosc) - UI; 基本是默认配置
- [uosc_danmaku](https://github.com/Tony15246/uosc_danmaku) - 弹幕插件
- [thumbfast](https://github.com/po5/thumbfast) - 进度条缩略图
- [anime4k](https://github.com/bloc97/Anime4K) - 唯一的着色器, 支持且仅支持 Mode A Fast/HQ 档位切换
- hold_speed.lua - 长按倍速; 本仓库脚本

其余功能均为 mpv 内置 (如: 播放历史 / yt-dlp / 截图 / high-quality 画质 etc.).

### 为什么没有…

- Jellyfin

  由 [jellyfin-mpv-shim](https://github.com/jellyfin/jellyfin-mpv-shim) 配置 mpv_ext 拉起 mpv, mpv 侧无需额外配置.

- WebDAV / Samba

  通过文件系统挂载, mpv 侧无需额外配置.

- 在线字幕 / AI 字幕 / 自动字幕同步

  配置繁琐且效果一般.

- 其他所有

  我不用🤗

## 部署

```bash
# 假设仓库目标位置为 ~/Projects/mpv-uyani
git clone --recurse-submodules https://github.com/Uyanide/mpv-uyani.git ~/Projects/mpv-uyani
# 若配置目录已存在则失败; 记得先备份喵
! [ -e ~/.config/mpv ] && ln -sfn ../Projects/mpv-uyani ~/.config/mpv
```

## 插件管理

所有第三方插件通过 git submodule 和符号链接管理 (除了 Anime4K, 源仓库实在太大而且很多文件都用不到).

### 更新

```bash
git submodule update --remote --depth 1   # 拉取提交
git diff --submodule=log                  # 查看更新
git commit -am "bump submodules"
```

避免使用插件自带的更新功能, 它们会直接改写 `vendor/` 里的文件, 污染 submodule.

### 回滚

以 uosc 为例:

```bash
git -C vendor/uosc fetch --depth 1 origin <commit>
git -C vendor/uosc checkout <commit>
git commit -am "pin uosc to <commit>"
```

### 添加

```bash
git submodule add -b <分支> --depth 1 <仓库地址> vendor/<名字>
git config -f .gitmodules submodule.vendor/<名字>.shallow true
# 如果需要脚本 (其他同理):
ln -s ../vendor/<名字>/<脚本文件或目录> scripts/
```

只把需要的文件链接进对应目录. `vendor/` 里的其他文件不会被 mpv 加载.

## 验证

```bash
tools/verify.sh
```

脚本会生成合成测试片, 用本仓库作为配置目录 (`--config-dir`)播放, 然后断言实际生效的属性. 运行期间会短暂弹出 mpv 窗口. 需要 ffmpeg 和 python3.

## 约定

- 避免在 `fonts/` 里放任何适合系统全局安装的字体 (e.g. Noto Sans CJK).
- 避免在配置文件中重复设置默认值.
- 通过 git submodule 和符号链接管理外部来源的文件; 违例需额外注明出处.
- 同类功能仅保留一份实现, 并移除或禁用其他实现 (e.g. 播放历史).
