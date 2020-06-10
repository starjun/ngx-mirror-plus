
local config = {}
local stool  = require "stool"
local ngx_shared = ngx.shared
local io_open = io.open

--- base.json 文件绝对路径
local base_json = "/opt/openresty/mirror-ngx/conf_json/base.json"

--- 将全局配置参数存放到共享内存（*_dict）中
local config_dict = ngx_shared.config_dict

--- 载入 base.json全局基础配置
--- 唯一一个全局函数
function loadConfig()
    config.base = stool.loadjson(base_json)
    config_dict:safe_set("config",stool.tableTojsonStr(config),0)
    config_dict:safe_set("config_version",0,0)
end

loadConfig()
-- G_filehandler = io_open(config.base.logPath..(config.base.log_conf.filename or "mirror-ngx.log"),"a+")


