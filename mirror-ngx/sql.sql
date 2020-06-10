

-- 统计表（域名-uri-ip  次数/12秒）
CREATE TABLE `realtime_host_uri_ip` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `host` varchar(100) NOT NULL,
  `uri` varchar(2000) NOT NULL,
  `ip` varchar(50) NOT NULL,
  `cnt` int(10) DEFAULT NULL,
  `ctime` datetime NOT NULL,
  `Ext1` int(10) DEFAULT NULL,
  `Ext2` varchar(20) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_host` (`host`),
  KEY `idx_time` (`ctime`),
  KEY `idx_ip` (`ip`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 COMMENT='创建 域名 uri ip 表';


-- 被动扫描记录的表
CREATE TABLE `mirror_copy` (
  `taskId` int(11) NOT NULL AUTO_INCREMENT,
  `uri` varchar(1000) DEFAULT NULL,
  `host` varchar(100) NOT NULL,
  `payload` varchar(5000) DEFAULT NULL,
  `remoteIp` varchar(20) DEFAULT NULL,
  `createTime` datetime NOT NULL,
  `startTime` datetime NOT NULL,
  `finishTime` datetime NOT NULL,
  `status` varchar(20) DEFAULT NULL,
  `Ext1` int(10) DEFAULT NULL,
  `Ext2` varchar(20) DEFAULT NULL,
  `id` int(11) DEFAULT NULL,
  PRIMARY KEY (`taskId`)
) ENGINE=InnoDB AUTO_INCREMENT=450232 DEFAULT CHARSET=utf8;