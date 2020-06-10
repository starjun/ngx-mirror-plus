
local type = type
local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local tostring = tostring
local getmetatable = getmetatable
local setmetatable = setmetatable
local string_gmatch = string.gmatch
local string_sub = string.sub
local string_find = string.find
local string_lower = string.lower
local ngx_re_find = ngx.re.find
local table_remove = table.remove
local table_concat = table.concat
local table_insert = table.insert
local math_floor = math.floor
local io_open = io.open
local cjson_safe = require "cjson.safe"
local JSON = require "JSON"

local _M = {_VERSION = 0.1}

-- 快速判断 table 类型 （数组字典）
local function isArrayTable(t)
    if type(t) ~= "table" then
        return false
    end
    local n = #t
    for i,v in pairs(t) do
        if type(i) ~= "number" then
            return false
        end
        if math_floor(i)<i or i < 0 or i >n then
            return false
        end
    end
    return true
end
_M.isArrayTable = isArrayTable

-- 判断 传入的 _value 是否在 list 类型的 _tb 中
local function isInArrayTb(_value,_tb)
    if type(_tb) ~= "table" then return false end
    for _,v in ipairs(_tb) do
        if v == _value then
            return true
        end
    end
end
_M.isInArrayTb = isInArrayTb

-- split 分割函数
-- 新版openresty lua-resty-core 支持 split 函数
-- https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/re.md#split
local function split(inputstr, sep)
    sep = sep or "%s"
    local t={} ; i=1
    for str in string_gmatch(inputstr, "([^"..sep.."]+)") do
        t[i] = str
        i = i + 1
    end
    return t
end
_M.split = split

-- ["false","true"] 转 boolean
-- 只有 _str == 'true' 为 真，其余都为 假
local function strToBoolean(_str)
    if string_lower(_str) == "true" then
        return true
    else
        return false
    end
end
_M.strToBoolean = strToBoolean

-- 判断传入的 str 是否为一个合法的 点分ip
local function isIp(_str_ip)
    local re_ip = "^(1\\d{2}|2[0-4]\\d|25[0-5]|[1-9]\\d|[1-9])\\."
    re_ip = re_ip.."(1\\d{2}|2[0-4]\\d|25[0-5]|[1-9]\\d|\\d)\\."
    re_ip = re_ip.."(1\\d{2}|2[0-4]\\d|25[0-5]|[1-9]\\d|\\d)\\."
    re_ip = re_ip.."(1\\d{2}|2[0-4]\\d|25[0-5]|[1-9]\\d|\\d)$"
    local from, to = ngx_re_find(_str_ip, re_ip, "jios")
    if from ~= nil then
        return true
    end
end
_M.isIp = isIp

-- 判断传入的 str 是否是一个合法的 域名
local function isHost(_str_host)
    if isIp(_str_host) then
        return true
    end
    local tmp = {"localhost5460","localhost"}
    if isInArrayTb(_str_host,tmp) then
        return true
    end
    local re_host = "^(?=^.{3,255}$)[a-zA-Z0-9][-a-zA-Z0-9]{0,62}(\\.[a-zA-Z0-9][-a-zA-Z0-9]{0,62})+$"
    local from, to = ngx_re_find(_str_host, re_host, "jios")
    if from ~= nil then
        return true
    end
end
_M.isHost = isHost

-- 计算传入的 table 的count
local function getTableCount(t)
    local count = 0
    if isArrayTable(t) then
        count = #t
    else
        for _,v in pairs(t) do
            count = count + 1
        end
    end
    return count
end
_M.getTableCount = getTableCount

-- 从table中 获取key的值（支持@标记 获取子节点的值）
local function get_keyInTable(_tb,_k,_tag)
    _tag = _tag or "@"
    local tmp_v = _tb[_k]
    if tmp_v then
        return tmp_v
    end
    local listKey = split(_k,_tag)
    if #listKey == 1 then
        local tmp_k = tonumber(_k) or _k
        return _tb[tmp_k]
    else
        local tmp_k = tonumber(listKey[1]) or listKey[1]
        local _tmp = _tb[tmp_k]
        if type(_tmp) == "table" then
            -- 将后续的key进行拼接
            table_remove(listKey,1)
            local newKey = table_concat(listKey,_tag)
            return get_keyInTable(_tmp,newKey)
        else
            return _tmp
        end
    end
