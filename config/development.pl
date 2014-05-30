{
    DBI => [
        'dbi:mysql:journal', 'root', '',
        {
            mysql_auto_reconnect => 1,
            mysql_enable_utf8 => 1,
        }
    ],
    title => 'Soffritto::Journal',
    auth => {
        username => 'username',
        password => 'password',
    },
}
