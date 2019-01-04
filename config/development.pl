use Path::Class;
{
    title => 'my journal',
    description => 'my great history',
    author => 'author unknown <info@example.com>',
    hostname => 'journal.example.com',
    datadir => Path::Class::File->new(__FILE__)->dir->parent->subdir('data')->absolute,
}
