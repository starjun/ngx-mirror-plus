

-----  content by zj  -----
local ngx_var              = ngx.var
local ngx_ctx              = ngx.ctx
local optl                 = require("optl")
local stool                = require("stool")
local mysql                = require "resty.mysql"
local redis                = require("resty.redis")
local parser               = require "resty.bodyparser"
local ngx_unescape_uri     = ngx.unescape_uri
local passive_dict         = ngx.shared["passive_dict"]

local base_msg             = {}
base_msg.scheme            = ngx_var.scheme
base_msg.uri               = ngx_var.uri
base_msg.remoteIp          = ngx_var.remote_addr
base_msg.http_host         = ngx_unescape_uri(ngx_var.http_host)
base_msg.method            = ngx_var.request_method
base_msg.referer           = ngx_unescape_uri(ngx_var.http_referer)
-- base_msg.useragent         = ngx_unescape_uri(ngx_var.http_user_agent)
-- base_msg.cookie            = ngx_unescape_uri(ngx_var.http_cookie)
-- base_msg.request_uri       = ngx_unescape_uri(ngx_var.request_uri)
base_msg.query_string      = ngx_unescape_uri(ngx_var.query_string)
base_msg.http_content_type = ngx_var.http_content_type
base_msg.headers           = ngx.req.get_headers()
base_msg.args              = ngx.req.get_uri_args()
-- base_msg.args_data         = ngx_unescape_uri(stool.get_table(args))
if base_msg.method == "POST" or base_msg.method == "PUT" then
    base_msg.posts_all = optl.get_post_all()
end
base_msg.ctime             = ngx.time()
local next_tb              = { base_msg = base_msg }
ngx_ctx.next_tb            = next_tb

local config_base = optl.config.base
local cjson       = stool.cjson_safe
local kafka_Mod   = config_base.kafka_Mod
local passive_Mod = config_base.passive_Mod
-- local client      = require "resty.kafka.client"
local producer    = require "resty.kafka.producer"

-- 判断 kafka_Mod 开关是否开启
if kafka_Mod.state == "on" then
    local broker_list = kafka_Mod.broker_list
    local prod_type   = kafka_Mod.producer_type or "async"
    local topic       = kafka_Mod.topic or "mirror-ngx-log"
    local key         = kafka_Mod.key or "base_msg"

    -- sync producer_type
    if prod_type == "sync" then
        local p = producer:new(broker_list)
        local offset, err = p:send(topic, key, cjson.encode(base_msg))
        if not offset then
            local msg = "send err: ".. err
            ngx.log(ngx.ERR,msg)
            return
        end
        -- ngx.say("send success, offset: ", tonumber(offset))

    elseif prod_type == "async" then
        local bp = producer:new(broker_list, { producer_type = prod_type })
        local ok, err = bp:send(topic, key, cjson.encode(base_msg))
        if not ok then
            local msg = "send err: ".. err
            ngx.log(ngx.ERR,msg)
            return
        end
    end
end

