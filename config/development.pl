{
    DBI => [
        'dbi:mysql:journal', 'root', '',
        {
            mysql_auto_reconnect => 1,
            mysql_enable_utf8 => 1,
        }
    ],
    title => 'my journal',
    description => 'my great history',
    author => 'author unknown',
    auth => {
        username => 'username',
        password => 'password',
    },
}
