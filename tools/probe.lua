-- 测试探针: 开始播放后打印属性, 供 tools/verify.sh 断言.
-- script-opts:
--   probe-delay=<秒>    开始播放后等待多久再打印 (默认 0.5)
--   probe-keys=<a b>     依次模拟按键 (空格分隔), 每次按键后打印 glsl-shaders
--                        +KEY 只按下不松开 (模拟长按), -KEY 松开
--   probe-bindings=<a b> 打印这些键实际生效的绑定命令 (binding/KEY=命令)
--   probe-expand=<文本>  每次按键后打印该文本经属性展开后的结果 (检查 show-text 模板)
--   probe-hold=<秒>      打印后继续播放多久再退出 (性能测试用, 默认 0)
local opts = { delay = 0.5, keys = "", expand = "", hold = 0, bindings = "" }
require("mp.options").read_options(opts, "probe")

local props = {
    "hwdec-current", "glsl-shaders", "deband", "video-sync", "interpolation",
    "scale", "demuxer-readahead-secs", "demuxer-max-bytes", "vf",
    "audio-exclusive", "audio-samplerate", "replaygain",
    "current-tracks/audio/lang", "current-tracks/audio/external",
    "current-tracks/sub/lang", "current-tracks/sub/external", "sub-text",
    "stretch-image-subs-to-screen",
}

local function out(k, v) print(k .. "=" .. tostring(v)) end

-- 第三方脚本是否已加载: script-message-to 发给不存在的脚本时命令会失败
local scripts = { "uosc", "uosc_danmaku", "thumbfast", "hold_speed" }

-- 某个键当前生效的绑定: 同一个键取优先级最高的, 非 weak 优先
local function active_binding(key)
    local best
    for _, b in ipairs(mp.get_property_native("input-bindings") or {}) do
        if b.key == key and b.priority >= 0 and (not best
            or (best.is_weak and not b.is_weak)
            or (best.is_weak == b.is_weak and b.priority > best.priority)) then
            best = b
        end
    end
    return best and best.cmd or ""
end

local function dump()
    for _, p in ipairs(props) do out(p, mp.get_property(p, "")) end
    for _, name in ipairs(scripts) do
        local _, err = mp.command_native({ "script-message-to", name, "probe-ping" })
        out("script-loaded/" .. name, err == nil and "yes" or "no")
    end
    for k in opts.bindings:gmatch("%S+") do out("binding/" .. k, active_binding(k)) end
end

local function press_keys(list, i, done)
    if i > #list then return done() end
    local k = list[i]
    if #k > 1 and k:sub(1, 1) == "+" then
        mp.commandv("keydown", k:sub(2))
    elseif #k > 1 and k:sub(1, 1) == "-" then
        mp.commandv("keyup", k:sub(2))
    else
        mp.commandv("keypress", k)
    end
    mp.add_timeout(0.3, function()
        out("after" .. i .. "-glsl-shaders", mp.get_property("glsl-shaders", ""))
        if opts.expand ~= "" then
            out("after" .. i .. "-expand", mp.command_native({ "expand-text", opts.expand }))
        end
        press_keys(list, i + 1, done)
    end)
end

local function finish()
    mp.add_timeout(opts.hold, function()
        local passes = mp.get_property_native("vo-passes") or {}
        local total = 0
        for _, pass in ipairs(passes.fresh or {}) do total = total + (pass.avg or 0) end
        out("fresh-avg-ms", string.format("%.2f", total / 1e6))
        out("frame-drop-count", mp.get_property("frame-drop-count", ""))
        out("vo-delayed-frame-count", mp.get_property("vo-delayed-frame-count", ""))
        mp.command("quit")
    end)
end

local started = false
mp.register_event("playback-restart", function()
    if started then return end
    started = true
    mp.add_timeout(opts.delay, function()
        dump()
        local keys = {}
        for k in opts.keys:gmatch("%S+") do keys[#keys + 1] = k end
        press_keys(keys, 1, finish)
    end)
end)
