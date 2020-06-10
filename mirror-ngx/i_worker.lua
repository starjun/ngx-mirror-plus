

local _worker_count = ngx.worker.count()
local _worker_id = ngx.worker.id()

local ngx_shared = ngx.shared
local ipairs = ipairs
local stool = require("stool")
local ngx_log = ngx.log
local ngx_ERR = ngx.ERR
local ngx_thread = ngx.thread
local timer_every = ngx.timer.every
local config_dict = ngx_shared.config_dict
local statistics_dict = ngx_shared.statistics_dict
local cjson_safe = require "cjson.safe"
local http = require "resty.http"
local mysql = require "resty.mysql"


local handler_zero
local config = cjson_safe.decode(config_dict:get("config"))
local config_base = config.base
local statistics_Mod = config_base.statistics_Mod
local filepath

-- dict 清空过期内存
local function flush_expired_dict()
    local dict_list = {"config_dict","statistics_dict","passive_dict"}
    for _,v in ipairs(dict_list) do
        ngx_shared[v]:flush_expired()
    end
end

handler_zero = function ()
    if config_base.autoSync.state == "Master" then
        -- todo
    elseif config_base.autoSync.state == "Slave" then
        -- todo
    else
        -- nothing todo
    end

    --清空过期内存
    ngx_thread.spawn(flush_expired_dict)
end


-- mysql ops
local function mysql_insert(_type,_sql)
    local mysql_tb = config_base.statistics_Mod.mysql
    local db, err = mysql:new()
    if not db then
        local msg = "failed to instantiate mysql: ".. err .."\n"
        stool.writefile(filepath,msg)
        return
    end

    db:set_timeout(100000) -- 100 sec

    local ok, err, errcode, sqlstate = db:connect{
        host = mysql_tb.host,
        port = mysql_tb.port,
        database = mysql_tb.database,
        user = mysql_tb.user,
        password = mysql_tb.password,
        charset = mysql_tb.charset or "utf8",
        max_packet_size = 1024 * 1024,
    }

    if not ok then
        local msg = "failed to connect: ".. err.. "\n"
        stool.writefile(filepath,msg)
        return
    end

    local function mysqlKeepalive()
        -- put it into the connection pool of size 100,
        -- with 10 seconds max idle timeout
        local ok, err = db:set_keepalive(10000, 100)
        if not ok then
            local msg = "failed to set keepalive: "..err.."\n"
            --stool.writefile(filepath,msg)
        end
    end

    -- do realtime insert to mysql
    if _type == "realtime" then
        --local sql = string.format("insert into cats (name) values (),(),()", ···)
        local res, err, errcode, sqlstate = db:query(_sql)
        if not res then
            local msg = "bad result: "..err.." errcode : "..errcode.." sqlstate : "..sqlstate.."\n"
            stool.writefile(filepath,msg)
        end
    else
        -- do global insert to mysql
    end
    mysqlKeepalive()
end


local function main_zero()
    local logpath = config_base.logPath or "./"
    filepath = logpath.."mirror-ngx.log"
    local tb_keys = statistics_dict:get_keys(0)
    local all_tb = {}
    for _,v in ipairs(tb_keys) do
        local tmp_v = statistics_dict:get(v)
        if tmp_v > statistics_Mod.min_num then
            all_tb[v] = tmp_v
        end
        statistics_dict:delete(v)
    end
    local ngx_ctime = ngx.localtime()
    local tb_sql_realtime = {}
    for k,v in pairs(all_tb) do
        local split_tb = stool.split(k,'?')
        -- string.format("%s?%s?%s",base_msg.http_host,base_msg.uri,base_msg.remoteIp)
        -- split_tb[1] = host ;  split_tb[2] = uri ;  split_tb[3] = ip
        local tmpsql = string.format("insert into realtime_host_uri_ip(host,uri,ip,cnt,cTime) values('%s','%s','%s',%d,'%s')",
            split_tb[1],split_tb[2],split_tb[3],v,ngx_ctime)
        table.insert(tb_sql_realtime,tmpsql)
    end
    -- insert into mysql
    if #tb_sql_realtime > 0 then
        local str_realtime_waf = table.concat(tb_sql_realtime, ";")
        mysql_insert("realtime",str_realtime_waf)
    end
end


if _worker_id == 0 then
    local timeAt = config_base.autoSync.timeAt or 5
    timer_every(timeAt,handler_zero)

    -- 执行 12s 定时操作
    -- statistics_Mod 模块执行
    if statistics_Mod.state == "on" then
        timer_every(12,main_zero)
    end
end