local db, err
-- 判断 passive_Mod 是否开启
-- 被动扫描去重 在进行数据库的存放
if passive_Mod.state == "on" then
    -- 判断 ip 是否需要排除
    if passive_Mod.exclude_ips[base_msg.ip] then
        return
    end
    -- 排除扫描器
    if base_msg.headers["test"] == "scanner" then
        return
    end
    -- 过滤 其它请求 options（后续可以写成可配置的）
    if optl.remath_Invert(base_msg.method,{"OPTIONS","HEAD"},"list") then
        return
    end
    -- 判断 http_host 是否是一个合法的域名
    if base_msg.http_host == "" or not stool.isHost(base_msg.http_host) then
        return
    end

    -- 判断 静态资源需要排除
    for _,v in ipairs(passive_Mod.exclude_urls) do
        -- remath_Invert(_str , _re_str , _options , _Invert)
        if optl.remath_Invert(base_msg.uri,v[1],v[2],v[3]) then
            return
        end
    end
    -- 从 redis 拉去去重信息
    --方法 + 域名 + uri  hash?
    local str_hash
    if base_msg.method == "POST" or base_msg.method == "PUT" then
        local from , to = string.find(base_msg.http_content_type , "application/json" , 1 , true)
        if from then
            -- json 排除
            return
        end
        from , to = string.find(base_msg.http_content_type , "text/xml" , 1 , true)
        if from then
            -- xml 排除
            return
        end
        from , to = string.find(base_msg.http_content_type , "multipart/form-data" , 1 , true)
        if from then
            -- form 表单
            local p , err  = parser.new(base_msg.posts_all , base_msg.http_content_type , 10)
            local tmp_tb = {}
            if p then
                while true do
                    local part_body , name , mime , filename = p:parse_part()
                    if not part_body then
                        break
                    end
                    table.insert(tmp_tb , { name, filename, mime, part_body })
                end
            end
            local key_tb = {}
            for _,v in ipairs(tmp_tb) do
                table.insert(key_tb,tostring(v[1]))
            end
            local keys_str = "multipart/form-data:"..table.concat( key_tb, ",")
            str_hash = string.format("%s:%s%s:%s",base_msg.method,base_msg.http_host,base_msg.uri,keys_str)
        end
        from , to = string.find(base_msg.http_content_type , "x-www-form-urlencoded" , 1 , true)
        if from then
            -- 普通 post
            local tmp = {}
            for k,_ in pairs(ngx.req.get_post_args()) do
                table.insert(tmp,k)
            end
            table.sort(tmp)
            local keys_str = "x-www-form-urlencoded:"..table.concat( tmp, ",")
            -- POST:www.abc.com/aaa/p.do:x-www-form-urlencoded:xxxxxxxxxx
            -- POST:www.abc.com/aaa/p.do:multipart/form-data:xxxxxxxxxx
            -- POST:www.abc.com/aaa/p.do:application/json:xxxxxxxxxx
            -- $method:$host$uri:keys_str
            str_hash = string.format("%s:%s%s:%s",base_msg.method,base_msg.http_host,base_msg.uri,keys_str)
        end
    else
        local tmp = {}
        for k,_ in pairs(base_msg.args) do
            table.insert(tmp,k)
        end
        table.sort(tmp)
        local keys_str = table.concat( tmp, ",")
        -- GET:www.abc.com/aaa/i.do:XXXXXXX
        -- $method:$host$uri:keys_str
        str_hash = string.format("%s:%s%s:%s",base_msg.method,base_msg.http_host,base_msg.uri,keys_str)
    end
    local md5_str = ngx.md5(str_hash)
    local redis_Mod = passive_Mod.redis_Mod
    if redis_Mod.state == "on" then
        local red = redis:new()
        -- red:set_timeouts(2000,2000,2000) -- 1000 = 1秒
        red:set_timeout(2000)
        local re, err = red:connect(redis_Mod.ip, redis_Mod.Port)
        if not re then
            ngx.log(ngx.ERR, err)
            return
        end
        local count, err = red:get_reused_times()
        if 0 == count then
            if redis_Mod.Password ~= "" then
                local re, err = red:auth(redis_Mod.Password)
                if not re then
                    local _msg = "failed to auth: " .. tostring(err)
                    ngx.log(ngx.ERR, _msg)
                    return
                end
            end
        elseif err then
            local _msg = "failed to get reused times: " .. tostring(err)
            ngx.log(ngx.ERR, _msg)
            return
        end
        local res , err = red:get(md5_str)
        if res == ngx.null then
            local _msg = "key not found."
            ngx.log(ngx.ERR, _msg)
            return
        end
        if res then
            -- 发现重复信息
            return
        end
        local ok, err = red:set(md5_str, 1)
        if not ok then
            ngx.log(ngx.ERR, "failed to set dog: ", err)
            return
        end
    else
        -- 使用共享字典存放 (passive_dict) 去重对比数据（nginx -s stop 后字典数据会丢失！！！）
        local re = passive_dict:get(md5_str)
        if re then
            -- 已经存在
            return
        else
            passive_dict:set(md5_str,1,0)
        end
    end
    --
    db, err = mysql:new()
    if not db then
        local msg = "failed to instantiate mysql: ".. err
        ngx.log(ngx.ERR,msg)
        return
    end

    db:set_timeout(100000) -- 1 sec
    local ok, err, errcode, sqlstate = db:connect{
        host = passive_Mod.mysql.host,
        port = passive_Mod.mysql.port,
        database = passive_Mod.mysql.database,
        user = passive_Mod.mysql.user,
        password = passive_Mod.mysql.password,
        charset = passive_Mod.mysql.charset or ("utf8"),
        max_packet_size = 1024 * 1024,
    }

    if not ok then
        local msg = "failed to connect: ".. err.. ": "..errcode.. ": "..sqlstate
        ngx.log(ngx.ERR,msg)
        return
    end
    local payload = {}
    payload.scheme = base_msg.scheme
    payload.method = base_msg.method
    payload.headers = base_msg.headers
    payload.query_string = base_msg.query_string
    payload.posts_all = base_msg.posts_all
    local tmpsql = string.format("insert into mirror_copy (host,uri,remoteIp,payload,createTime) values('%s','%s','%s','%s','%s')",
        base_msg.http_host, ngx.encode_base64( base_msg.uri ),base_msg.remoteIp, ngx.encode_base64( stool.tableTojsonStr(payload) ), ngx.localtime())
    local res, err, errcode, sqlstate = db:query(tmpsql)
    if not res then
        local msg = "bad result: ".. err.. ": "..errcode.. ": "..sqlstate
        ngx.log(ngx.ERR,msg)
        return
    end

    ok, err = db:set_keepalive(100000, 1000)
    if not ok then
        ngx.log(ngx.ERR,"failed to set keepalive: ", err)
        return
    end
end