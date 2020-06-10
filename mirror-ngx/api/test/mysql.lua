

local optl = require("optl")
local mysql = require "resty.mysql"

local config = optl.config
local mysql_Mod = config.base.statistics_Mod.mysql

local db, err = mysql:new()
if not db then
    ngx.say("failed to instantiate mysql: ", err)
    return
end

db:set_timeout(10000) -- 1 sec

local ok, err, errcode, sqlstate = db:connect{
    host = mysql_Mod.host,
    port = mysql_Mod.port,
    database = mysql_Mod.database,
    user = mysql_Mod.user,
    password = mysql_Mod.password,
    charset = mysql_Mod.charset or ("utf8"),
    max_packet_size = 1024 * 1024,
}

if not ok then
    ngx.say("failed to connect: ", err, ": ", errcode, " ", sqlstate)
    return
end

ngx.say("connected to mysql.")


-- statistics_Mod 使用的 表需要创建
local res, err, errcode, sqlstate =
    db:query([=[CREATE TABLE IF NOT EXISTS realtime_host_uri_ip (
  id int auto_increment ,
  host VARCHAR(100) NOT NULL,
  uri VARCHAR(2000) NOT NULL,
  ip VARCHAR(50) NOT NULL,
  cnt  INT(10),
  ctime DATETIME NOT NULL,
  Ext1 INT(10),
  Ext2 VARCHAR(20),
  primary key (id),
  key idx_host(host),
  key idx_time(ctime),
  key idx_ip(ip)
) ENGINE=InnoDB comment '创建 域名 uri ip 表';
        ]=])
if not res then
    ngx.say("bad result: ", err, ": ", errcode, ": ", sqlstate, ".")
    return
end

ngx.say("table realtime_host_uri_ip created.")

-- passive_Mod 使用的 表需要创建

-- put it into the connection pool of size 100,
-- with 10 seconds max idle timeout
local ok, err = db:set_keepalive(10000, 100)
if not ok then
    ngx.say("failed to set keepalive: ", err)
    return
end