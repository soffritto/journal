# vim: ft=perl
use strict;
use warnings;
use Plack::Builder;
use Amon2::Lite;
use Path::Class;
use File::Temp;
use Email::MIME;
use Email::Date::Format;

{
    package Entry;
    use Text::Hatena;
    use Text::Markdown;
    use Time::Piece;
    use URI::WithBase;

    sub new { 
        my ($class, $file) = @_;
        $file or return;
        my $content = $file->slurp;
        my $mime = Email::MIME->new($content);
        my ($time, $id) = $mime->header('Message-ID') =~ m/^<(\d+)\.(\d+)\@.+>$/;
        bless {
            id => $id,
            subject => $mime->header('Subject'),
            file => $file,
            mime => $mime,
            posted_at => $time,
            body => $mime->body,
        }, $class;
    }
    sub param { $_[0]->{$_[1]} }
    sub updated { 
        my $self = shift;
        localtime($self->{posted_at});
    }
    sub short_body {
        my $self = shift;
        my $body = substr($self->{mime}->body, 0, 100);
        $body .= '...' if length($self->{mime}->body) > 100;
        return $body;
    }
    sub formatted_body {
        my $self = shift;
        if ($self->{mime}{ct}{subtype} eq 'hatena') {
            Text::Hatena->parse($self->{body});
        } elsif ($self->{mime}{ct}{subtype} eq 'markdown') {
            Text::Markdown::markdown($self->{body});
        } else {
            $self->{body};
        }
    }
    sub permalink {
        my ($self, $c) = @_;
        URI::WithBase->new(
            $c->uri_for("/entry/$self->{id}"), 
            $c->req->base
        )->abs->as_string;
    }
}

sub entry_file {
    my $id = shift;
    my ($item) = grep {$_->basename =~ m/^\d+\.$id\..+$/} __PACKAGE__->config->{datadir}->children;
    return $item;
}

sub render_page {
    my ($c, $page, $template) = @_;
    $template ||= 'page.tt';
    my @files = sort {$b cmp $a} $c->config->{datadir}->children;
    my @list = grep {defined} @files[10 * ($page - 1) .. 10 * $page - 1];
    scalar @list or return $c->res_404;
    my $has_next = defined($files[10 * $page]);
    $c->render(
        $template, 
        { 
            list => [map {Entry->new($_)} @list],
            pager => $has_next ? $page + 1 : undef
        }
    );
}

get '/' => sub {
    my ($c) = @_;
    render_page($c, 1);
};

get '/page/{page:\d+}' => sub {
    my ($c, $args) = @_;
    if ($args->{page} == 1) {
        return $c->redirect($c->uri_for('/'));
    }
    render_page($c, $args->{page});
};

get '/entry/{id:\d+}' => sub {
    my ($c, $args) = @_;
    my $item = entry_file($args->{id});
    my $pager = entry_file($args->{id} - 1) ? 1 : 0;
    $c->render(
        'entry.tt', 
        { 
            item => Entry->new($item),
            pager => $pager
        }
    );
};

get '/feed' => sub {
    my ($c) = @_;
    my $res = render_page($c, 1, 'feed.tt');
    $res->content_type('application/rss+xml; charset=utf-8');
    return $res;
};

__PACKAGE__->load_config($ENV{PLACK_ENV});

if (caller) {
    return builder {
        enable 'ReverseProxy';
        enable_if {
            join('', @{$_[0]}{qw(SCRIPT_NAME PATH_INFO)}) =~ m{^/writer}
        } 'Auth::Basic', authenticator => sub {
            my $config = __PACKAGE__->config;
            return $_[0] eq $config->{auth}{username} && $_[1] eq $config->{auth}{password};
        };
        __PACKAGE__->to_app(handle_static => 1);
    };
} else {
    my $fh = File::Temp->new;
    my $filename = $fh->filename;
    close $fh;
    system($ENV{EDITOR}, $filename);
    my $content = Path::Class::File->new($filename)->slurp(iomode => '<:encoding(utf8)');
    my $parsed = Email::MIME->new($content);
    my $subject = $parsed->header('Subject');
    my $body;
    if ($subject) {
        $body = $parsed->body;
    } else {
        $subject = '';
        $body = $content;
    }
    my $config = __PACKAGE__->config;
    my ($latest) = sort {$b cmp $a} $config->{datadir}->children;
    my ($latest_id) = $latest ? $latest->basename =~ m/^\d+\.(\d+)\..+/ : 0;
    my $id = $latest_id + 1;
    my $time = time;
    my $mime = Email::MIME->create(
        attributes => {
            content_type => 'text/markdown',
            encoding => '8bit',
            charset => 'utf8',
        },
        header_str => [
            From => $config->{author},
            Subject => $subject,
            Date => Email::Date::Format::email_date($time),
            'Message-ID' => sprintf('<%d.%d@%s>', $time, $id, $config->{hostname}),
        ],
        body_str => $body
    );
    $config->{datadir}->file(sprintf('%d.%d.%s', $time, $id, $config->{hostname}))->spew($mime->as_string);
}

