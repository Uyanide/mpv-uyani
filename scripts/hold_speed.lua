-- 单击暂停, 长按倍速播放, 松开恢复原速度和暂停状态.
--
-- 用法 (input.conf): SPACE script-binding hold_speed/hold
-- 「长按」= 按住超过 input-ar-delay (默认 200 ms), 即收到第一个自动重复事件.
--
-- script-opts: hold_speed-speed=<倍速> (默认 3)
local opts = { speed = 3 }
require("mp.options").read_options(opts, "hold_speed")

local holding = false
local saved_speed, saved_pause

local function flash_speed()
    mp.commandv("script-message-to", "uosc", "flash-elements", "speed")
end

local function start_hold()
    holding = true
    saved_speed = mp.get_property_number("speed")
    saved_pause = mp.get_property_bool("pause")
    mp.set_property_number("speed", opts.speed)
    mp.set_property_bool("pause", false)
    flash_speed()
end

local function end_hold()
    holding = false
    mp.set_property_number("speed", saved_speed)
    mp.set_property_bool("pause", saved_pause)
    flash_speed()
end

mp.add_key_binding(nil, "hold", function(e)
    if e.event == "repeat" then
        if not holding then start_hold() end
    elseif e.event == "up" then
        if holding then end_hold() elseif not e.canceled then mp.command("cycle pause") end
    elseif e.event == "press" then -- 没有按下/抬起之分的输入 (如部分遥控器)
        mp.command("cycle pause")
    end
end, { complex = true, repeatable = true })