end
_M.get_keyInTable = get_keyInTable

-- 递归 对比两个 table 相等返回 true
local function table_compare(t1,t2,ignore_mt)
  local ty1 = type(t1)
  local ty2 = type(t2)
  if ty1 ~= ty2 then return false end
  -- non-table types can be directly compared
  if ty1 ~= 'table' and ty2 ~= 'table' then return t1 == t2 end
  -- as well as tables which have the metamethod __eq
  local mt = getmetatable(t1)
  if not ignore_mt and mt and mt.__eq then return t1 == t2 end
  for k1,v1 in pairs(t1) do
      local v2 = t2[k1]
      if v2 == nil or not table_compare(v1,v2) then return false end
  end
  for k2,v2 in pairs(t2) do
      local v1 = t1[k2]
      if v1 == nil or not table_compare(v1,v2) then return false end
  end
  return true
end
_M.table_compare = table_compare

-- table 深 copy (ismt 控制元表copy)
local function table_copy(orig,ismt)
    local copy
    if type(orig) == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[table_copy(orig_key)] = table_copy(orig_value)
        end
        if ismt then
            setmetatable(copy, table_copy(getmetatable(orig)))
        end
    else
        copy = orig
    end
    return copy
end
_M.table_copy = table_copy

local function stringStarts(String,Start)
   return string_sub(String,1,#Start)==Start
end
_M.stringStarts = stringStarts

local function stringEnds(String,End)
   return string_sub(String,-#End)==End
end
_M.stringEnds = stringEnds

local function stringIn(String,in_str)
    --- 用于包含 查找 string_find
    if not String or (not in_str or in_str == '') then return false end
    local from , to = string_find(String, in_str,1,true)
    if from ~= nil then
        return true
    end
end
_M.stringIn = stringIn

local function readfile(_filepath,_ty)
    local fd = io_open(_filepath,"r")
    if not fd then return end
    if not _ty then
        local str = fd:read("*a") --- 全部内容读取
        fd:close()
        return str
    else
        local line_s = {}
        for line in fd:lines() do
            table_insert(line_s, line)
        end
        fd:close()
        return line_s
    end
end
_M.readfile = readfile

local function writefile(_filepath,_msg,_ty)
    _ty = _ty or "a+"
    -- w+ 覆盖 | a+ 追加（默认）
    local fd,err = io_open(_filepath,_ty)
    if fd == nil then
        ngx.log(ngx.ERR,"writefile msg : "..tostring(_msg),err)
        return
    end -- 文件读取错误返回
    fd:write(tostring(_msg))
    fd:flush()
    fd:close()
    return true
end
_M.writefile = writefile

-- table转成json字符串
local function tableTojsonStr(_obj,_pretty)
    if _pretty then
        return JSON:encode_pretty(_obj)
    else
        return cjson_safe.encode(_obj)
    end
end
_M.tableTojsonStr = tableTojsonStr

-- 字符串转成序列化后的json同时也可当table类型
local function stringTojson(_obj)
    local json = cjson_safe.decode(_obj)
    return json
end
_M.stringTojson = stringTojson

local function loadjson(_path_name)
    local x    = readfile(_path_name)
    local json = stringTojson(x) or {}
    return json
end
_M.loadjson = loadjson

local function get_table(_tb)
    if type(_tb) ~= "table" then
        return ""
    end
    local tb_args = {}
    for k,v in pairs(_tb) do
        if type(v) == "table" then
            local tmp_v = {}
            for i,vv in ipairs(v) do
                if vv == true then
                    vv=""
                end
                table_insert(tmp_v,vv)
            end
            v = table_concat(tmp_v,",")
        elseif v == true then
            v= ""
        end
        table_insert(tb_args,v)
    end
    return table_concat(tb_args,",")
end
_M.get_table = get_table

return _M