__DATA__

@@ wrapper.tt
<html>
  <head>
    <title>[% c().config().title || 'my journal' %]</title>
    <meta http-equiv="Content-Style-Type" value="text/css" />
    <link rel="alternate" href="[% uri_for('/feed') %]" title="RSS" type="application/rss+xml" />
    <link rel="shortcut icon" href="http://soffritto.org/images/favicon.ico" />
    <link rel="stylesheet" href="[% uri_for('/static/style.css') %]" media="screen" type="text/css" />
  </head>
  <body>
    <div id="container">
      <div id="header"><h1 class="title"><a href="[% uri_for('/') %]">soffritto::journal</a></h1></div>
      <div id="main" class="autopagerize_page_element">
        [% content %]
      </div>
      <div id="footer" class="autopagerize_insert_before"></div>
  </body>
</html>

@@ item.tt

<div class="entry hentry">
  <h2 class="subject entry-title">
    <a rel="bookmark" href="/entry/[% entry.param('id') %]">[% entry.param('subject') %]</a>
  </h2>
  <div class="vcard author"><span class="fn">[% c().config().author || 'author unknown' %]</span></div>
  <div class="updated">[% entry.updated.strftime('%FT%T%z') %]</div>
  <div class="entry-content [% entry.param('format') %]">
    [% entry.formatted_body | raw %]
  </div>
</div>

@@ page.tt

[% WRAPPER 'wrapper.tt' %]
[% FOR item IN list %]
[% INCLUDE 'item.tt' WITH entry = item %]
[% END %]
[% IF pager %]<div class="pager"><a href="/page/[% pager %]">next</a></div>[% END %]
[% END %]

@@ entry.tt

[% WRAPPER 'wrapper.tt' %]
[% INCLUDE 'item.tt' WITH entry = item %]
[% IF pager %]<div class="pager"><a href="/entry/[% pager %]">next</a></div>[% END %]
[% END %]

@@ feed.tt

<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
  xmlns:blogChannel="http://backend.userland.com/blogChannelModule"
  xmlns:geo="http://www.w3.org/2003/01/geo/wgs84_pos#"
  xmlns:content="http://purl.org/rss/1.0/modules/content/"
  xmlns:atom="http://www.w3.org/2005/Atom"
  xmlns:dcterms="http://purl.org/dc/terms/"
  xmlns:dc="http://purl.org/dc/elements/1.1/"
>
<channel>
<title>[% c().config().title || 'my journal' %]</title>
<link>[% c().request.base.as_string %]</link>
<description>[% c().config().description || 'my great history' %]</description>
<atom:link href="[% c().request.uri %]" rel="self" type="application/rss+xml" />
[% FOR item IN list %]
<item>
<title>[% item.param('subject') %]</title>
<dc:creator>[% c().config().author || 'author unknown' %]</dc:creator>
<link>[% item.permalink(c()) %]</link>
<guid isPermaLink="true">[% item.permalink(c()) %]</guid>
<pubDate>[% item.updated.strftime('%a, %e %b %Y %H:%M:%S %z') %]</pubDate>
<description>[% item.short_body %]</description>
<content:encoded><![CDATA[
[% item.formatted_body |raw %]
]]></content:encoded>
</item>
[% END %]
</channel>
</rss>

@@ /static/style.css

* {
    font-family: "Lucida Grande", Verdana, Arial, Geneva, sans-serif;
    line-height: 2em;
    font-weight: normal;
    size: 90%;
    margin: 0;
    padding: 0;
}
body {
    margin: 30px;
    padding: 30px;
    border: 2px solid #FCC800;
}
a {
    text-decoration: none;
    color: #FCC800;
    border-bottom: 2px solid #FCC800;
    padding: 2px;
}
h1 a {
    display: block;
    background: url(http://soffritto.org/images/logo.png) no-repeat ;
    width: 100%;
    height: 60px;
    background-position: right top;
    text-decoration: none;
    text-align: left;
    border-bottom: none;
    text-indent: -9999px;
}
h2 {
    color: #FCC800;
}
dl, ul, dd {
    margin: 0px 30px;
}
#form_subject {
    display: block;
    width: 60em;
}
#form_body {
    display: block;
    width: 60em;
    height: 20em;
}
.entry, pre, q {
    margin-top: 25px;
    padding: 15px 25px;
    border: 2px solid #FCC800;
}
.updated, .author, .pager, .autopagerize_page_separator, .autopagerize_page_info {
    display: none;
}
.entry h2 a {
    border: none;
}
