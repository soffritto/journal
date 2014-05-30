create table entry (
    id int unsigned not null auto_increment primary key,
    subject text,
    body mediumtext,
    posted_at int unsigned not null,
    format varchar(16) not null default 'markdown'
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
