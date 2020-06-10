
local stool = require("stool")
local optl = require("optl")
local ngx_shared = ngx.shared
local ngx_ctx = ngx.ctx
local next_tb = ngx_ctx.next_tb or {}
local statistics_dict = ngx_shared["statistics_dict"]
local config = optl.config
local config_base = config.base
local statistics_Mod = config_base.statistics_Mod
local debug_log_Mod = config_base.debug_log_Mod

if next_tb.base_msg then

    local base_msg = next_tb.base_msg
    -- 记录请求的原始数据日志（方便排查线上的问题  后续可以按天进行分割）
    if debug_log_Mod.state == "on" then
        stool.writefile(debug_log_Mod.logpath,stool.tableTojsonStr(base_msg).."\n\n")
    end

    -- 判断 statistics_Mod 是否开启
    -- 统计模块
    if statistics_Mod.state == "on" then
        -- 去除不重要域名
        if not statistics_Mod.match_hosts[base_msg.http_host] then
            return
        end
        -- 去除静态资源文件 ？
        for _,v in ipairs(statistics_Mod.exclude_urls) do
            -- remath_Invert(_str , _re_str , _options , _Invert)
            if optl.remath_Invert(base_msg.uri,v[1],v[2],v[3]) then
                return
            end
        end
        -- 使用 连接符 '?' 连接 域名 - uri - ip 插入到dict中
        local tmp = string.format("%s?%s?%s",base_msg.http_host,base_msg.uri,base_msg.remoteIp)
        local re = statistics_dict:get(tmp)
        if re then
            statistics_dict:incr(tmp,1,60 * 1)
        else
            statistics_dict:set(tmp,1,60 * 1)
        end
    end

end